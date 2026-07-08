use crate::{
    api::client::USER_AGENT,
    cli::paste::{PasteCommand, PasteSubcommands},
    models::error::{Error, Result},
};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use dialoguer::Password;
use ente_core::crypto::{self, Key, argon, blob, secretbox};
use reqwest::{Client, StatusCode, header};
use serde::{Deserialize, Serialize};
use std::ffi::OsStr;
use std::io::{self, IsTerminal, Read};
use std::path::PathBuf;

const MAX_PASTE_CHARS: usize = 4000;
const FRAGMENT_SECRET_LENGTH: usize = 12;
const FRAGMENT_SECRET_ALPHABET: &[u8] =
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const PASTE_GUARD_COOKIE: &str = "paste_guard";
const PASTE_PASSWORD_ENV: &str = "ENTE_PASTE_PASSWORD";
const PASSWORD_FRAGMENT_PREFIX: &str = "p-";
const PASSWORD_KDF_CONTEXT: &str = "ente-paste-password-v1";

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
            let link = create_paste(&endpoint, &paste_origin, &text, password.as_deref()).await?;
            println!("{link}");
            Ok(())
        }
        PasteSubcommands::Consume {
            link_or_token,
            raw,
            key,
            endpoint,
        } => {
            let (access_token, paste_key) = parse_paste_reference(&link_or_token, key)?;
            let text = consume_paste(&endpoint, &access_token, &paste_key).await?;
            print_consumed_paste(&text, raw);
            Ok(())
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
    if text.chars().count() > MAX_PASTE_CHARS {
        return Err(Error::InvalidInput(format!(
            "Paste is limited to {MAX_PASTE_CHARS} characters"
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

async fn create_paste(
    endpoint: &str,
    paste_origin: &str,
    text: &str,
    password: Option<&str>,
) -> Result<String> {
    let client = paste_http_client()?;
    let (paste_key, payload) = encrypt_paste_for_create(text, password)?;
    let response: CreatePasteResponse =
        post_json(&client, endpoint, "/paste/create", &payload, None, None).await?;
    Ok(build_paste_link(
        paste_origin,
        &response.access_token,
        &paste_key.link_fragment(),
    ))
}

async fn consume_paste(endpoint: &str, access_token: &str, paste_key: &PasteKey) -> Result<String> {
    consume_paste_with_password_resolver(
        endpoint,
        access_token,
        paste_key,
        resolve_paste_password_attempt,
    )
    .await
}

async fn consume_paste_with_password_resolver<F>(
    endpoint: &str,
    access_token: &str,
    paste_key: &PasteKey,
    resolve_password: F,
) -> Result<String>
where
    F: FnOnce() -> Result<PastePasswordAttempt>,
{
    let client = paste_http_client()?;
    let request = PasteTokenRequest {
        access_token: access_token.to_string(),
    };
    let password = if paste_key.password_required {
        guard_cookie(&client, endpoint, &request).await?;
        Some(resolve_password()?)
    } else {
        None
    };
    let cookie = guard_cookie(&client, endpoint, &request).await?;
    let payload = consume_paste_payload(&client, endpoint, &request, &cookie).await?;

    match password {
        Some(password) => decrypt_password_protected_paste(paste_key, &payload, password),
        None => decrypt_consumed_paste(paste_key, None, &payload),
    }
}

async fn consume_paste_payload(
    client: &Client,
    endpoint: &str,
    request: &PasteTokenRequest,
    cookie: &str,
) -> Result<PastePayload> {
    post_json(
        client,
        endpoint,
        "/paste/consume",
        &request,
        Some(("X-Paste-Consume", "1")),
        Some(cookie),
    )
    .await
}

fn decrypt_password_protected_paste(
    paste_key: &PasteKey,
    payload: &PastePayload,
    password: PastePasswordAttempt,
) -> Result<String> {
    decrypt_password_protected_paste_with_prompt(
        paste_key,
        payload,
        password,
        prompt_raw_paste_password,
    )
}

fn decrypt_password_protected_paste_with_prompt<F>(
    paste_key: &PasteKey,
    payload: &PastePayload,
    mut password: PastePasswordAttempt,
    mut prompt_password: F,
) -> Result<String>
where
    F: FnMut() -> Result<String>,
{
    loop {
        let key_encryption_key =
            derive_paste_key_encryption_key(paste_key, Some(password.value()), payload)?;
        let paste_key = match decrypt_paste_key_for_password(payload, &key_encryption_key) {
            Ok(paste_key) => paste_key,
            Err(Error::AuthenticationFailed(_)) if password.can_retry() => {
                eprintln!("Incorrect paste password. Try again.");
                password = PastePasswordAttempt::Prompted(prompt_valid_paste_password(
                    &mut prompt_password,
                )?);
                continue;
            }
            Err(error) => return Err(error),
        };
        return decrypt_consumed_text(&paste_key, payload);
    }
}

fn paste_http_client() -> Result<Client> {
    Ok(Client::builder().user_agent(USER_AGENT).build()?)
}

async fn guard_cookie(
    client: &Client,
    endpoint: &str,
    request: &PasteTokenRequest,
) -> Result<String> {
    let url = api_url(endpoint, "/paste/guard");
    let response = client.post(url).json(request).send().await?;
    if !response.status().is_success() {
        return Err(api_error(response).await);
    }

    let cookie_prefix = format!("{PASTE_GUARD_COOKIE}=");
    response
        .headers()
        .get_all(header::SET_COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .filter_map(|value| value.split(';').next())
        .find(|value| value.starts_with(&cookie_prefix))
        .map(str::to_string)
        .ok_or_else(|| Error::Generic("Paste guard cookie was not returned".to_string()))
}

async fn post_json<T, B>(
    client: &Client,
    endpoint: &str,
    path: &str,
    body: &B,
    header_pair: Option<(&str, &str)>,
    cookie: Option<&str>,
) -> Result<T>
where
    T: for<'de> Deserialize<'de>,
    B: Serialize,
{
    let mut request = client.post(api_url(endpoint, path)).json(body);
    if let Some((name, value)) = header_pair {
        request = request.header(name, value);
    }
    if let Some(cookie) = cookie {
        request = request.header(header::COOKIE, cookie);
    }

    let response = request.send().await?;
    if !response.status().is_success() {
        return Err(api_error(response).await);
    }

    Ok(response.json().await?)
}

async fn api_error(response: reqwest::Response) -> Error {
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    let parsed = serde_json::from_str::<ApiErrorBody>(&body).ok();
    let message = parsed
        .as_ref()
        .and_then(|body| body.message.clone().or_else(|| body.code.clone()))
        .unwrap_or_else(|| status_message(status, &body));

    Error::ApiError {
        status: status.as_u16(),
        code: parsed.and_then(|body| body.code),
        message,
    }
}

fn status_message(status: StatusCode, body: &str) -> String {
    if body.trim().is_empty() {
        status.to_string()
    } else {
        body.to_string()
    }
}

fn api_url(endpoint: &str, path: &str) -> String {
    format!("{}{}", endpoint.trim_end_matches('/'), path)
}

fn build_paste_link(paste_origin: &str, access_token: &str, fragment_secret: &str) -> String {
    format!(
        "{}/{}#{}",
        paste_origin.trim_end_matches('/'),
        access_token,
        fragment_secret
    )
}

fn encrypt_paste_for_create(
    text: &str,
    password: Option<&str>,
) -> Result<(PasteKey, PastePayload)> {
    let paste_key = Key::generate();
    let fragment_secret = create_fragment_secret();
    let paste_key_reference = PasteKey {
        fragment_secret,
        password_required: password.is_some(),
    };
    let encrypted = blob::encrypt_json(
        &PasteText {
            text: text.to_string(),
        },
        &paste_key,
    )?;
    let kdf_secret = paste_key_reference.kdf_secret(password)?;
    let key_encryption_key = if password.is_some() {
        argon::derive_moderate_key(&kdf_secret)?
    } else {
        argon::derive_interactive_key(&kdf_secret)?
    };
    let encrypted_paste_key = secretbox::encrypt(paste_key.as_bytes(), &key_encryption_key.key);

    Ok((
        paste_key_reference,
        PastePayload {
            encrypted_data: crypto::encode_b64(&encrypted.encrypted_data),
            decryption_header: crypto::encode_b64(encrypted.decryption_header.as_bytes()),
            encrypted_paste_key: crypto::encode_b64(&encrypted_paste_key.encrypted_data),
            encrypted_paste_key_nonce: crypto::encode_b64(encrypted_paste_key.nonce.as_bytes()),
            kdf_nonce: crypto::encode_b64(key_encryption_key.salt.as_bytes()),
            kdf_mem_limit: key_encryption_key.params.mem_limit,
            kdf_ops_limit: key_encryption_key.params.ops_limit,
        },
    ))
}

fn decrypt_consumed_paste(
    paste_key: &PasteKey,
    password: Option<&str>,
    payload: &PastePayload,
) -> Result<String> {
    let key_encryption_key = derive_paste_key_encryption_key(paste_key, password, payload)?;
    let paste_key = decrypt_wrapped_paste_key(payload, &key_encryption_key)?;
    decrypt_consumed_text(&paste_key, payload)
}

fn derive_paste_key_encryption_key(
    paste_key: &PasteKey,
    password: Option<&str>,
    payload: &PastePayload,
) -> Result<crypto::Key> {
    let salt = crypto::Salt::try_from_slice(&BASE64.decode(&payload.kdf_nonce)?)?;
    let kdf_secret = paste_key.kdf_secret(password)?;
    Ok(argon::derive_key(
        &kdf_secret,
        &salt,
        argon::Params {
            mem_limit: payload.kdf_mem_limit,
            ops_limit: payload.kdf_ops_limit,
        },
    )?)
}

fn decrypt_paste_key_for_password(
    payload: &PastePayload,
    key_encryption_key: &Key,
) -> Result<Vec<u8>> {
    let (encrypted_paste_key, nonce) = decode_wrapped_paste_key(payload)?;
    secretbox::decrypt(&encrypted_paste_key, &nonce, key_encryption_key)
        .map_err(|_| Error::AuthenticationFailed("Incorrect paste password".to_string()))
}

fn decrypt_wrapped_paste_key(payload: &PastePayload, key_encryption_key: &Key) -> Result<Vec<u8>> {
    let (encrypted_paste_key, nonce) = decode_wrapped_paste_key(payload)?;
    Ok(secretbox::decrypt(
        &encrypted_paste_key,
        &nonce,
        key_encryption_key,
    )?)
}

fn decode_wrapped_paste_key(payload: &PastePayload) -> Result<(Vec<u8>, crypto::Nonce)> {
    let encrypted_paste_key = BASE64.decode(&payload.encrypted_paste_key)?;
    let encrypted_paste_key_nonce = BASE64.decode(&payload.encrypted_paste_key_nonce)?;
    if encrypted_paste_key.len() < secretbox::MAC_BYTES {
        return Err(invalid_paste_payload());
    }
    let nonce = crypto::Nonce::try_from_slice(&encrypted_paste_key_nonce)
        .map_err(|_| invalid_paste_payload())?;
    Ok((encrypted_paste_key, nonce))
}

fn decrypt_consumed_text(paste_key: &[u8], payload: &PastePayload) -> Result<String> {
    let encrypted_data = BASE64.decode(&payload.encrypted_data)?;
    let decryption_header = BASE64.decode(&payload.decryption_header)?;
    let text: PasteText = blob::decrypt_json(
        &blob::EncryptedBlob {
            encrypted_data,
            decryption_header: crypto::Header::try_from_slice(&decryption_header)?,
        },
        &Key::try_from_slice(paste_key)?,
    )?;
    Ok(text.text)
}

fn invalid_paste_payload() -> Error {
    Error::Crypto("The paste data is malformed or corrupted".to_string())
}

fn create_fragment_secret() -> String {
    let mut secret = String::with_capacity(FRAGMENT_SECRET_LENGTH);
    let threshold = 256 - (256 % FRAGMENT_SECRET_ALPHABET.len());

    while secret.len() < FRAGMENT_SECRET_LENGTH {
        for byte in crypto::random_bytes(FRAGMENT_SECRET_LENGTH) {
            let byte = usize::from(byte);
            if byte >= threshold {
                continue;
            }
            let index = byte % FRAGMENT_SECRET_ALPHABET.len();
            secret.push(char::from(FRAGMENT_SECRET_ALPHABET[index]));
            if secret.len() == FRAGMENT_SECRET_LENGTH {
                break;
            }
        }
    }

    secret
}

fn parse_paste_reference(input: &str, key: Option<String>) -> Result<(String, PasteKey)> {
    let input = input.trim();
    if input.is_empty() {
        return Err(Error::InvalidInput(
            "Paste URL or access token is empty".to_string(),
        ));
    }

    let (access_token, embedded_secret) = match reqwest::Url::parse(input) {
        Ok(url) => {
            let token = url
                .path_segments()
                .and_then(|mut segments| segments.rfind(|segment| !segment.is_empty()))
                .ok_or_else(|| {
                    Error::InvalidInput("Paste URL is missing an access token".into())
                })?;
            (token.to_string(), url.fragment().map(str::to_string))
        }
        Err(_) => match input.split_once('#') {
            Some((token, secret)) => (token.trim().to_string(), Some(secret.trim().to_string())),
            None => (input.to_string(), None),
        },
    };

    if access_token.trim().is_empty() {
        return Err(Error::InvalidInput(
            "Paste access token is empty".to_string(),
        ));
    }

    let paste_key = match (embedded_secret, key) {
        (Some(embedded), Some(key)) if embedded != key => {
            return Err(Error::InvalidInput(
                "Paste URL fragment and --key do not match".to_string(),
            ));
        }
        (Some(embedded), _) => PasteKey::parse(&embedded)?,
        (None, Some(key)) => PasteKey::parse(&key)?,
        (None, None) => {
            return Err(Error::InvalidInput(
                "Paste key missing. Pass a full paste URL or --key".to_string(),
            ));
        }
    };

    Ok((access_token, paste_key))
}

fn validate_fragment_secret(fragment_secret: &str) -> Result<()> {
    if fragment_secret.len() == FRAGMENT_SECRET_LENGTH
        && fragment_secret
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric())
    {
        return Ok(());
    }

    Err(Error::InvalidInput("Invalid paste key".to_string()))
}

#[derive(Debug, Eq, PartialEq)]
struct PasteKey {
    fragment_secret: String,
    password_required: bool,
}

impl PasteKey {
    fn parse(raw: &str) -> Result<Self> {
        let (password_required, fragment_secret) = match raw.strip_prefix(PASSWORD_FRAGMENT_PREFIX)
        {
            Some(fragment_secret) => (true, fragment_secret),
            None => (false, raw),
        };
        validate_fragment_secret(fragment_secret)?;
        Ok(Self {
            fragment_secret: fragment_secret.to_string(),
            password_required,
        })
    }

    fn link_fragment(&self) -> String {
        if self.password_required {
            format!("{PASSWORD_FRAGMENT_PREFIX}{}", self.fragment_secret)
        } else {
            self.fragment_secret.clone()
        }
    }

    fn kdf_secret(&self, password: Option<&str>) -> Result<String> {
        if self.password_required {
            let password = password
                .ok_or_else(|| Error::InvalidInput("Paste password is required".to_string()))?;
            validate_password(password)?;
            Ok(format!(
                "{PASSWORD_KDF_CONTEXT}\n{}\n{password}",
                self.fragment_secret
            ))
        } else {
            Ok(self.fragment_secret.clone())
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PastePayload {
    encrypted_data: String,
    decryption_header: String,
    encrypted_paste_key: String,
    encrypted_paste_key_nonce: String,
    kdf_nonce: String,
    kdf_mem_limit: u32,
    kdf_ops_limit: u32,
}

#[derive(Serialize, Deserialize)]
struct PasteText {
    text: String,
}

#[derive(Deserialize)]
struct CreatePasteResponse {
    #[serde(rename = "accessToken")]
    access_token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PasteTokenRequest {
    access_token: String,
}

#[derive(Deserialize)]
struct ApiErrorBody {
    code: Option<String>,
    message: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};

    #[test]
    fn encrypt_then_decrypt_paste_payload() {
        let (paste_key, payload) = encrypt_paste_for_create("hello paste", None).unwrap();
        let text = decrypt_consumed_paste(&paste_key, None, &payload).unwrap();

        assert_eq!(text, "hello paste");
        assert_eq!(payload.kdf_mem_limit, argon::Params::INTERACTIVE.mem_limit);
        assert_eq!(payload.kdf_ops_limit, argon::Params::INTERACTIVE.ops_limit);
    }

    #[test]
    fn encrypt_then_decrypt_password_protected_paste_payload() {
        let (paste_key, payload) =
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
        let text = decrypt_consumed_paste(&paste_key, Some("correct horse"), &payload).unwrap();

        assert_eq!(text, "protected paste");
        assert!(paste_key.password_required);
        assert!(
            paste_key
                .link_fragment()
                .starts_with(PASSWORD_FRAGMENT_PREFIX)
        );
        assert_eq!(payload.kdf_mem_limit, argon::Params::MODERATE.mem_limit);
        assert_eq!(payload.kdf_ops_limit, argon::Params::MODERATE.ops_limit);
    }

    #[test]
    fn reject_wrong_paste_password() {
        let (paste_key, payload) =
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
        let error = decrypt_consumed_paste(&paste_key, Some("wrong horse"), &payload).unwrap_err();

        assert!(matches!(error, Error::Crypto(_)));
    }

    #[test]
    fn reject_wrong_env_paste_password() {
        let (paste_key, payload) =
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
        let error = decrypt_password_protected_paste(
            &paste_key,
            &payload,
            PastePasswordAttempt::Env("wrong horse".to_string()),
        )
        .unwrap_err();

        assert!(matches!(error, Error::AuthenticationFailed(_)));
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
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
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
        let (paste_key, payload) =
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
        let mut retry_passwords = ["", "correct horse"].into_iter();
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
    fn prompted_password_retry_does_not_hide_structural_payload_errors() {
        let (paste_key, mut payload) =
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
        payload.kdf_nonce = "not base64".to_string();
        let mut prompts = 0;
        let error = decrypt_password_protected_paste_with_prompt(
            &paste_key,
            &payload,
            PastePasswordAttempt::Prompted("correct horse".to_string()),
            || {
                prompts += 1;
                Ok::<_, Error>("correct horse".to_string())
            },
        )
        .unwrap_err();

        assert!(matches!(error, Error::Base64Decode(_)));
        assert_eq!(prompts, 0);
    }

    #[test]
    fn prompted_password_retry_does_not_hide_wrapped_key_payload_errors() {
        let (paste_key, mut payload) =
            encrypt_paste_for_create("protected paste", Some("correct horse")).unwrap();
        payload.encrypted_paste_key = "not base64".to_string();
        let mut prompts = 0;
        let error = decrypt_password_protected_paste_with_prompt(
            &paste_key,
            &payload,
            PastePasswordAttempt::Prompted("correct horse".to_string()),
            || {
                prompts += 1;
                Ok::<_, Error>("correct horse".to_string())
            },
        )
        .unwrap_err();

        assert!(matches!(error, Error::Base64Decode(_)));
        assert_eq!(prompts, 0);
    }

    #[test]
    fn parse_full_paste_link() {
        let (token, paste_key) =
            parse_paste_reference("https://paste.ente.com/ABC123#AbCd1234EfGh", None).unwrap();

        assert_eq!(token, "ABC123");
        assert_eq!(
            paste_key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: false,
            }
        );
    }

    #[test]
    fn parse_password_protected_paste_link() {
        let (token, paste_key) =
            parse_paste_reference("https://paste.ente.com/ABC123#p-AbCd1234EfGh", None).unwrap();

        assert_eq!(token, "ABC123");
        assert_eq!(
            paste_key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: true,
            }
        );
    }

    #[test]
    fn parse_token_with_key() {
        let (token, paste_key) =
            parse_paste_reference("ABC123", Some("AbCd1234EfGh".to_string())).unwrap();

        assert_eq!(token, "ABC123");
        assert_eq!(
            paste_key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: false,
            }
        );
    }

    #[test]
    fn parse_token_with_password_key() {
        let (token, paste_key) =
            parse_paste_reference("ABC123", Some("p-AbCd1234EfGh".to_string())).unwrap();

        assert_eq!(token, "ABC123");
        assert_eq!(
            paste_key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: true,
            }
        );
    }

    #[test]
    fn reject_mismatched_fragment_and_key() {
        let error = parse_paste_reference(
            "https://paste.ente.com/ABC123#AbCd1234EfGh",
            Some("123456789012".to_string()),
        )
        .unwrap_err();

        assert!(matches!(error, Error::InvalidInput(_)));
    }

    #[tokio::test]
    async fn consume_paste_uses_guard_cookie_and_decrypts_payload() {
        let access_token = "ABC123";
        let paste_key = PasteKey::parse("AbCd1234EfGh").unwrap();
        let payload = test_payload("guarded paste", &paste_key, None);
        let mut server = Server::new_async().await;

        let guard = server
            .mock("POST", "/paste/guard")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "accessToken": access_token,
            })))
            .with_status(200)
            .with_header("set-cookie", "paste_guard=test-cookie; Path=/; HttpOnly")
            .with_body("{}")
            .create_async()
            .await;

        let consume = server
            .mock("POST", "/paste/consume")
            .match_header("x-paste-consume", "1")
            .match_header("cookie", "paste_guard=test-cookie")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "accessToken": access_token,
            })))
            .with_status(200)
            .with_body(serde_json::to_string(&payload).unwrap())
            .create_async()
            .await;

        let text = consume_paste(&server.url(), access_token, &paste_key)
            .await
            .unwrap();

        assert_eq!(text, "guarded paste");
        guard.assert_async().await;
        consume.assert_async().await;
    }

    #[tokio::test]
    async fn password_paste_refreshes_guard_after_password_resolution() {
        let access_token = "ABC123";
        let paste_key = PasteKey::parse("p-AbCd1234EfGh").unwrap();
        let payload = test_payload("guarded paste", &paste_key, Some("correct horse"));
        let mut server = Server::new_async().await;

        let availability_guard = server
            .mock("POST", "/paste/guard")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "accessToken": access_token,
            })))
            .with_status(200)
            .with_header(
                "set-cookie",
                "paste_guard=availability-cookie; Path=/; HttpOnly",
            )
            .with_body("{}")
            .expect(1)
            .create_async()
            .await;

        let consume_guard = server
            .mock("POST", "/paste/guard")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "accessToken": access_token,
            })))
            .with_status(200)
            .with_header("set-cookie", "paste_guard=consume-cookie; Path=/; HttpOnly")
            .with_body("{}")
            .expect(1)
            .create_async()
            .await;

        let consume = server
            .mock("POST", "/paste/consume")
            .match_header("x-paste-consume", "1")
            .match_header("cookie", "paste_guard=consume-cookie")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "accessToken": access_token,
            })))
            .with_status(200)
            .with_body(serde_json::to_string(&payload).unwrap())
            .create_async()
            .await;

        let text =
            consume_paste_with_password_resolver(&server.url(), access_token, &paste_key, || {
                Ok(PastePasswordAttempt::Env("correct horse".to_string()))
            })
            .await
            .unwrap();

        assert_eq!(text, "guarded paste");
        availability_guard.assert_async().await;
        consume_guard.assert_async().await;
        consume.assert_async().await;
    }

    fn test_payload(text: &str, key_reference: &PasteKey, password: Option<&str>) -> PastePayload {
        let paste_key = Key::from_bytes([7u8; Key::BYTES]);
        let encrypted = blob::encrypt_json(
            &PasteText {
                text: text.to_string(),
            },
            &paste_key,
        )
        .unwrap();
        let salt = crypto::Salt::from_bytes([9u8; crypto::Salt::BYTES]);
        let kdf_secret = key_reference.kdf_secret(password).unwrap();
        let key_encryption_key = argon::derive_key(&kdf_secret, &salt, argon::Params::MIN).unwrap();
        let encrypted_paste_key = secretbox::encrypt(paste_key.as_bytes(), &key_encryption_key);

        PastePayload {
            encrypted_data: crypto::encode_b64(&encrypted.encrypted_data),
            decryption_header: crypto::encode_b64(encrypted.decryption_header.as_bytes()),
            encrypted_paste_key: crypto::encode_b64(&encrypted_paste_key.encrypted_data),
            encrypted_paste_key_nonce: crypto::encode_b64(encrypted_paste_key.nonce.as_bytes()),
            kdf_nonce: crypto::encode_b64(salt.as_bytes()),
            kdf_mem_limit: argon::Params::MIN.mem_limit,
            kdf_ops_limit: argon::Params::MIN.ops_limit,
        }
    }
}
