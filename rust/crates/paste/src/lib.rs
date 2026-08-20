use ente_core::b64;
use ente_core::crypto::{self, Key, argon, blob, secretbox};
use ente_core::http::{self, Api, ApiConfig, Http};
use serde::{Deserialize, Serialize};

pub const MAX_PASTE_CHARS: usize = 4000;

const FRAGMENT_SECRET_LENGTH: usize = 12;
const FRAGMENT_SECRET_ALPHABET: &[u8] =
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
#[cfg(not(target_arch = "wasm32"))]
const PASTE_GUARD_COOKIE: &str = "paste_guard";
const PASSWORD_FRAGMENT_PREFIX: &str = "p-";
const PASSWORD_KDF_CONTEXT: &str = "ente-paste-password-v1";

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] http::Error),

    #[error(transparent)]
    Crypto(#[from] crypto::Error),

    #[error("base64 decode error: {0}")]
    Base64Decode(#[from] b64::DecodeError),

    #[error("incorrect paste password")]
    IncorrectPassword,

    #[error("paste is unavailable")]
    Unavailable,

    #[error("paste text is empty")]
    EmptyText,

    #[error("paste text exceeds the maximum length")]
    TextTooLong,

    #[error("paste URL or access token is invalid")]
    InvalidLink,

    #[error("paste access token is invalid")]
    InvalidAccessToken,

    #[error("paste key is invalid")]
    InvalidKey,

    #[error("paste key is missing")]
    MissingKey,

    #[error("paste keys do not match")]
    KeyMismatch,

    #[error("paste password is required")]
    PasswordRequired,

    #[error("paste session is not open")]
    SessionNotOpen,

    #[error("the paste data is malformed or corrupted")]
    MalformedPayload,

    #[error("paste guard cookie was not returned")]
    MissingGuardCookie,
}

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Http(http::Error::Network(_)) => "network",
            Self::Http(_) => "request_failed",
            Self::Crypto(_) => "crypto",
            Self::Base64Decode(_) | Self::MalformedPayload => "malformed_payload",
            Self::IncorrectPassword => "incorrect_password",
            Self::Unavailable => "unavailable",
            Self::EmptyText => "empty_text",
            Self::TextTooLong => "text_too_long",
            Self::InvalidLink => "invalid_link",
            Self::InvalidAccessToken => "invalid_access_token",
            Self::InvalidKey => "invalid_key",
            Self::MissingKey => "missing_key",
            Self::KeyMismatch => "key_mismatch",
            Self::PasswordRequired => "password_required",
            Self::SessionNotOpen => "session_not_open",
            Self::MissingGuardCookie => "missing_guard_cookie",
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct PasteKey {
    fragment_secret: String,
    pub password_required: bool,
}

impl PasteKey {
    pub fn parse(raw: &str) -> Result<Self> {
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

    pub fn link_fragment(&self) -> String {
        if self.password_required {
            format!("{PASSWORD_FRAGMENT_PREFIX}{}", self.fragment_secret)
        } else {
            self.fragment_secret.clone()
        }
    }

    fn kdf_secret(&self, password: Option<&str>) -> Result<String> {
        if self.password_required {
            let password = password
                .filter(|password| !password.is_empty())
                .ok_or(Error::PasswordRequired)?;
            Ok(format!(
                "{PASSWORD_KDF_CONTEXT}\n{}\n{password}",
                self.fragment_secret
            ))
        } else {
            Ok(self.fragment_secret.clone())
        }
    }
}

fn validate_fragment_secret(fragment_secret: &str) -> Result<()> {
    if fragment_secret.len() == FRAGMENT_SECRET_LENGTH
        && fragment_secret
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric())
    {
        return Ok(());
    }

    Err(Error::InvalidKey)
}

#[derive(Debug)]
pub struct PasteLink {
    pub access_token: String,
    pub key: PasteKey,
}

impl PasteLink {
    pub fn parse(input: &str, key: Option<&str>) -> Result<Self> {
        let input = input.trim();
        if input.is_empty() {
            return Err(Error::InvalidLink);
        }

        let (access_token, embedded_secret) = match url::Url::parse(input) {
            Ok(url) => {
                let token = url
                    .path_segments()
                    .and_then(|mut segments| segments.rfind(|segment| !segment.is_empty()))
                    .ok_or(Error::InvalidLink)?;
                (token.to_string(), url.fragment().map(str::to_string))
            }
            Err(_) => match input.split_once('#') {
                Some((token, secret)) => {
                    (token.trim().to_string(), Some(secret.trim().to_string()))
                }
                None => (input.to_string(), None),
            },
        };

        if access_token.trim().is_empty() {
            return Err(Error::InvalidAccessToken);
        }
        validate_access_token(&access_token)?;

        let key = match (embedded_secret, key) {
            (Some(embedded), Some(key)) if embedded != key => {
                return Err(Error::KeyMismatch);
            }
            (Some(embedded), _) => PasteKey::parse(&embedded)?,
            (None, Some(key)) => PasteKey::parse(key)?,
            (None, None) => return Err(Error::MissingKey),
        };

        Ok(Self { access_token, key })
    }

    pub fn url(&self, paste_origin: &str) -> String {
        format!(
            "{}/{}#{}",
            paste_origin.trim_end_matches('/'),
            self.access_token,
            self.key.link_fragment()
        )
    }

    pub fn password_required(&self) -> bool {
        self.key.password_required
    }
}

fn validate_access_token(access_token: &str) -> Result<()> {
    if (6..=32).contains(&access_token.len())
        && access_token
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric())
    {
        return Ok(());
    }
    Err(Error::InvalidAccessToken)
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PastePayload {
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

pub struct Client {
    api: Api,
}

pub enum OpenPaste {
    PasswordRequired,
    Text(String),
}

pub struct PasteSession {
    link: PasteLink,
    payload: Option<PastePayload>,
}

impl PasteSession {
    pub fn parse(input: &str) -> Result<Self> {
        Ok(Self {
            link: PasteLink::parse(input, None)?,
            payload: None,
        })
    }

    pub async fn open(&mut self, client: &Client) -> Result<OpenPaste> {
        if self.link.password_required() {
            client.check(&self.link.access_token).await?;
            Ok(OpenPaste::PasswordRequired)
        } else {
            self.consume(client, None).await.map(OpenPaste::Text)
        }
    }

    pub async fn consume(&mut self, client: &Client, password: Option<&str>) -> Result<String> {
        if self.link.password_required() && password.filter(|value| !value.is_empty()).is_none() {
            return Err(Error::PasswordRequired);
        }
        if let Some(payload) = &self.payload {
            return decrypt(payload, &self.link.key, password);
        }

        let payload = client.consume(&self.link.access_token).await?;
        let result = decrypt(&payload, &self.link.key, password);
        self.payload = Some(payload);
        result
    }
}

impl Client {
    pub fn new(origin: String, user_agent: Option<String>) -> Result<Self> {
        Ok(Self {
            api: Api::new(
                Http::new()?,
                ApiConfig {
                    origin,
                    client_package: None,
                    client_version: None,
                    user_agent,
                    auth: None,
                },
            ),
        })
    }

    pub async fn create(&self, text: &str, password: Option<&str>) -> Result<PasteLink> {
        let (key, payload) = encrypt(text, password)?;
        let response: CreatePasteResponse = self
            .api
            .post("/paste/create")
            .json(&payload)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?;
        Ok(PasteLink {
            access_token: response.access_token,
            key,
        })
    }

    pub async fn check(&self, access_token: &str) -> Result<()> {
        validate_access_token(access_token)?;
        self.guard(access_token).await?;
        Ok(())
    }

    pub async fn consume(&self, access_token: &str) -> Result<PastePayload> {
        validate_access_token(access_token)?;
        #[cfg(target_arch = "wasm32")]
        self.guard(access_token).await?;
        #[cfg(not(target_arch = "wasm32"))]
        let cookie = self.guard(access_token).await?;
        let request = self
            .api
            .post("/paste/consume")
            .json(&PasteTokenRequest {
                access_token: access_token.to_string(),
            })
            .header("X-Paste-Consume", "1");
        #[cfg(target_arch = "wasm32")]
        let request = request.credentials_include();
        #[cfg(not(target_arch = "wasm32"))]
        let request = request.header("Cookie", &cookie);
        Ok(request
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(map_consume_error)?
            .json()
            .await?)
    }

    #[cfg(target_arch = "wasm32")]
    async fn guard(&self, access_token: &str) -> Result<()> {
        self.api
            .post("/paste/guard")
            .json(&PasteTokenRequest {
                access_token: access_token.to_string(),
            })
            .credentials_include()
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(map_consume_error)?;
        Ok(())
    }

    #[cfg(not(target_arch = "wasm32"))]
    async fn guard(&self, access_token: &str) -> Result<String> {
        let response = self
            .api
            .post("/paste/guard")
            .json(&PasteTokenRequest {
                access_token: access_token.to_string(),
            })
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(map_consume_error)?;
        let cookie_prefix = format!("{PASTE_GUARD_COOKIE}=");
        response
            .headers()
            .get_all("Set-Cookie")
            .iter()
            .filter_map(|value| value.to_str().ok())
            .filter_map(|value| value.split(';').next())
            .find(|value| value.starts_with(&cookie_prefix))
            .map(str::to_string)
            .ok_or(Error::MissingGuardCookie)
    }
}

fn map_consume_error(error: http::Error) -> Error {
    match error.status_code() {
        Some(404 | 410) => Error::Unavailable,
        _ => Error::Http(error),
    }
}

pub fn decrypt(payload: &PastePayload, key: &PasteKey, password: Option<&str>) -> Result<String> {
    let key_encryption_key = derive_key_encryption_key(key, password, payload)?;
    let (encrypted_paste_key, nonce) = decode_wrapped_paste_key(payload)?;
    let paste_key = match secretbox::decrypt(&encrypted_paste_key, &nonce, &key_encryption_key) {
        Ok(paste_key) => paste_key,
        Err(_) if key.password_required => return Err(Error::IncorrectPassword),
        Err(error) => return Err(error.into()),
    };
    decrypt_text(&paste_key, payload)
}

pub fn encrypt(text: &str, password: Option<&str>) -> Result<(PasteKey, PastePayload)> {
    validate_text(text)?;
    let params = if password.is_some() {
        argon::Params::MODERATE
    } else {
        argon::Params::INTERACTIVE
    };
    encrypt_with_kdf_params(text, password, params)
}

pub fn validate_text(text: &str) -> Result<()> {
    if text.trim().is_empty() {
        return Err(Error::EmptyText);
    }
    if text.chars().count() > MAX_PASTE_CHARS {
        return Err(Error::TextTooLong);
    }
    Ok(())
}

fn encrypt_with_kdf_params(
    text: &str,
    password: Option<&str>,
    params: argon::Params,
) -> Result<(PasteKey, PastePayload)> {
    let paste_key = Key::generate();
    let key_reference = PasteKey {
        fragment_secret: fragment_secret(),
        password_required: password.is_some(),
    };
    let encrypted = blob::encrypt_json(
        &PasteText {
            text: text.to_string(),
        },
        &paste_key,
    )?;
    let kdf_secret = key_reference.kdf_secret(password)?;
    let salt = crypto::Salt::generate();
    let key_encryption_key = argon::derive_key(&kdf_secret, &salt, params)?;
    let encrypted_paste_key = secretbox::encrypt(paste_key.as_bytes(), &key_encryption_key);

    Ok((
        key_reference,
        PastePayload {
            encrypted_data: b64::encode(&encrypted.encrypted_data),
            decryption_header: b64::encode(encrypted.decryption_header.as_bytes()),
            encrypted_paste_key: b64::encode(&encrypted_paste_key.encrypted_data),
            encrypted_paste_key_nonce: b64::encode(encrypted_paste_key.nonce.as_bytes()),
            kdf_nonce: b64::encode(salt.as_bytes()),
            kdf_mem_limit: params.mem_limit,
            kdf_ops_limit: params.ops_limit,
        },
    ))
}

fn derive_key_encryption_key(
    key: &PasteKey,
    password: Option<&str>,
    payload: &PastePayload,
) -> Result<Key> {
    let salt = crypto::Salt::try_from_slice(&b64::decode(&payload.kdf_nonce)?)?;
    let kdf_secret = key.kdf_secret(password)?;
    Ok(argon::derive_key(
        &kdf_secret,
        &salt,
        argon::Params {
            mem_limit: payload.kdf_mem_limit,
            ops_limit: payload.kdf_ops_limit,
        },
    )?)
}

fn decode_wrapped_paste_key(payload: &PastePayload) -> Result<(Vec<u8>, crypto::Nonce)> {
    let encrypted_paste_key = b64::decode(&payload.encrypted_paste_key)?;
    let encrypted_paste_key_nonce = b64::decode(&payload.encrypted_paste_key_nonce)?;
    if encrypted_paste_key.len() < secretbox::MAC_BYTES {
        return Err(Error::MalformedPayload);
    }
    let nonce = crypto::Nonce::try_from_slice(&encrypted_paste_key_nonce)
        .map_err(|_| Error::MalformedPayload)?;
    Ok((encrypted_paste_key, nonce))
}

fn decrypt_text(paste_key: &[u8], payload: &PastePayload) -> Result<String> {
    let encrypted_data = b64::decode(&payload.encrypted_data)?;
    let decryption_header = b64::decode(&payload.decryption_header)?;
    let text: PasteText = blob::decrypt_json(
        &blob::EncryptedBlob {
            encrypted_data,
            decryption_header: crypto::Header::try_from_slice(&decryption_header)?,
        },
        &Key::try_from_slice(paste_key)?,
    )?;
    Ok(text.text)
}

fn fragment_secret() -> String {
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

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};

    #[test]
    fn encrypt_then_decrypt_paste_payload() {
        let (paste_key, payload) = encrypt("hello paste", None).unwrap();
        let text = decrypt(&payload, &paste_key, None).unwrap();

        assert_eq!(text, "hello paste");
        assert_eq!(payload.kdf_mem_limit, argon::Params::INTERACTIVE.mem_limit);
        assert_eq!(payload.kdf_ops_limit, argon::Params::INTERACTIVE.ops_limit);
    }

    #[test]
    fn validate_paste_text() {
        assert!(validate_text("hello").is_ok());
        assert!(matches!(validate_text("  \n"), Err(Error::EmptyText)));
        assert!(validate_text(&"😀".repeat(MAX_PASTE_CHARS)).is_ok());
        assert!(matches!(
            validate_text(&"😀".repeat(MAX_PASTE_CHARS + 1)),
            Err(Error::TextTooLong)
        ));
        assert!(matches!(
            validate_text(&"a".repeat(MAX_PASTE_CHARS + 1)),
            Err(Error::TextTooLong)
        ));
    }

    #[test]
    fn encrypt_password_protected_paste_payload_uses_moderate_kdf() {
        let (paste_key, payload) = encrypt("protected paste", Some("correct horse")).unwrap();

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
    fn decrypt_password_protected_paste_payload() {
        let (paste_key, payload) =
            encrypt_with_kdf_params("protected paste", Some("correct horse"), argon::Params::MIN)
                .unwrap();
        let text = decrypt(&payload, &paste_key, Some("correct horse")).unwrap();

        assert_eq!(text, "protected paste");
    }

    #[test]
    fn decrypt_legacy_web_paste_payloads() {
        let payload: PastePayload = serde_json::from_str(
            r#"{"encryptedData":"niesGyZo1AlMtTMfgRLskd+McdrMTLRCt6nHvSY39Aw4U2clYPI01nj8VmTOyA==","decryptionHeader":"Lqb0aj5VlGwfTNi69GFvK7Rahl4dVa17","encryptedPasteKey":"+NH/0c9+yIfTGKFfs1fxvY7vPAB6OP0QcjBcZvZ01K/qGXoJTSJobjDNOmS5Si78","encryptedPasteKeyNonce":"+NAxXQ59SDU7YqWhJHpBvWqkuGerwvlh","kdfNonce":"xzT60ys77A8WEg4SToeRYQ==","kdfMemLimit":67108864,"kdfOpsLimit":2}"#,
        )
        .unwrap();
        assert_eq!(
            decrypt(&payload, &PasteKey::parse("AbCd1234EfGh").unwrap(), None).unwrap(),
            "legacy web fixture"
        );

        let payload: PastePayload = serde_json::from_str(
            r#"{"encryptedData":"FkWTCxgHGPAc+1v0B21D+4dYpZpNP33Xhd0MgmbvPg7d9EDFv5ZAt++NQ3NcfiFPtzHBrg==","decryptionHeader":"JV7V6Ba0/daql+mfQ/UpUSICw1ErDG3Q","encryptedPasteKey":"Wle7cpaMWaor0z8m1LYMufl7Qw5k3mNAF2OvjGZs4/nigJHgYbrjZaJN9KtkMGuW","encryptedPasteKeyNonce":"3gLFpRkUvzPTc7QYPzfZ9CrVOivJ5tZF","kdfNonce":"1PJBf1pkftMWXeKyJtb4tw==","kdfMemLimit":268435456,"kdfOpsLimit":3}"#,
        )
        .unwrap();
        assert_eq!(
            decrypt(
                &payload,
                &PasteKey::parse("p-1234567890ab").unwrap(),
                Some("correct horse")
            )
            .unwrap(),
            "legacy protected fixture"
        );
    }

    #[test]
    fn reject_wrong_paste_password() {
        let (paste_key, payload) =
            encrypt_with_kdf_params("protected paste", Some("correct horse"), argon::Params::MIN)
                .unwrap();
        let error = decrypt(&payload, &paste_key, Some("wrong horse")).unwrap_err();

        assert!(matches!(error, Error::IncorrectPassword));
    }

    #[test]
    fn structural_payload_errors_are_not_incorrect_password() {
        let (paste_key, mut payload) =
            encrypt_with_kdf_params("protected paste", Some("correct horse"), argon::Params::MIN)
                .unwrap();
        payload.kdf_nonce = "not base64".to_string();
        let error = decrypt(&payload, &paste_key, Some("correct horse")).unwrap_err();

        assert!(matches!(error, Error::Base64Decode(_)));
    }

    #[test]
    fn wrapped_key_payload_errors_are_not_incorrect_password() {
        let (paste_key, mut payload) =
            encrypt_with_kdf_params("protected paste", Some("correct horse"), argon::Params::MIN)
                .unwrap();
        payload.encrypted_paste_key = "not base64".to_string();
        let error = decrypt(&payload, &paste_key, Some("correct horse")).unwrap_err();

        assert!(matches!(error, Error::Base64Decode(_)));
    }

    #[test]
    fn parse_full_paste_link() {
        let link = PasteLink::parse("https://paste.ente.com/ABC123#AbCd1234EfGh", None).unwrap();

        assert_eq!(link.access_token, "ABC123");
        assert_eq!(
            link.key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: false,
            }
        );
    }

    #[test]
    fn parse_password_protected_paste_link() {
        let link = PasteLink::parse("https://paste.ente.com/ABC123#p-AbCd1234EfGh", None).unwrap();

        assert_eq!(link.access_token, "ABC123");
        assert_eq!(
            link.key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: true,
            }
        );
    }

    #[test]
    fn parse_token_with_key() {
        let link = PasteLink::parse("ABC123", Some("AbCd1234EfGh")).unwrap();

        assert_eq!(link.access_token, "ABC123");
        assert_eq!(
            link.key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: false,
            }
        );
    }

    #[test]
    fn parse_token_with_password_key() {
        let link = PasteLink::parse("ABC123", Some("p-AbCd1234EfGh")).unwrap();

        assert_eq!(link.access_token, "ABC123");
        assert_eq!(
            link.key,
            PasteKey {
                fragment_secret: "AbCd1234EfGh".to_string(),
                password_required: true,
            }
        );
    }

    #[test]
    fn reject_mismatched_fragment_and_key() {
        let error = PasteLink::parse(
            "https://paste.ente.com/ABC123#AbCd1234EfGh",
            Some("123456789012"),
        )
        .unwrap_err();

        assert!(matches!(error, Error::KeyMismatch));
    }

    #[tokio::test]
    async fn consume_uses_guard_cookie() {
        let access_token = "ABC123";
        let (paste_key, payload) =
            encrypt_with_kdf_params("guarded paste", None, argon::Params::MIN).unwrap();
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

        let client = Client::new(server.url(), None).unwrap();
        let payload = client.consume(access_token).await.unwrap();
        let text = decrypt(&payload, &paste_key, None).unwrap();

        assert_eq!(text, "guarded paste");
        guard.assert_async().await;
        consume.assert_async().await;
    }

    #[tokio::test]
    async fn session_retains_consumed_payload_for_password_retry() {
        let access_token = "ABC123";
        let password = "correct horse";
        let (key, payload) =
            encrypt_with_kdf_params("guarded paste", Some(password), argon::Params::MIN).unwrap();
        let mut server = Server::new_async().await;

        let guard = server
            .mock("POST", "/paste/guard")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "accessToken": access_token,
            })))
            .with_status(200)
            .with_header("set-cookie", "paste_guard=test-cookie; Path=/; HttpOnly")
            .with_body("{}")
            .expect(2)
            .create_async()
            .await;
        let consume = server
            .mock("POST", "/paste/consume")
            .match_header("x-paste-consume", "1")
            .match_header("cookie", "paste_guard=test-cookie")
            .with_status(200)
            .with_body(serde_json::to_string(&payload).unwrap())
            .create_async()
            .await;

        let client = Client::new(server.url(), None).unwrap();
        let mut session = PasteSession {
            link: PasteLink {
                access_token: access_token.to_string(),
                key,
            },
            payload: None,
        };

        assert!(matches!(
            session.open(&client).await.unwrap(),
            OpenPaste::PasswordRequired
        ));
        assert!(matches!(
            session.consume(&client, Some("wrong horse")).await,
            Err(Error::IncorrectPassword)
        ));
        assert_eq!(
            session.consume(&client, Some(password)).await.unwrap(),
            "guarded paste"
        );
        guard.assert_async().await;
        consume.assert_async().await;
    }

    #[tokio::test]
    async fn maps_unavailable_pastes() {
        let mut server = Server::new_async().await;
        let guard = server
            .mock("POST", "/paste/guard")
            .with_status(410)
            .with_body(r#"{"code":"NOT_FOUND"}"#)
            .create_async()
            .await;
        let client = Client::new(server.url(), None).unwrap();

        assert!(matches!(
            client.check("ABC123").await,
            Err(Error::Unavailable)
        ));
        guard.assert_async().await;
    }
}
