mod source;

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, ensure};
use ente_core::crypto::hash;
use ente_photos_export::{AdoptionRequired, Export, Report};
use tokio::sync::watch;

use crate::{
    api,
    args::{App, Options, PhotosExportArgs},
    db, home, output,
    vault::State,
};

pub async fn run(args: PhotosExportArgs, selected: Option<&str>, options: &Options) -> Result<()> {
    ensure!(
        !options.offline,
        "export requires network access; remove --offline"
    );
    let selected = selected.map(str::to_owned);
    let as_json = options.json;
    let runtime = tokio::runtime::Handle::current();
    tokio::task::spawn_blocking(move || {
        runtime.block_on(run_locked(args, selected.as_deref(), as_json))
    })
    .await?
}

fn adoption(error: anyhow::Error) -> anyhow::Error {
    match error.downcast_ref::<AdoptionRequired>() {
        Some(AdoptionRequired::Foreign) => anyhow!(
            "This folder contains an export from the old CLI or Ente Desktop. Use --adopt if you want to take it over."
        ),
        Some(reason) => anyhow!("{reason}; use --adopt"),
        None => error,
    }
}

fn report(report: Report) {
    let line = match report {
        Report::RefreshingCatalog => "Refreshing album metadata.".into(),
        Report::RefreshingAlbums => "Refreshing selected albums and Favorites.".into(),
        Report::CheckingExistingFiles => {
            "Checking the existing files before taking over this export.".into()
        }
        Report::Maintaining { expected } => format!("Maintaining {expected} selected copies."),
        Report::Completed {
            completed,
            expected,
        } => {
            format!("Completed {completed}/{expected} selected copies.")
        }
        Report::Failure { unit, error } => format!("{unit}: {error:#}"),
        Report::UnknownAlbum {
            id,
            shared_unknown,
            hidden_unknown,
        } => {
            let flags = match (shared_unknown, hidden_unknown) {
                (true, true) => "--exclude-shared and --exclude-hidden",
                (true, false) => "--exclude-shared",
                _ => "--exclude-hidden",
            };
            format!(
                "album:{id}: cannot determine whether this album is excluded by {flags}; use --exclude-album {id} or remove {flags}"
            )
        }
    };
    eprintln!("{line}");
}

async fn run_locked(args: PhotosExportArgs, selected: Option<&str>, as_json: bool) -> Result<()> {
    let mut state = State::load()?;
    let index = state.resolve(selected)?;
    let account = state.accounts.swap_remove(index);
    let session = api::session(&account, App::Photos)?;
    // Declare first so export's stores drop before this lock.
    let _storage_use;
    let mut export = Export::open(
        &args.destination,
        &session,
        ente_photos_export::Options {
            albums: args.album,
            exclude_albums: args.exclude_album,
            exclude_shared: args.exclude_shared,
            exclude_hidden: args.exclude_hidden,
            adopt: args.adopt,
            hardlinks: args.hardlinks,
            jobs: args.jobs,
        },
    )
    .map_err(adoption)
    .with_context(|| format!("cannot open Photos export {}", args.destination.display()))?;
    let account_home = home::lock_account(account.storage_id, true)?;
    let account = State::load()?
        .accounts
        .into_iter()
        .find(|a| a.storage_id == account.storage_id)
        .context("account was removed while waiting for access")?;
    let session = api::session(&account, App::Photos)?;
    export.verify_source(&session)?;
    _storage_use = account_home.storage_use()?;
    home::create(&account_home.path)?;
    let db_path = store_path(&account_home.path, export.destination())?;
    ensure!(
        !export.exists() || db_path.try_exists()? || args.adopt,
        "this export is not associated with this CLI home; use --adopt"
    );
    let db_dir = db_path.parent().context("export DB has no parent")?;
    home::create(db_dir)?;
    if let Err(error) = std::fs::remove_dir_all(db_dir.join("adoption"))
        && error.kind() != std::io::ErrorKind::NotFound
    {
        return Err(error.into());
    }
    let connection = db::connect(&db_path, &account.db_key, true)?;
    let (cancel_send, mut cancel) = watch::channel(false);
    let signal_send = cancel_send.clone();
    let signal = tokio::spawn(async move {
        if tokio::signal::ctrl_c().await.is_ok() {
            signal_send.send_replace(true);
        }
    });
    let result = async {
        let mut source_db = db::open(&account_home.path, &account.db_key, true)?;
        let mut source = source::ReplicaSource::new(&mut source_db, session.user_id);
        export
            .prepare(
                connection,
                || {
                    let directory = tempfile::Builder::new()
                        .prefix("adoption")
                        .rand_bytes(0)
                        .tempdir_in(db_dir)?;
                    let connection = db::scratch(&directory.path().join("index.db"))?;
                    Ok((directory, connection))
                },
                &mut source,
                &session,
                &mut cancel,
                &report,
            )
            .await?;
        drop(source);
        drop(source_db);
        drop(account_home);
        export.execute(&session, &cancel_send, &cancel, &report)
    }
    .await;
    signal.abort();
    let summary = result.map_err(adoption)?;
    let progress = if summary.json["copies"].is_null() {
        "could not determine the full export size".to_owned()
    } else {
        format!(
            "{}/{} album copies complete",
            summary.completed, summary.expected
        )
    };
    let changes = &summary.json["changes"];
    output::action(
        as_json,
        &summary.json,
        &format!(
            "{}: {progress}, {} exported, {} moved to Trash, {} failures ({} conflicts).",
            export.destination().display(),
            changes["exported"],
            changes["movedToTrash"],
            summary.json["failures"]["total"],
            summary.json["failures"]["conflicts"],
        ),
    )?;
    ensure!(summary.complete, "export is incomplete");
    Ok(())
}

fn store_path(account_home: &Path, destination: &Path) -> Result<PathBuf> {
    let bytes = destination.as_os_str().as_encoded_bytes();
    let name: String = hash::hash(bytes, Some(32), None)?
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    Ok(account_home.join("exports").join(format!("{name}.db")))
}
