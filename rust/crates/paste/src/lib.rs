use ente_core::b64;
use ente_core::crypto::{self, Key, argon, blob, secretbox};
use ente_core::http::{self, Api, ApiConfig, Http};
use serde::{Deserialize, Serialize};

pub const MAX_PASTE_CHARS: usize = 4000;

const FRAGMENT_SECRET_LENGTH: usize = 12;
const FRAGMENT_SECRET_ALPHABET: &[u8] =
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
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

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("the paste data is malformed or corrupted")]
    MalformedPayload,

    #[error("paste guard cookie was not returned")]
    MissingGuardCookie,
}

pub type Result<T> = std::result::Result<T, Error>;

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
                .ok_or_else(|| Error::InvalidInput("Paste password is required".to_string()))?;
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

    Err(Error::InvalidInput("Invalid paste key".to_string()))
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
            return Err(Error::InvalidInput(
                "Paste URL or access token is empty".to_string(),
            ));
        }

        let (access_token, embedded_secret) = match url::Url::parse(input) {
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
                Some((token, secret)) => {
                    (token.trim().to_string(), Some(secret.trim().to_string()))
                }
                None => (input.to_string(), None),
            },
        };

        if access_token.trim().is_empty() {
            return Err(Error::InvalidInput(
                "Paste access token is empty".to_string(),
            ));
        }

        let key = match (embedded_secret, key) {
            (Some(embedded), Some(key)) if embedded != key => {
                return Err(Error::InvalidInput(
                    "Paste URL fragment and --key do not match".to_string(),
                ));
            }
            (Some(embedded), _) => PasteKey::parse(&embedded)?,
            (None, Some(key)) => PasteKey::parse(key)?,
            (None, None) => {
                return Err(Error::InvalidInput(
                    "Paste key missing. Pass a full paste URL or --key".to_string(),
                ));
            }
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
        self.guard(access_token).await?;
        Ok(())
    }

    pub async fn consume(&self, access_token: &str) -> Result<PastePayload> {
        let cookie = self.guard(access_token).await?;
        Ok(self
            .api
            .post("/paste/consume")
            .json(&PasteTokenRequest {
                access_token: access_token.to_string(),
            })
            .header("X-Paste-Consume", "1")
            .header("Cookie", &cookie)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

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
            .await?;

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
    let params = if password.is_some() {
        argon::Params::MODERATE
    } else {
        argon::Params::INTERACTIVE
    };
    encrypt_with_kdf_params(text, password, params)
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

        assert!(matches!(error, Error::InvalidInput(_)));
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
}
