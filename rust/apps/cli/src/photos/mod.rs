mod export;
mod places;
pub mod replica;

use std::{cmp::Ordering, io::Seek, path::Path};

use anyhow::{Context, Result, ensure};
use ente_core::Session;
use ente_location::Coordinate;
use ente_photos::files::{self, File, Kind};
use serde_json::json;

use crate::{
    api,
    args::{
        AlbumCommand, App, FileCommand, FileQuery, FileSort, FileType, Options, PhotosCommand,
        PlaceCommand,
    },
    core_db::SqliteResult,
    db, home,
    output::{self, AlbumView, FileView, MAX_CANDIDATES, select},
    usage,
};
use replica::Replica;

pub async fn run(command: PhotosCommand, selected: Option<&str>, options: &Options) -> Result<()> {
    match command {
        PhotosCommand::Api(args) => return api::run(App::Photos, args, selected, options).await,
        PhotosCommand::Export(args) => return export::run(args, selected, options).await,
        PhotosCommand::Usage => return usage::photos(selected, options).await,
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
        PhotosCommand::Api(_) | PhotosCommand::Export(_) | PhotosCommand::Usage => unreachable!(),
        PhotosCommand::Album { command } => album(command, &replica, options),
        PhotosCommand::File { album, command } => {
            file(command, album.as_deref(), &session, &mut replica, options).await
        }
        PhotosCommand::Place { album, command } => {
            place(command, album.as_deref(), &session, &mut replica, options).await
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

async fn sync_files(
    album: Option<&str>,
    session: &Session,
    replica: &mut Replica<'_>,
    options: &Options,
) -> Result<(Option<i64>, bool)> {
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
    Ok((album.map(|_| albums[0].id), incomplete))
}

async fn file(
    command: FileCommand,
    album: Option<&str>,
    session: &Session,
    replica: &mut Replica<'_>,
    options: &Options,
) -> Result<()> {
    let (album_id, mut incomplete) = sync_files(album, session, replica, options).await?;
    let placed = match &command {
        FileCommand::List { query, .. } if query.place.is_some() || query.country.is_some() => {
            let index = places::open(options.offline).await?;
            let located = located(replica, album_id, |_, _| {})?;
            Some(places::matching(&index, query, &located)?)
        }
        _ => None,
    };
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
        FileCommand::List { query, list } => replica.files(album_id, None, None, |rows| {
            let files = rows.filter_map(|row| {
                let entry = match row {
                    Ok(entry) => entry,
                    Err(error) => return Some(Err(error.into())),
                };
                let listed = entry.file.and_then(|file| {
                    if !matches(&query, &file)
                        || placed.as_ref().is_some_and(|ids| !ids.contains(&file.id))
                    {
                        return Ok(None);
                    }
                    let key = SortKey {
                        created_at_micros: file.created_at_micros,
                        size: file.size,
                    };
                    FileView::new(file, &entry.album_ids).map(|view| Some((key, view)))
                });
                match listed {
                    Ok(listed) => listed.map(Ok),
                    Err(error) => {
                        eprintln!("file {}: {error:#}", entry.id);
                        incomplete = true;
                        None
                    }
                }
            });
            let Some(sort) = query.sort else {
                return output::files(
                    files.map(|row| row.map(|(_, view)| view)),
                    &list,
                    options.json,
                );
            };
            let mut files = files.collect::<Result<Vec<_>>>()?;
            files.sort_by(|(a, _), (b, _)| compare(sort, query.reverse, a, b));
            output::files(
                files.into_iter().map(|(_, view)| Ok(view)),
                &list,
                options.json,
            )
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

async fn place(
    command: PlaceCommand,
    album: Option<&str>,
    session: &Session,
    replica: &mut Replica<'_>,
    options: &Options,
) -> Result<()> {
    let (album_id, mut incomplete) = sync_files(album, session, replica, options).await?;
    let PlaceCommand::List { countries, list } = command;
    let index = places::open(options.offline).await?;
    let located = located(replica, album_id, |id, error| {
        eprintln!("file {id}: {error:#}");
        incomplete = true;
    })?;
    let coordinates = located
        .into_iter()
        .map(|(_, coordinate)| coordinate)
        .collect::<Vec<_>>();
    places::list(&index, &coordinates, countries, &list, options.json)?;
    ensure!(!incomplete, "place results are incomplete");
    Ok(())
}

fn located(
    replica: &Replica<'_>,
    album_id: Option<i64>,
    mut failed: impl FnMut(i64, anyhow::Error),
) -> Result<Vec<(i64, Coordinate)>> {
    replica.files(album_id, None, None, |rows| {
        let mut located = Vec::new();
        for row in rows {
            let entry = row?;
            match entry.file {
                Ok(file) => located
                    .extend(places::coordinate(&file).map(|coordinate| (file.id, coordinate))),
                Err(error) => failed(entry.id, error),
            }
        }
        Ok(located)
    })
}

struct SortKey {
    created_at_micros: i64,
    size: Option<u64>,
}

fn matches(query: &FileQuery, file: &File) -> bool {
    (query.types.is_empty() || query.types.iter().any(|&kind| file_kind(kind) == file.kind))
        && query
            .since
            .is_none_or(|since| file.created_at_micros >= since)
        && query
            .before
            .is_none_or(|before| file.created_at_micros < before)
        && (!query.no_location || file.location.is_none())
        && query
            .min_size
            .is_none_or(|min| file.size.is_some_and(|size| size >= min))
        && query
            .max_size
            .is_none_or(|max| file.size.is_some_and(|size| size <= max))
        && query
            .search
            .as_deref()
            .is_none_or(|text| contains_words(file, text))
}

fn file_kind(kind: FileType) -> Kind {
    match kind {
        FileType::Image => Kind::Image,
        FileType::Video => Kind::Video,
        FileType::LivePhoto => Kind::LivePhoto,
    }
}

fn contains_words(file: &File, text: &str) -> bool {
    let name = file.name.to_lowercase();
    let caption = file.caption.as_deref().unwrap_or_default().to_lowercase();
    text.to_lowercase()
        .split_whitespace()
        .all(|word| name.contains(word) || caption.contains(word))
}

fn compare(sort: FileSort, reverse: bool, a: &SortKey, b: &SortKey) -> Ordering {
    let newest_or_largest_first = match sort {
        FileSort::Created => b.created_at_micros.cmp(&a.created_at_micros),
        FileSort::Size => b.size.cmp(&a.size),
    };
    if reverse {
        newest_or_largest_first.reverse()
    } else {
        newest_or_largest_first
    }
}
