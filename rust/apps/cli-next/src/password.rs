use std::env;

use anyhow::{Result, bail, ensure};
use dialoguer::{Password, console::Term};
use zeroize::Zeroizing;

use crate::args::Options;

pub fn read(label: &str, confirm: bool, options: &Options) -> Result<Zeroizing<String>> {
    match supplied(label, options)? {
        Some(password) => Ok(password),
        None => prompt(label, confirm),
    }
}

pub fn supplied(label: &str, options: &Options) -> Result<Option<Zeroizing<String>>> {
    match env::var("ENTE_CLI_PASSWORD") {
        Ok(password) => {
            ensure!(!password.is_empty(), "ENTE_CLI_PASSWORD must be nonempty");
            Ok(Some(Zeroizing::new(password)))
        }
        Err(env::VarError::NotUnicode(_)) => bail!("ENTE_CLI_PASSWORD must be UTF-8"),
        Err(env::VarError::NotPresent) => {
            ensure!(
                options.can_prompt(),
                "set ENTE_CLI_PASSWORD to the {} when running without interactive prompts",
                label.to_lowercase()
            );
            Ok(None)
        }
    }
}

pub fn prompt(label: &str, confirm: bool) -> Result<Zeroizing<String>> {
    let mut prompt = Password::new().with_prompt(label);
    if confirm {
        prompt = prompt.with_confirmation(
            format!("Confirm {}", label.to_lowercase()),
            "Passwords do not match",
        );
    }
    Ok(Zeroizing::new(prompt.interact_on(&Term::stderr())?))
}
