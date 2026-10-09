mod output;
pub mod replica;

use std::{env, fs, path::PathBuf};

use anyhow::{Context, Result, bail, ensure};
use dialoguer::{Password, console::Term};
use ente_auth::backup;
use serde_json::json;
use zeroize::Zeroizing;

use crate::{
    api,
    args::{AuthCommand, AuthExportArgs, Options, Product},
    db, home,
};
use output::Destination;

pub async fn run(command: AuthCommand, selected: Option<&str>, options: &Options) -> Result<()> {
    match command {
        AuthCommand::Session(command) => {
            crate::session(Product::Auth, command, selected, options).await
        }
        AuthCommand::Export(args) => export(args, selected, options).await,
        AuthCommand::Decrypt { input, output } => {
            let destination = Destination::file(output.unwrap_or_else(|| PathBuf::from("-")));
            destination.prepare()?;
            let encrypted =
                fs::read(&input).with_context(|| format!("cannot read {}", input.display()))?;
            let password = export_password(false, options)?;
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
        Some(export_password(true, options)?)
    };
    let payload = {
        let (account, home) = home::open_account(selected, !options.offline)?;
        let session = api::session(&account, Product::Auth)?;
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
                &json!({"output": null, "records": 0, "failed": payload.failed}),
                &format!(
                    "{} unreadable Auth record{plural}; no new backup was written.",
                    payload.failed
                ),
            )?;
        }
        bail!(
            "{} unreadable Auth record{plural}; no new backup was written (record ID{plural}: {})",
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
            &json!({"output": path.to_string_lossy(), "records": payload.records, "failed": 0}),
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

fn export_password(confirm: bool, options: &Options) -> Result<Zeroizing<String>> {
    let password = match env::var("ENTE_CLI_EXPORT_PASSWORD") {
        Ok(password) => Zeroizing::new(password),
        Err(env::VarError::NotUnicode(_)) => bail!("ENTE_CLI_EXPORT_PASSWORD must be UTF-8"),
        Err(env::VarError::NotPresent) => {
            ensure!(
                options.can_prompt(),
                "set ENTE_CLI_EXPORT_PASSWORD for noninteractive encrypted export or decryption"
            );
            let mut prompt = Password::new().with_prompt("Export password");
            if confirm {
                prompt =
                    prompt.with_confirmation("Confirm export password", "Passwords do not match");
            }
            Zeroizing::new(prompt.interact_on(&Term::stderr())?)
        }
    };
    ensure!(
        !password.is_empty(),
        "export password cannot be empty; set ENTE_CLI_EXPORT_PASSWORD to a nonempty value"
    );
    Ok(password)
}
