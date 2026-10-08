use std::{
    fs::File,
    io::{Seek, SeekFrom},
};

use crate::{metadata::Role, snapshot::FileSnapshot};
use anyhow::{Context, Result, ensure};
use ente_core::{Session, b64, crypto::hash};
use ente_photos::files;
use rusqlite::{OptionalExtension, params};

use super::{
    fs::{self, HashWriter},
    names,
    reconcile::Run,
    store::{self, Component, Location, Properties},
};

pub struct Source {
    pub role: Role,
    pub extension: String,
    pub location: Location,
    pub size: u64,
    pub hash: String,
    pub temporary: bool,
}

pub struct Prepared {
    pub signature: String,
    pub components: Vec<Source>,
    pub observed: Vec<(i64, Vec<(Role, Properties)>)>,
}

pub fn roles(file: &FileSnapshot) -> Vec<Role> {
    if file.kind == "livephoto" {
        vec![Role::Image, Role::Video]
    } else {
        vec![Role::Original]
    }
}

fn source_changed(component: &Component, file: &FileSnapshot, signature: &str) -> bool {
    !roles(file).contains(&component.role)
        || expected_hash(file, &component.role).is_some_and(|hash| hash != component.hash)
        || (expected_hash(file, &component.role).is_none()
            && component
                .signature
                .as_ref()
                .is_some_and(|original| original != signature))
}

fn verify(run: &Run<'_>, component: &Component, replacing: bool) -> Result<Option<Properties>> {
    let path = run.path(&component.location)?;
    let Some(properties) = Properties::optional(&path)? else {
        return Ok(None);
    };
    if replacing || component.properties.as_ref() != Some(&properties) {
        ensure!(
            fs::matches(&path, component.size, &component.hash, run.cancel)?,
            super::Conflict(format!("at {}: locally changed media", path.display()))
        );
    }
    Ok(Some(properties))
}

