use std::{io::IsTerminal, path::Path};

use anyhow::{Context, Result, ensure};
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::{
    api,
    args::{FeedbackArgs, Options},
    output, read_input,
};

const MAX_MESSAGE_CHARS: usize = 2_000;

#[derive(Deserialize, Serialize)]
struct Receipt {
    id: Uuid,
}

pub async fn run(args: FeedbackArgs, options: &Options) -> Result<()> {
    ensure!(!options.offline, "this command requires network access");
    let message = match args.message {
        Some(message) => message,
        None => {
            ensure!(
                args.input.is_some() || !std::io::stdin().is_terminal(),
                "provide MESSAGE, --input PATH|-, or piped stdin"
            );
            let bytes = read_input(
                args.input.as_deref().unwrap_or(Path::new("-")),
                (MAX_MESSAGE_CHARS * 4 + 1) as u64,
            )?;
            ensure!(
                bytes.len() <= MAX_MESSAGE_CHARS * 4,
                "feedback cannot exceed 2,000 characters"
            );
            String::from_utf8(bytes.to_vec()).context("feedback input must be UTF-8")?
        }
    };
    ensure!(!message.trim().is_empty(), "feedback cannot be blank");
    ensure!(
        message.chars().count() <= MAX_MESSAGE_CHARS,
        "feedback cannot exceed 2,000 characters"
    );
    ensure!(
        !message
            .chars()
            .any(|c| c.is_control() && !matches!(c, '\r' | '\n' | '\t')),
        "feedback cannot contain control characters other than line endings and tabs"
    );
    let body = json!({
        "message": message,
        "version": env!("CARGO_PKG_VERSION"),
        "os": std::env::consts::OS,
    });
    let response = api::http()?
        .post(api::normalize_host(&args.host)?)
        .json(&body)
        .send()
        .await
        .context("could not confirm feedback submission")?;
    ensure!(
        response.status() != StatusCode::TOO_MANY_REQUESTS,
        "too many feedback submissions; wait a minute before trying again"
    );
    ensure!(
        response.status() == StatusCode::CREATED,
        "could not confirm feedback submission (HTTP {})",
        response.status()
    );
    let receipt: Receipt = response.json().await.context(
        "feedback server returned an invalid receipt; submission may have been received",
    )?;
    output::action(
        options.json,
        &receipt,
        &format!("Feedback submitted. Receipt: {}", receipt.id),
    )
}
