mod export;
pub mod replica;

use std::{io::Seek, path::Path};

use anyhow::{Context, Result, ensure};
use ente_core::Session;
use ente_photos::files;
use serde_json::json;

use crate::{
    api,
    args::{AlbumCommand, App, FileCommand, Options, PhotosCommand},
    core_db::SqliteResult,
    db, home,
    output::{self, AlbumView, FileView, MAX_CANDIDATES, select},
};
use replica::Replica;

pub async fn run(command: PhotosCommand, selected: Option<&str>, options: &Options) -> Result<()> {
    match command {
        PhotosCommand::Api(args) => return api::run(App::Photos, args, selected, options).await,
        PhotosCommand::Export(args) => return export::run(args, selected, options).await,
        _ => {}
    }
    ensure!(
        !options.offline
            || !matches!(
                &command,
                PhotosCommand::File {
                    command: FileCommand::Download { .. },
                    ..
                }
            ),
        "original files are not stored locally; download requires network access"
    );
    let (account, home) = home::open_account(selected, !options.offline)?;
    let session = api::session(&account, App::Photos)?;
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
        PhotosCommand::Api(_) | PhotosCommand::Export(_) => unreachable!(),
        PhotosCommand::Album { command } => album(command, &replica, options),
        PhotosCommand::File { album, command } => {
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
                    select(
                        rows.collect::<SqliteResult<Vec<_>>>()?,
                        &album,
                        "album",
                        "Use an ID.",
                        |a| (a.id, a.name.as_deref().unwrap_or("unavailable").to_owned()),
                    )
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
                let entry = select(
                    rows.collect::<SqliteResult<Vec<_>>>()?,
                    selector,
                    "album",
                    "Use an ID.",
                    |a| (a.id, a.name.as_deref().unwrap_or("unavailable").to_owned()),
                )?;
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
                select(
                    rows.collect::<SqliteResult<Vec<_>>>()?,
                    selector,
                    "file",
                    "Use an ID.",
                    |e| (e.id, e.name.as_deref().unwrap_or("unavailable").to_owned()),
                )
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
