use crate::{
    api::client::USER_AGENT,
    cli::paste::{PasteCommand, PasteSubcommands},
    models::error::{Error, Result},
};
use dialoguer::Password;
use ente_paste::{PasteKey, PasteLink, PastePayload};
use std::ffi::OsStr;
use std::io::{self, IsTerminal, Read};
use std::path::PathBuf;

const PASTE_PASSWORD_ENV: &str = "ENTE_PASTE_PASSWORD";

pub async fn handle_paste_command(cmd: PasteCommand) -> Result<()> {
    match cmd.command {
        PasteSubcommands::Create {
            text,
            file,
            endpoint,
            paste_origin,
            password,
        } => {
            let text = read_paste_text(text, file)?;
            let password = if password {
                Some(resolve_new_paste_password()?)
            } else {
                None
            };
            let client = paste_client(endpoint)?;
            let link = client.create(&text, password.as_deref()).await?;
            println!("{}", link.url(&paste_origin));
            Ok(())
        }
        PasteSubcommands::Consume {
            link_or_token,
            raw,
            key,
            endpoint,
        } => {
            let link = PasteLink::parse(&link_or_token, key.as_deref())?;
            let text = consume_paste(endpoint, &link.access_token, &link.key).await?;
            print_consumed_paste(&text, raw);
            Ok(())
        }
    }
}

fn paste_client(endpoint: String) -> Result<ente_paste::Client> {
    Ok(ente_paste::Client::new(
        endpoint,
        Some(USER_AGENT.to_string()),
    )?)
}

async fn consume_paste(
    endpoint: String,
    access_token: &str,
    paste_key: &PasteKey,
) -> Result<String> {
    consume_paste_with_password_resolver(
        endpoint,
        access_token,
        paste_key,
        resolve_paste_password_attempt,
    )
    .await
}

async fn consume_paste_with_password_resolver<F>(
    endpoint: String,
    access_token: &str,
    paste_key: &PasteKey,
    resolve_password: F,
) -> Result<String>
where
    F: FnOnce() -> Result<PastePasswordAttempt>,
{
    let client = paste_client(endpoint)?;
    let password = if paste_key.password_required {
        client.check(access_token).await?;
        Some(resolve_password()?)
    } else {
        None
    };
    let payload = client.consume(access_token).await?;

    match password {
        Some(password) => decrypt_password_protected_paste_with_prompt(
            paste_key,
            &payload,
            password,
            prompt_raw_paste_password,
        ),
        None => Ok(ente_paste::decrypt(&payload, paste_key, None)?),
    }
}

fn decrypt_password_protected_paste_with_prompt<F>(
    paste_key: &PasteKey,
    payload: &PastePayload,
    password: PastePasswordAttempt,
    prompt_password: F,
) -> Result<String>
where
    F: FnMut() -> Result<String>,
{
    decrypt_password_protected_paste_with(password, prompt_password, |password| {
        ente_paste::decrypt(payload, paste_key, Some(password))
    })
}

fn decrypt_password_protected_paste_with<F, D>(
    mut password: PastePasswordAttempt,
    mut prompt_password: F,
    mut decrypt: D,
) -> Result<String>
where
    F: FnMut() -> Result<String>,
    D: FnMut(&str) -> ente_paste::Result<String>,
{
    loop {
        match decrypt(password.value()) {
            Err(ente_paste::Error::IncorrectPassword) if password.can_retry() => {
                eprintln!("Incorrect paste password. Try again.");
                password = PastePasswordAttempt::Prompted(prompt_valid_paste_password(
                    &mut prompt_password,
                )?);
            }
            Err(ente_paste::Error::IncorrectPassword) => {
                return Err(Error::AuthenticationFailed(
                    "Incorrect paste password".to_string(),
                ));
            }
            result => return Ok(result?),
        }
    }
}

fn print_consumed_paste(text: &str, raw: bool) {
    if !raw && io::stdout().is_terminal() {
        print!("{}", terminal_safe_paste_text(text));
    } else {
        print!("{text}");
    }
}

fn terminal_safe_paste_text(text: &str) -> String {
    let mut output = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '\n' | '\t' => output.push(ch),
            '\r' if chars.peek() == Some(&'\n') => {
                chars.next();
                output.push('\r');
                output.push('\n');
            }
            _ if ch.is_control() => output.extend(ch.escape_default()),
            _ => output.push(ch),
        }
    }
    output
}

fn read_paste_text(text: Option<String>, file: Option<PathBuf>) -> Result<String> {
    let text = match (text, file) {
        (Some(text), None) => text,
        (None, Some(path)) if path.as_os_str() == OsStr::new("-") => read_stdin()?,
        (None, Some(path)) => std::fs::read_to_string(path)?,
        (None, None) if !io::stdin().is_terminal() => read_stdin()?,
        (None, None) => {
            return Err(Error::InvalidInput(
                "Provide text, --file, or pipe text on stdin".to_string(),
            ));
        }
        (Some(_), Some(_)) => unreachable!("clap prevents text and --file together"),
    };

    if text.trim().is_empty() {
        return Err(Error::InvalidInput(
            "Paste text cannot be empty".to_string(),
        ));
    }
    if text.chars().count() > ente_paste::MAX_PASTE_CHARS {
        return Err(Error::InvalidInput(format!(
            "Paste is limited to {} characters",
            ente_paste::MAX_PASTE_CHARS
        )));
    }
    Ok(text)
}

