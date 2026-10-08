use crate::{
    adopt::{self, Item},
    fs,
    metadata::{self, Role},
    names,
    snapshot::FileSnapshot,
    store::{Album, Component, JsonRecord, Location, Properties},
    transfer,
};
use anyhow::{Context, Result, ensure};
use ente_core::{Session, b64, crypto::hash::HashState};
use ente_photos::files;
use std::{
    io::{self, Seek, SeekFrom, Write},
    path::Path,
};
use tokio::sync::watch;

pub async fn file(
    check: &super::Preflight<'_>,
    album: &Album,
    item: &mut Item,
    source: &FileSnapshot,
    expected: &mut Option<Result<Vec<(Role, String)>, String>>,
) -> Result<usize> {
    let record = item.legacy.as_ref().context("missing legacy record")?;
    let roles = transfer::roles(source);
    ensure!(
        source.kind == "livephoto" || record.parts.len() == 1,
        "ordinary file has multiple legacy components"
    );
    ensure!(
        source.hash.is_none()
            || roles
                .iter()
                .all(|role| transfer::expected_hash(source, role).is_some_and(valid_hash)),
        "invalid authenticated source hash"
    );
    ensure!(
        record.parts.len() == 1
            || record.parts[0].role.is_none()
            || record.parts[0].role != record.parts[1].role,
        "duplicate legacy component role"
    );
    let mut measured = Vec::new();
    for part in &record.parts {
        let path = names::check(check.root, &format!("{}/{}", album.path, part.name))?;
        measured.push(
            Properties::optional(&path)?
                .map(|properties| {
                    let (size, hash) = fs::hash_cancellable(&path, check.cancel)?;
                    Ok::<_, anyhow::Error>((size, hash, properties))
                })
                .transpose()?,
        );
    }
    let present = measured.iter().filter(|p| p.is_some()).count();
    if present > 0 && expected.is_none() {
        match hashes(check.root, source, check.session, check.cancel).await {
            Ok(hashes) => *expected = Some(Ok(hashes)),
            Err(error) => {
                if crate::fatal(&error) {
                    return Err(error);
                }
                *expected = Some(Err(format!("{error:#}")));
            }
        }
    }
    let known = if present > 0 {
        expected
            .as_ref()
            .context("missing comparison")?
            .as_ref()
            .map_err(|error| anyhow::anyhow!("{error}"))?
            .clone()
    } else {
        roles
            .iter()
            .filter_map(|r| transfer::expected_hash(source, r).map(|h| (r.clone(), h.to_owned())))
            .collect()
    };
    let complete = present == roles.len();
    item.leftover = !complete && (source.kind == "livephoto" || record.desktop);
    item.placement.kind = source.kind.clone();
    if record.desktop {
        item.placement.name = source.name.clone();
    }
    for (index, part) in record.parts.iter().enumerate() {
        let role = part.role.clone().or_else(|| {
            if roles.len() == 1 {
                Some(Role::Original)
            } else if record.parts.len() == 2 {
                Some(roles[index].clone())
            } else {
                None
            }
        });
        ensure!(
            role.as_ref().is_none_or(|r| roles.contains(r)),
            "legacy component role disagrees with source"
        );
        if let Some((size, hash, properties)) = &measured[index] {
            ensure!(
                known
                    .iter()
                    .any(|(r, h)| role.as_ref().is_none_or(|own| own == r) && h == hash),
                "changed original at {}/{}",
                album.path,
                part.name
            );
            if complete {
                let role = role.context("missing complete component role")?;
                ensure!(
                    !item.components.iter().any(|c| c.role == role),
                    "duplicate legacy component role"
                );
                item.components.push(Component {
                    placement: item.placement.id.clone(),
                    role,
                    location: Location {
                        folder: album.key.clone(),
                        name: part.name.clone(),
                    },
                    size: *size,
                    hash: hash.clone(),
                    signature: Some(transfer::signature(source)?),
                    properties: Some(properties.clone()),
                    intended_time: None,
                });
            }
        }
    }
    for (role, hash) in &known {
        if let Some(legacy) = legacy_hash(record.hash.as_deref(), role) {
            ensure!(
                legacy == hash,
                "legacy hash contradicts the {} component",
                role.name()
            );
        }
    }
    if complete {
        let layout: Vec<_> = item.components.iter().map(Component::portable).collect();
        let favorited = check.store.db.query_row(
            "SELECT favorited FROM desired_files WHERE album=?1 AND file=?2",
            rusqlite::params![record.album, record.file],
            |r| r.get(0),
        )?;
        for (index, component) in item.components.iter().enumerate() {
            let name = format!("metadata/{}.json", component.location.name);
            let path = names::check(check.root, &format!("{}/{name}", album.path))?;
            let properties = Properties::optional(&path)?;
            ensure!(
                record.desktop || properties.is_none(),
                "required metadata path is occupied"
            );
            let hash = properties
                .as_ref()
                .map(|_| adopt::digest(&std::fs::read(&path)?))
                .transpose()?;
            item.json.push(JsonRecord {
                owner: item.placement.id.clone(),
                role: Some(component.role.clone()),
                location: properties.as_ref().map(|_| Location {
                    folder: album.key.clone(),
                    name,
                }),
                value: metadata::publish(&source.metadata, &layout, index, favorited)?,
                hash,
                properties,
            });
        }
    }
    Ok(present)
}

