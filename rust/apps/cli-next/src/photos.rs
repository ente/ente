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
    vault::{Account, State},
};

const MAX_CANDIDATES: usize = 10;

pub async fn run(
    command: PhotosLibraryCommand,
    selected: Option<&str>,
    options: &Options,
) -> Result<()> {
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
    let (account, home) = open_account(selected, !options.offline)?;
    let session = api::session(&account, Product::Photos)?;
    let mut db = db::open(&home.path, &account.db_key, !options.offline)?;
    let mut replica = Replica::new(&mut db);
    if !options.offline {
        replica.sync_collections(&session).await?;
    } else {
        ensure!(
            replica.collections_cursor()?.is_some(),
            "no local Photos data; run the command online first"
        );
    }
    match command {
        PhotosLibraryCommand::Album { command } => album(command, &replica, options),
        PhotosLibraryCommand::File { album, command } => {
            file(command, album.as_deref(), &session, &mut replica, options).await
        }
    }
}

fn album(command: AlbumCommand, replica: &Replica<'_>, options: &Options) -> Result<()> {
    match command {
        AlbumCommand::List(args) => replica.collections(
            None,
            args.limit().map(|limit| i64::from(limit) + 1),
            |rows| {
                output::albums(
                    rows.map(|album| AlbumView::try_from(album?)),
                    &args,
                    options.json,
                )
            },
        ),
        AlbumCommand::View { album } => {
            let album =
                replica.collections(Some(&album), Some((MAX_CANDIDATES + 1) as i64), |rows| {
                    select(rows.map(|album| Ok(album?)), &album, "album", |a| {
                        (a.id, &a.name)
                    })
                })?;
            let album = AlbumView::try_from(album)?;
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
    let albums =
        replica.collections(album, album.map(|_| (MAX_CANDIDATES + 1) as i64), |rows| {
            if let Some(selector) = album {
                Ok(vec![select(
                    rows.map(|album| Ok(album?)),
                    selector,
                    "album",
                    |a| (a.id, &a.name),
                )?])
            } else {
                rows.map(|album| Ok(album?)).collect::<Result<Vec<_>>>()
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
        replica.files(
            album_id,
            Some(selector),
            Some((MAX_CANDIDATES + 1) as i64),
            |rows| {
                select(rows.map(|entry| Ok(entry?)), selector, "file", |e| {
                    (e.file.id, &e.file.name)
                })
            },
        )
    };
    match command {
        FileCommand::List(args) => replica.files(
            album_id,
            None,
            args.limit().map(|limit| i64::from(limit) + 1),
            |rows| {
                output::files(
                    rows.map(|entry| {
                        let entry = entry?;
                        FileView::new(entry.file, &entry.album_ids)
                    }),
                    &args,
                    options.json,
                )
            },
        ),
        FileCommand::View { file } => {
            let entry = find(&file)?;
            let view = FileView::new(entry.file, &entry.album_ids)?;
            if options.json {
                output::json(&view)
            } else {
                output::file(&view)
            }
        }
        FileCommand::Download { file, output } => {
            let entry = find(&file)?;
            let parent = output
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
                .unwrap_or(Path::new("."));
            let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
            files::download(session, &entry.file, || {
                let file = temporary.as_file_mut();
                file.set_len(0)?;
                file.rewind()?;
                file.try_clone()
            })
            .await?;
            temporary.as_file().sync_all()?;
            let bytes = temporary.as_file().metadata()?.len();
            temporary
                .persist_noclobber(&output)
                .map_err(|error| error.error)
                .with_context(|| format!("cannot save download to {}", output.display()))?;
            output::action(
                options.json,
                &json!({ "id": entry.file.id.to_string(), "output": output, "bytes": bytes }),
                &format!("Downloaded {:?} to {}.", entry.file.name, output.display()),
            )
        }
    }
}

fn open_account(selected: Option<&str>, create: bool) -> Result<(Account, home::AccountHome)> {
    let state = State::load()?;
    let id = state.accounts[state.resolve(selected)?].storage_id;
    let home = home::lock_account(id, create)?;
    let Some(account) = State::load()?
        .accounts
        .into_iter()
        .find(|account| account.storage_id == id)
    else {
        home.remove()?;
        bail!("account was removed while waiting for access");
    };
    if create {
        home::create(&home.path)?;
    }
    Ok((account, home))
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
