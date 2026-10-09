use std::{io::Seek, path::Path};

use anyhow::{Context, Result, bail, ensure};
use ente_core::Session;
use ente_photos::files;
use serde_json::json;

use crate::{
    api,
    args::{AlbumCommand, FileCommand, Options, PhotosLibraryCommand, Product},
    db, home,
    output::{self, AlbumView, FileView},
    replica::Replica,
};

const MAX_CANDIDATES: usize = 10;

pub async fn run(
    command: PhotosLibraryCommand,
    selected: Option<&str>,
    options: &Options,
) -> Result<()> {
    if let PhotosLibraryCommand::Export(args) = command {
        return crate::export::run(args, selected, options).await;
    }
    ensure!(
        !options.offline
            || !matches!(
                &command,
                PhotosLibraryCommand::File {
                    command: FileCommand::Download { .. },
                    ..
                }
            ),
        "original files are not stored locally; download requires network access"
    );
    let (account, home) = home::open_account(selected, !options.offline)?;
    let session = api::session(&account, Product::Photos)?;
    let mut db = db::open(&home.path, &account.db_key, !options.offline)?;
    let mut replica = Replica::new(&mut db, session.user_id);
    if !options.offline {
        replica.sync_collections(&session).await?;
        replica.retry_failed_albums(&session)?;
    } else {
        ensure!(
            replica.collections_cursor()?.is_some(),
            "no local Photos data; run the command online first"
        );
    }
    match command {
        PhotosLibraryCommand::Export(_) => unreachable!(),
        PhotosLibraryCommand::Album { command } => album(command, &replica, options),
        PhotosLibraryCommand::File { album, command } => {
            file(command, album.as_deref(), &session, &mut replica, options).await
        }
    }
}

fn album(command: AlbumCommand, replica: &Replica<'_>, options: &Options) -> Result<()> {
    match command {
        AlbumCommand::List(args) => replica.collections(None, None, |rows| {
            let mut incomplete = false;
            let albums = rows.filter_map(|row| {
                let entry = match row {
                    Ok(entry) => entry,
                    Err(error) => return Some(Err(error.into())),
                };
                match entry.value.and_then(AlbumView::try_from) {
                    Ok(album) => Some(Ok(album)),
                    Err(error) => {
                        eprintln!("album {}: {error:#}", entry.id);
                        incomplete = true;
                        None
                    }
                }
            });
            output::albums(albums, &args, options.json)?;
            ensure!(!incomplete, "album list is incomplete");
            Ok(())
        }),
        AlbumCommand::View { album } => {
            let album =
                replica.collections(Some(&album), Some((MAX_CANDIDATES + 1) as i64), |rows| {
                    select(rows.map(|album| Ok(album?)), &album, "album", |a| {
                        (a.id, a.name.as_deref().unwrap_or("unavailable"))
                    })
                })?;
            let album = album
                .value
                .and_then(AlbumView::try_from)
                .with_context(|| format!("album {}", album.id))?;
            if options.json {
                output::json(&album)
            } else {
                output::album(&album)
            }
        }
    }
}

