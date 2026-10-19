use std::{
    io::{IsTerminal, Write},
    path::Path,
};

use anyhow::{Context, Result, ensure};
use ente_accounts::DEFAULT_API_ORIGIN;
use ente_paste::{Client, OpenPaste, PasteLink, PasteSession};
use serde_json::json;
use zeroize::Zeroizing;

use crate::{
    api,
    args::{Options, PasteCommand},
    output, password, read_input,
};

pub async fn run(command: PasteCommand, options: &Options) -> Result<()> {
    ensure!(!options.offline, "this command requires network access");
    match command {
        PasteCommand::Create {
            text,
            input,
            password: protected,
            host,
            paste_origin,
        } => {
            let text = Zeroizing::new(match text {
                Some(text) => text,
                None => {
                    ensure!(
                        input.is_some() || !std::io::stdin().is_terminal(),
                        "provide TEXT, --input PATH|-, or piped stdin"
                    );
                    let max_bytes = ente_paste::MAX_PASTE_CHARS * 4;
                    let bytes = read_input(
                        input.as_deref().unwrap_or(Path::new("-")),
                        (max_bytes + 1) as u64,
                    )?;
                    ensure!(bytes.len() <= max_bytes, ente_paste::Error::TextTooLong);
                    String::from_utf8(bytes.to_vec()).context("paste input must be UTF-8")?
                }
            });
            ente_paste::validate_text(&text)?;
            let paste_origin = api::normalize_host(paste_origin.as_str())?;
            let password = protected
                .then(|| password::read("Paste password", true, options))
                .transpose()?;
            let link = client(host)?
                .create(&text, password.as_deref().map(String::as_str))
                .await?;
            let url = link.url(&paste_origin);
            output::action(options.json, &json!({ "url": url }), &url)
        }
        PasteCommand::Consume {
            link_or_token,
            key,
            raw,
            host,
        } => {
            let link = PasteLink::parse(&link_or_token, key.as_deref())?;
            let password = if link.password_required() {
                password::supplied("Paste password", options)?
            } else {
                None
            };
            let text = Zeroizing::new(
                consume(&client(host)?, link, password, || {
                    password::prompt("Paste password", false)
                })
                .await?,
            );
            if options.json {
                output::json(&json!({ "text": text.as_str() }))
            } else {
                let text = display_text(&text, raw, std::io::stdout().is_terminal());
                let mut stdout = std::io::stdout().lock();
                stdout.write_all(text.as_bytes())?;
                stdout.flush().map_err(Into::into)
            }
        }
    }
}

fn client(host: Option<String>) -> Result<Client> {
    Ok(Client::new(
        api::normalize_host(host.as_deref().unwrap_or(DEFAULT_API_ORIGIN))?,
        Some(api::USER_AGENT.into()),
    )?)
}

async fn consume(
    client: &Client,
    link: PasteLink,
    mut password: Option<Zeroizing<String>>,
    mut prompt: impl FnMut() -> Result<Zeroizing<String>>,
) -> Result<String> {
    let mut session = PasteSession::new(link);
    let result: Result<String> = async {
        if let OpenPaste::Text(text) = session.open(client).await? {
            return Ok(text);
        }
        let retry = password.is_none();
        if retry {
            password = Some(prompt()?);
        }
        loop {
            match session
                .consume(client, password.as_deref().map(String::as_str))
                .await
            {
                Err(error @ ente_paste::Error::IncorrectPassword) if retry => {
                    eprintln!(
                        "{error}. Paste already consumed; exiting will prevent further retries."
                    );
                    password = Some(prompt()?);
                }
                result => return result.map_err(Into::into),
            }
        }
    }
    .await;
    if session.has_payload() {
        result.context("paste has been consumed and cannot be read again")
    } else {
        result
    }
}

fn display_text(text: &str, raw: bool, terminal: bool) -> std::borrow::Cow<'_, str> {
    if raw || !terminal {
        return text.into();
    }
    let mut output = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '\n' | '\t' => output.push(ch),
            '\r' if chars.peek() == Some(&'\n') => {
                chars.next();
                output.push_str("\r\n");
            }
            _ if ch.is_control() => output.extend(ch.escape_default()),
            _ => output.push(ch),
        }
    }
    output.into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::Server;

    #[test]
    fn output_preserves_text_and_escapes_terminal_controls() {
        let text = "français 🔐\r\n\t\x1b]52;c;AAAA\x07\rhidden\u{85}";
        assert_eq!(display_text(text, false, false), text);
        assert_eq!(display_text(text, true, true), text);
        assert_eq!(
            display_text(text, false, true),
            "français 🔐\r\n\t\\u{1b}]52;c;AAAA\\u{7}\\rhidden\\u{85}"
        );
    }

    #[tokio::test]
    async fn password_retry_and_prompt_failure_never_consume_twice() {
        let (key, payload) = ente_paste::encrypt("protected text", Some("correct")).unwrap();
        let fragment = key.link_fragment();
        let mut server = Server::new_async().await;
        let client = Client::new(server.url(), None).unwrap();
        for cancel_at in [None, Some(1), Some(2)] {
            let guard = server
                .mock("POST", "/paste/guard")
                .with_header("set-cookie", "paste_guard=fixture")
                .expect(if cancel_at == Some(1) { 1 } else { 2 })
                .create_async()
                .await;
            let request = server
                .mock("POST", "/paste/consume")
                .with_body(serde_json::to_string(&payload).unwrap())
                .expect(if cancel_at == Some(1) { 0 } else { 1 })
                .create_async()
                .await;
            let mut prompts = 0;
            let link = PasteLink::parse("ABC123", Some(&fragment)).unwrap();
            let result = consume(&client, link, None, || {
                prompts += 1;
                if cancel_at == Some(prompts) {
                    anyhow::bail!("prompt cancelled");
                }
                match prompts {
                    1 => Ok(Zeroizing::new("wrong".into())),
                    2 => Ok(Zeroizing::new("correct".into())),
                    _ => panic!("unexpected prompt"),
                }
            })
            .await;
            if cancel_at.is_some() {
                let error = format!("{:#}", result.unwrap_err());
                assert!(error.contains("prompt cancelled"));
                assert_eq!(
                    error.contains("paste has been consumed"),
                    cancel_at == Some(2)
                );
            } else {
                assert_eq!(result.unwrap(), "protected text");
            }
            assert_eq!(prompts, cancel_at.unwrap_or(2));
            guard.assert_async().await;
            request.assert_async().await;
            guard.remove_async().await;
            request.remove_async().await;
        }
    }
}
