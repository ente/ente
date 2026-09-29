mod source;

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use ente_core::crypto::hash;
use ente_photos_export::{AdoptionRequired, Export};
use tokio::sync::watch;

use crate::{
    api,
    args::{ExportArgs, Options, Product},
    db, home, output,
    vault::State,
};

pub async fn run(args: ExportArgs, selected: Option<&str>, options: &Options) -> Result<()> {
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
    .map_err(|error| {
        if error.is::<AdoptionRequired>() {
            error.context("this export requires --adopt")
        } else {
            error
        }
    })
}

async fn run_locked(args: ExportArgs, selected: Option<&str>, as_json: bool) -> Result<()> {
    let mut state = State::load()?;
    let index = state.resolve(selected)?;
    let account = state.accounts.swap_remove(index);
    let session = api::session(&account, Product::Photos)?;
    let mut export = Export::open(
        &args.destination,
        &session.master_key,
        ente_photos_export::Options {
            albums: args.album,
            exclude_albums: args.exclude_album,
            adopt: args.adopt,
            jobs: args.jobs,
        },
    )?;
    let account_home = home::lock_account(account.storage_id, true)?;
    let account = State::load()?
        .accounts
        .into_iter()
        .find(|a| a.storage_id == account.storage_id)
        .context("account was removed while waiting for access")?;
    let session = api::session(&account, Product::Photos)?;
    export.verify_source(&session.master_key)?;
    home::create(&account_home.path)?;
    let db_path = store_path(&account_home.path, export.destination())?;
    ensure!(
        !export.exists() || db_path.try_exists()? || args.adopt,
        "this export is not associated with this CLI home; use --adopt"
    );
    home::create(db_path.parent().context("export DB has no parent")?)?;
    let connection = db::connect(&db_path, &account.db_key, true)?;
    let (cancel_send, mut cancel) = watch::channel(false);
    let signal_send = cancel_send.clone();
    let signal = tokio::spawn(async move {
        if tokio::signal::ctrl_c().await.is_ok() {
            signal_send.send_replace(true);
        }
    });
    let report = |line: &str| eprintln!("{line}");
    let result = async {
        let mut source_db = db::open(&account_home.path, &account.db_key, true)?;
        let mut source = source::ReplicaSource::new(&mut source_db, session.user_id);
        export
            .prepare(connection, &mut source, &session, &mut cancel, &report)
            .await?;
        drop(source);
        drop(source_db);
        drop(account_home);
        export.execute(&session, &cancel_send, &cancel, &report)
    }
    .await;
    signal.abort();
    let summary = result?;
    let progress = if summary.json["copies"].is_null() {
        "inventory incomplete".to_owned()
    } else {
        format!("{}/{} copies complete", summary.completed, summary.expected)
    };
    let changes = &summary.json["changes"];
    output::action(
        as_json,
        &summary.json,
        &format!(
            "{}: {progress}, {} exported, {} retained, {} failures, {} conflicts.",
            export.destination().display(),
            changes["exported"],
            changes["retained"],
            summary.json["failures"],
            summary.json["conflicts"],
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
