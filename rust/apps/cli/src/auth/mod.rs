mod code;
mod output;
pub mod replica;

use std::{fs, path::PathBuf};

use anyhow::{Context, Result, bail};
use ente_auth::backup;
use serde_json::json;
use zeroize::Zeroizing;

use crate::{
    api,
    args::{App, AuthCommand, AuthExportArgs, Options},
    db, home, password,
};
use output::Destination;

pub async fn run(command: AuthCommand, selected: Option<&str>, options: &Options) -> Result<()> {
    match command {
        AuthCommand::Api(args) => api::run(App::Auth, args, selected, options).await,
        AuthCommand::Code { command } => code::run(command, selected, options).await,
        AuthCommand::Export(args) => export(args, selected, options).await,
        AuthCommand::Decrypt { input, output } => {
            let destination = Destination::file(output.unwrap_or_else(|| PathBuf::from("-")));
            destination.prepare()?;
            let encrypted =
                fs::read(&input).with_context(|| format!("cannot read {}", input.display()))?;
            let password = password::read("Export password", false, options)?;
            let plaintext = backup::decrypt(&encrypted, &password)
                .with_context(|| format!("cannot decrypt {}", input.display()))?;
            if let Some(path) = destination.publish(&plaintext)? {
                crate::output::action(
                    options.json,
                    &json!({"output": path.to_string_lossy()}),
                    &format!("Decrypted to {}.", path.display()),
                )?;
            }
            Ok(())
        }
    }
}

async fn export(args: AuthExportArgs, selected: Option<&str>, options: &Options) -> Result<()> {
    let destination = if let Some(path) = args.directory {
        Destination::Directory {
            path,
            extension: if args.plaintext { "txt" } else { "json" },
        }
    } else {
        Destination::file(
            args.output
                .context("export requires DIR or --output PATH|-")?,
        )
    };
    destination.prepare()?;
    let password = if args.plaintext {
        None
    } else {
        Some(password::read("Export password", true, options)?)
    };
    let payload = {
        let (account, home) = home::open_account(selected, !options.offline)?;
        let session = api::session(&account, App::Auth)?;
        let mut db = db::open(&home.path, &account.db_key, !options.offline)?;
        if !options.offline {
            replica::refresh(&mut db, &session).await?;
        }
        replica::read_payload(&db, &session)?
    };
    if payload.failed > 0 {
        let plural = if payload.failed == 1 { "" } else { "s" };
        if !matches!(destination, Destination::Stdout) {
            crate::output::action(
                options.json,
                &json!({"output": null, "codes": 0, "failures": {"total": payload.failed}}),
                &format!(
                    "{} unreadable Auth code{plural}; no new backup was written.",
                    payload.failed
                ),
            )?;
        }
        bail!(
            "{} unreadable Auth code{plural}; no new backup was written (code ID{plural}: {})",
            payload.failed,
            payload.failed_ids.join(", ")
        );
    }
    let artifact = match password {
        Some(password) => Zeroizing::new(backup::encrypt(&payload.bytes, &password)?),
        None => payload.bytes,
    };
    if let Some(path) = destination.publish(&artifact)? {
        crate::output::action(
            options.json,
            &json!({"output": path.to_string_lossy(), "codes": payload.records, "failures": {"total": 0}}),
            &format!(
                "Exported {} code{} to {}.",
                payload.records,
                if payload.records == 1 { "" } else { "s" },
                path.display(),
            ),
        )?;
    }
    Ok(())
}