pub async fn prepare(run: &Run<'_>, session: &Session, file: &FileSnapshot) -> Result<Prepared> {
    let signature = signature(file)?;
    let roles = roles(file);
    let mut observed = Vec::new();
    let mut needs_bytes = false;
    let mut after = 0;
    loop {
        run.check_cancel()?;
        let album: Option<i64> = store::lock(run.store)?
            .db
            .query_row(
                "SELECT album FROM desired_files WHERE file=?1 AND album>?2 AND failure IS NULL ORDER BY album LIMIT 1",
                params![file.id, after],
                |r| r.get(0),
            )
            .optional()?;
        let Some(album) = album else {
            break;
        };
        after = album;
        let result = (|| {
            let (components, retained_folder) = {
                let store = store::lock(run.store)?;
                let retained_folder = store
                    .pending_file(album, file.id)?
                    .filter(|pending| pending.retained)
                    .map(|pending| pending.folder);
                let components = store
                    .placement(album, file.id)?
                    .map(|placement| store.components(&placement.id))
                    .transpose()?
                    .unwrap_or_default();
                (components, retained_folder)
            };
            let mut verified = Vec::new();
            let replacing = components
                .iter()
                .any(|component| source_changed(component, file, &signature));
            for component in &components {
                if retained_folder.as_ref() == Some(&component.location.folder) {
                    continue;
                }
                if let Some(properties) = verify(run, component, replacing)?
                    && !source_changed(component, file, &signature)
                {
                    verified.push((component.role.clone(), properties));
                }
            }
            needs_bytes |= roles
                .iter()
                .any(|role| !verified.iter().any(|(verified, _)| role == verified));
            observed.push((album, verified));
            Ok(())
        })();
        if let Err(error) = result {
            run.block(album, Some(file.id), error)?;
        }
    }
    if !needs_bytes {
        return Ok(Prepared {
            signature,
            components: Vec::new(),
            observed,
        });
    }
    let mut reusable = Vec::new();
    let mut before = i64::MAX;
    loop {
        run.check_cancel()?;
        if roles
            .iter()
            .all(|role| reusable.iter().any(|source: &Source| source.role == *role))
        {
            break;
        }
        let next: Option<(i64, String)> = store::lock(run.store)?
            .db
            .query_row(
                "SELECT rowid,id FROM placements WHERE file=?1 AND rowid<?2 ORDER BY rowid DESC LIMIT 1",
                params![file.id, before],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        let Some((rowid, id)) = next else {
            break;
        };
        before = rowid;
        let components = store::lock(run.store)?.components(&id)?;
        for component in components {
            if !roles.contains(&component.role)
                || reusable.iter().any(|source| source.role == component.role)
                || expected_hash(file, &component.role).is_some_and(|hash| hash != component.hash)
                || (expected_hash(file, &component.role).is_none()
                    && component
                        .signature
                        .as_ref()
                        .is_some_and(|original| original != &signature))
            {
                continue;
            }
            let valid = (|| {
                let path = run.path(&component.location)?;
                Properties::read(&path)?;
                fs::matches(&path, component.size, &component.hash, run.cancel)
            })();
            match valid {
                Ok(true) => reusable.push(Source {
                    role: component.role,
                    extension: names::split(&component.location.name, false).1.into(),
                    location: component.location,
                    size: component.size,
                    hash: component.hash,
                    temporary: false,
                }),
                Err(error) if super::fatal(&error) => return Err(error),
                _ => {}
            }
        }
    }
    if roles
        .iter()
        .all(|role| reusable.iter().any(|source| source.role == *role))
    {
        reusable.sort_by_key(|source| roles.iter().position(|role| *role == source.role));
        return Ok(Prepared {
            signature,
            components: reusable,
            observed,
        });
    }
    after = 0;
    let (folder, album, temporary, output) = loop {
        let album: Option<i64> = store::lock(run.store)?
            .db
            .query_row(
                "SELECT album FROM desired_files WHERE file=?1 AND album>?2 AND failure IS NULL ORDER BY album LIMIT 1",
                params![file.id, after],
                |r| r.get(0),
            )
            .optional()?;
        let Some(album) = album else {
            return Ok(Prepared {
                signature,
                components: Vec::new(),
                observed,
            });
        };
        after = album;
        let folder = store::lock(run.store)?
            .album(album, false)?
            .context("missing destination album")?
            .key;
        match run.temporary(&folder, album, Some(file.id)) {
            Ok((temporary, output)) => break (folder, album, temporary, output),
            Err(error) => run.block(album, Some(file.id), error)?,
        }
    };
    drop(output);
    let path = run.path(&temporary)?;
    let mut cancel = run.cancel.clone();
    let download = files::download(session, file.id, &file.key, &file.header, || {
        let mut output = File::options().read(true).write(true).open(&path)?;
        output.set_len(0)?;
        output.seek(SeekFrom::Start(0))?;
        HashWriter::new(output, run.cancel).map_err(std::io::Error::other)
    });
    let writer = tokio::select! { result=download => result?, _=cancel.changed() => return Err(super::Cancelled.into()) };
    let (archive, size, hash) = writer.finish()?;
    let components = if file.kind == "livephoto" {
        let mut temporaries = Vec::new();
        let extracted = crate::live_photo::extract(archive, |role, extension| {
            let (temporary, file) = run
                .temporary(&folder, album, Some(file.id))
                .map_err(std::io::Error::other)?;
            temporaries.push((role, extension.to_owned(), temporary));
            HashWriter::new(file, run.cancel).map_err(std::io::Error::other)
        })?;
        let mut components = Vec::with_capacity(2);
        for ((role, extension, writer), (_, _, temporary)) in extracted.into_iter().zip(temporaries)
        {
            let (_, size, hash) = writer.finish()?;
            if let Some(expected) = expected_hash(file, &role) {
                ensure!(
                    hash == expected,
                    "original component hash does not match source for file {}",
                    file.id
                );
            }
            components.push(Source {
                role,
                extension,
                location: temporary,
                size,
                hash,
                temporary: true,
            });
        }
        run.discard(&temporary)?;
        components
    } else {
        drop(archive);
        if let Some(expected) = &file.hash {
            ensure!(
                hash == *expected,
                "original hash does not match source for file {}",
                file.id
            );
        }
        vec![Source {
            role: Role::Original,
            extension: names::split(&file.name, false).1.into(),
            location: temporary,
            size,
            hash,
            temporary: true,
        }]
    };
    Ok(Prepared {
        signature,
        components,
        observed,
    })
}
pub fn signature(file: &FileSnapshot) -> Result<String> {
    let mut bytes = file.header.as_bytes().to_vec();
    bytes.extend_from_slice(file.hash.as_deref().unwrap_or_default().as_bytes());
    Ok(b64::encode(&hash::hash(
        &bytes,
        Some(32),
        Some(file.key.as_bytes()),
    )?))
}

pub fn expected_hash<'a>(file: &'a FileSnapshot, role: &Role) -> Option<&'a str> {
    let hash = file.hash.as_deref()?;
    match role {
        Role::Original => Some(hash),
        Role::Image => hash.split_once(':').map(|pair| pair.0),
        Role::Video => hash.split_once(':').map(|pair| pair.1),
    }
}
