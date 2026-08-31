use ente_paste::{Client, OpenPaste, PasteSession};
use ente_wasm_log as _;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Paste(#[from] ente_paste::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        use ente_paste::Error as E;

        match self {
            Self::Paste(E::Http(ente_core::http::Error::Network(_))) => Some("network"),
            Self::Paste(E::Http(_)) => Some("request_failed"),
            Self::Paste(E::Crypto(_)) => Some("crypto"),
            Self::Paste(E::Base64Decode(_)) | Self::Paste(E::MalformedPayload) => {
                Some("malformed_payload")
            }
            Self::Paste(E::IncorrectPassword) => Some("incorrect_password"),
            Self::Paste(E::Unavailable) => Some("unavailable"),
            Self::Paste(E::EmptyText) => Some("empty_text"),
            Self::Paste(E::TextTooLong) => Some("text_too_long"),
            Self::Paste(E::InvalidLink) => Some("invalid_link"),
            Self::Paste(E::InvalidAccessToken) => Some("invalid_access_token"),
            Self::Paste(E::InvalidKey) => Some("invalid_key"),
            Self::Paste(E::MissingKey) => Some("missing_key"),
            Self::Paste(E::KeyMismatch) => Some("key_mismatch"),
            Self::Paste(E::PasswordRequired) => Some("password_required"),
            _ => None,
        }
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        let js_error = js_sys::Error::new(&error.message());
        if let Some(name) = error.name() {
            js_error.set_name(name);
        }
        js_error.into()
    }
}

#[wasm_bindgen]
pub struct CreatedPaste {
    url: String,
    password_required: bool,
}

#[wasm_bindgen]
impl CreatedPaste {
    #[wasm_bindgen(getter)]
    pub fn url(&self) -> String {
        self.url.clone()
    }

    #[wasm_bindgen(getter, js_name = passwordRequired)]
    pub fn password_required(&self) -> bool {
        self.password_required
    }
}

#[wasm_bindgen]
pub struct OpenedPaste {
    password_required: bool,
    text: Option<String>,
}

#[wasm_bindgen]
impl OpenedPaste {
    #[wasm_bindgen(getter, js_name = passwordRequired)]
    pub fn password_required(&self) -> bool {
        self.password_required
    }

    #[wasm_bindgen(getter)]
    pub fn text(&self) -> Option<String> {
        self.text.clone()
    }
}

#[wasm_bindgen]
pub struct PasteClient {
    client: Client,
    session: Option<PasteSession>,
}

#[wasm_bindgen]
impl PasteClient {
    #[wasm_bindgen(constructor)]
    pub fn new(api_origin: String) -> Result<Self, Error> {
        Ok(Self {
            client: Client::new(api_origin, None)?,
            session: None,
        })
    }

    pub async fn create(
        &self,
        paste_origin: &str,
        text: &str,
        password: Option<String>,
    ) -> Result<CreatedPaste, Error> {
        let link = self.client.create(text, password.as_deref()).await?;
        Ok(CreatedPaste {
            url: link.url(paste_origin),
            password_required: link.password_required(),
        })
    }

    pub async fn open(&mut self, url: &str) -> Result<OpenedPaste, Error> {
        let mut session = PasteSession::parse(url)?;
        let opened = match session.open(&self.client).await? {
            OpenPaste::PasswordRequired => OpenedPaste {
                password_required: true,
                text: None,
            },
            OpenPaste::Text(text) => OpenedPaste {
                password_required: false,
                text: Some(text),
            },
        };
        self.session = Some(session);
        Ok(opened)
    }

    #[wasm_bindgen(js_name = submitPassword)]
    pub async fn submit_password(&mut self, password: &str) -> Result<String, Error> {
        self.session
            .as_mut()
            .ok_or(ente_paste::Error::SessionNotOpen)?
            .consume(&self.client, Some(password))
            .await
            .map_err(Into::into)
    }
}