fn valid_hash(hash: &str) -> bool {
    b64::decode(hash).is_ok_and(|bytes| bytes.len() == 64)
}

fn legacy_hash<'a>(hash: Option<&'a str>, role: &Role) -> Option<&'a str> {
    let hash = hash?;
    let hash = match role {
        Role::Original => hash,
        Role::Image => hash.split_once(':')?.0,
        Role::Video => hash.split_once(':')?.1,
    };
    valid_hash(hash).then_some(hash)
}

async fn hashes(
    root: &Path,
    file: &FileSnapshot,
    session: &Session,
    cancel: &watch::Receiver<bool>,
) -> Result<Vec<(Role, String)>> {
    let roles = transfer::roles(file);
    let known: Option<Vec<_>> = roles
        .iter()
        .map(|role| transfer::expected_hash(file, role).map(|hash| (role.clone(), hash.to_owned())))
        .collect();
    if let Some(known) = known {
        return Ok(known);
    }
    let mut receiver = cancel.clone();
    let hashes = if file.kind == "livephoto" {
        let scratch = tempfile::tempfile_in(root)?;
        let download = files::download(session, file.id, &file.key, &file.header, || {
            let mut file = scratch.try_clone()?;
            file.set_len(0)?;
            file.seek(SeekFrom::Start(0))?;
            Ok(file)
        });
        let archive = tokio::select! { result=download=>result?, _=receiver.changed()=>return Err(crate::Cancelled.into()) };
        crate::live_photo::extract(archive, |_, _| {
            Digest::new(cancel).map_err(io::Error::other)
        })?
        .into_iter()
        .map(|(role, _, writer)| Ok((role, writer.finish()?)))
        .collect::<Result<Vec<_>>>()?
    } else {
        let download = files::download(session, file.id, &file.key, &file.header, || {
            Digest::new(cancel).map_err(io::Error::other)
        });
        let writer = tokio::select! { result=download=>result?, _=receiver.changed()=>return Err(crate::Cancelled.into()) };
        vec![(Role::Original, writer.finish()?)]
    };
    Ok(hashes)
}

struct Digest {
    state: HashState,
    cancel: watch::Receiver<bool>,
}

impl Digest {
    fn new(cancel: &watch::Receiver<bool>) -> Result<Self> {
        Ok(Self {
            state: HashState::new(Some(64), None)?,
            cancel: cancel.clone(),
        })
    }
    fn finish(self) -> Result<String> {
        Ok(b64::encode(&self.state.finalize()?))
    }
}

impl Write for Digest {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if *self.cancel.borrow() {
            return Err(io::Error::other(crate::Cancelled));
        }
        self.state.update(bytes).map_err(io::Error::other)?;
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