async fn file(
    command: FileCommand,
    album: Option<&str>,
    session: &Session,
    replica: &mut Replica<'_>,
    options: &Options,
) -> Result<()> {
    let mut incomplete = false;
    let albums =
        replica.collections(album, album.map(|_| (MAX_CANDIDATES + 1) as i64), |rows| {
            if let Some(selector) = album {
                let entry = select(rows.map(|album| Ok(album?)), selector, "album", |a| {
                    (a.id, a.name.as_deref().unwrap_or("unavailable"))
                })?;
                Ok(vec![
                    entry.value.with_context(|| format!("album {}", entry.id))?,
                ])
            } else {
                let mut albums = Vec::new();
                for row in rows {
                    let entry = row?;
                    match entry.value {
                        Ok(album) => albums.push(album),
                        Err(error) => {
                            eprintln!("album {}: {error:#}", entry.id);
                            incomplete = true;
                        }
                    }
                }
                Ok(albums)
            }
        })?;
    if options.offline {
        for album in &albums {
            ensure!(
                replica.files_synced_to(album.id)?.is_some(),
                "files for album {:?} have not finished syncing; run the command online first",
                album.name
            );
        }
    } else {
        replica.sync_files(session, &albums).await?;
    }
    let album_id = album.map(|_| albums[0].id);
    let find = |selector: &str| {
        let entry = replica.files(
            album_id,
            Some(selector),
            Some((MAX_CANDIDATES + 1) as i64),
            |rows| {
                select(rows.map(|entry| Ok(entry?)), selector, "file", |e| {
                    (e.id, e.name.as_deref().unwrap_or("unavailable"))
                })
            },
        )?;
        let file = entry.file.with_context(|| format!("file {}", entry.id))?;
        Ok::<_, anyhow::Error>((file, entry.album_ids))
    };
    match command {
        FileCommand::List(args) => replica.files(album_id, None, None, |rows| {
            let files = rows.filter_map(|row| {
                let entry = match row {
                    Ok(entry) => entry,
                    Err(error) => return Some(Err(error.into())),
                };
                match entry
                    .file
                    .and_then(|file| FileView::new(file, &entry.album_ids))
                {
                    Ok(file) => Some(Ok(file)),
                    Err(error) => {
                        eprintln!("file {}: {error:#}", entry.id);
                        incomplete = true;
                        None
                    }
                }
            });
            output::files(files, &args, options.json)
        }),
        FileCommand::View { file } => {
            let (file, album_ids) = find(&file)?;
            let id = file.id;
            let view = FileView::new(file, &album_ids).with_context(|| format!("file {id}"))?;
            if options.json {
                output::json(&view)
            } else {
                output::file(&view)
            }
        }
        FileCommand::Download { file, output } => {
            ensure!(
                !incomplete,
                "album lookup is incomplete; select an available album with --album before downloading"
            );
            let (file, _) = find(&file)?;
            let parent = output
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
                .unwrap_or(Path::new("."));
            let mut temporary = tempfile::NamedTempFile::new_in(parent)
                .with_context(|| format!("cannot prepare download to {}", output.display()))?;
            files::download(session, file.id, &file.key, &file.header, || {
                let file = temporary.as_file_mut();
                file.set_len(0)?;
                file.rewind()?;
                file.try_clone()
            })
            .await
            .with_context(|| format!("cannot download file {}", file.id))?;
            temporary
                .as_file()
                .sync_all()
                .with_context(|| format!("cannot sync download to {}", output.display()))?;
            let bytes = temporary.as_file().metadata()?.len();
            temporary
                .persist_noclobber(&output)
                .map_err(|error| error.error)
                .with_context(|| format!("cannot save download to {}", output.display()))?;
            output::action(
                options.json,
                &json!({ "id": file.id.to_string(), "output": output.to_string_lossy(), "bytes": bytes }),
                &format!("Downloaded {:?} to {}.", file.name, output.display()),
            )
        }
    }?;
    ensure!(!incomplete, "file results are incomplete");
    Ok(())
}

fn select<T>(
    items: impl Iterator<Item = Result<T>>,
    selector: &str,
    kind: &str,
    identity: impl Fn(&T) -> (i64, &str),
) -> Result<T> {
    let mut matches = items.take(MAX_CANDIDATES + 1).collect::<Result<Vec<_>>>()?;
    if matches.len() > 1 {
        let candidates = matches
            .iter()
            .take(MAX_CANDIDATES)
            .map(|item| {
                let (id, name) = identity(item);
                format!("  {id}  {name:?}")
            })
            .collect::<Vec<_>>()
            .join("\n");
        let more = if matches.len() > MAX_CANDIDATES {
            "\nMore matches omitted; use an ID."
        } else {
            ""
        };
        bail!("{kind} {selector:?} is ambiguous:\n{candidates}{more}");
    }
    matches
        .pop()
        .with_context(|| format!("no {kind} matches {selector:?}"))
}