fn read_stdin() -> Result<String> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    Ok(input)
}

fn resolve_new_paste_password() -> Result<String> {
    match paste_password_from_env()? {
        Some(password) => Ok(password),
        None => prompt_new_paste_password(),
    }
}

fn resolve_paste_password_attempt() -> Result<PastePasswordAttempt> {
    match paste_password_from_env()? {
        Some(password) => Ok(PastePasswordAttempt::Env(password)),
        None => Ok(PastePasswordAttempt::Prompted(prompt_paste_password()?)),
    }
}

fn paste_password_from_env() -> Result<Option<String>> {
    match std::env::var(PASTE_PASSWORD_ENV) {
        Ok(password) => {
            validate_password(&password)?;
            Ok(Some(password))
        }
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(error) => Err(Error::InvalidInput(format!(
            "{PASTE_PASSWORD_ENV} is not valid Unicode: {error}"
        ))),
    }
}

fn prompt_new_paste_password() -> Result<String> {
    let password = Password::new()
        .with_prompt("Paste password")
        .with_confirmation("Confirm paste password", "Passwords do not match")
        .interact()
        .map_err(dialoguer_error)?;
    validate_password(&password)?;
    Ok(password)
}

fn prompt_paste_password() -> Result<String> {
    prompt_valid_paste_password(prompt_raw_paste_password)
}

fn prompt_raw_paste_password() -> Result<String> {
    Password::new()
        .with_prompt("Paste password")
        .interact()
        .map_err(dialoguer_error)
}

fn prompt_valid_paste_password<F>(mut prompt_password: F) -> Result<String>
where
    F: FnMut() -> Result<String>,
{
    loop {
        let password = prompt_password()?;
        match validate_password(&password) {
            Ok(()) => return Ok(password),
            Err(error) => eprintln!("{error}"),
        }
    }
}

fn dialoguer_error(error: dialoguer::Error) -> Error {
    match error {
        dialoguer::Error::IO(source) => Error::Io(source),
    }
}

fn validate_password(password: &str) -> Result<()> {
    if password.is_empty() {
        Err(Error::InvalidInput(
            "Paste password cannot be empty".to_string(),
        ))
    } else {
        Ok(())
    }
}

enum PastePasswordAttempt {
    Env(String),
    Prompted(String),
}

impl PastePasswordAttempt {
    fn value(&self) -> &str {
        match self {
            Self::Env(password) | Self::Prompted(password) => password,
        }
    }

    fn can_retry(&self) -> bool {
        matches!(self, Self::Prompted(_))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_decrypt_password_protected_paste(password: &str) -> ente_paste::Result<String> {
        match password {
            "correct horse" => Ok("protected paste".to_string()),
            _ => Err(ente_paste::Error::IncorrectPassword),
        }
    }

    #[test]
    fn default_tty_output_escapes_controls() {
        let text = "ok\n\x1b]52;c;AAAA\x07\rhidden\tend\u{85}";

        assert_eq!(
            terminal_safe_paste_text(text),
            "ok\n\\u{1b}]52;c;AAAA\\u{7}\\rhidden\tend\\u{85}",
        );
    }

    #[test]
    fn terminal_safe_paste_text_preserves_crlf() {
        assert_eq!(terminal_safe_paste_text("one\r\ntwo\r\n"), "one\r\ntwo\r\n");
    }

    #[test]
    fn terminal_safe_paste_text_preserves_printable_unicode() {
        let text = "api key: fran\u{e7}ais \u{1f510}";

        assert_eq!(terminal_safe_paste_text(text), text);
    }

    #[test]
    fn prompted_password_retry_can_recover() {
        let (paste_key, payload) =
            ente_paste::encrypt("protected paste", Some("correct horse")).unwrap();
        let mut retry_passwords = ["correct horse"].into_iter();
        let text = decrypt_password_protected_paste_with_prompt(
            &paste_key,
            &payload,
            PastePasswordAttempt::Prompted("wrong horse".to_string()),
            || Ok::<_, Error>(retry_passwords.next().expect("retry password").to_string()),
        )
        .unwrap();

        assert_eq!(text, "protected paste");
        assert_eq!(retry_passwords.next(), None);
    }

    #[test]
    fn prompted_password_retry_ignores_empty_password() {
        let mut retry_passwords = ["", "correct horse"].into_iter();
        let text = decrypt_password_protected_paste_with(
            PastePasswordAttempt::Prompted("wrong horse".to_string()),
            || Ok::<_, Error>(retry_passwords.next().expect("retry password").to_string()),
            test_decrypt_password_protected_paste,
        )
        .unwrap();

        assert_eq!(text, "protected paste");
        assert_eq!(retry_passwords.next(), None);
    }

    #[test]
    fn wrong_env_password_fails_without_retry() {
        let error = decrypt_password_protected_paste_with(
            PastePasswordAttempt::Env("wrong horse".to_string()),
            || panic!("environment passwords must not be retried"),
            test_decrypt_password_protected_paste,
        )
        .unwrap_err();

        assert!(matches!(error, Error::AuthenticationFailed(_)));
    }
}
