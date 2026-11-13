use ente_paste::{Client, OpenPaste, PasteSession};
use serde::Serialize;
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Paste(#[from] ente_paste::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
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
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        ente_wasm_lib::js_error(&error, error.name())
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct CreatedPaste {
    url: String,
    password_required: bool,
}

#[derive(Serialize, Tsify)]
#[serde(untagged, rename_all_fields = "camelCase")]
pub enum OpenedPaste {
    PasswordRequired {
        #[tsify(type = "true")]
        password_required: bool,
    },
    Text {
        #[tsify(type = "false")]
        password_required: bool,
        text: String,
    },
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
    ) -> Result<<CreatedPaste as Tsify>::JsType, Error> {
        let link = self.client.create(text, password.as_deref()).await?;
        CreatedPaste {
            url: link.url(paste_origin),
            password_required: link.password_required(),
        }
        .into_js()
        .map_err(Into::into)
    }

    pub async fn open(&mut self, url: &str) -> Result<<OpenedPaste as Tsify>::JsType, Error> {
        let mut session = PasteSession::parse(url)?;
        let opened = match session.open(&self.client).await? {
            OpenPaste::PasswordRequired => OpenedPaste::PasswordRequired {
                password_required: true,
            },
            OpenPaste::Text(text) => OpenedPaste::Text {
                password_required: false,
                text,
            },
        };
        self.session = Some(session);
        opened.into_js().map_err(Into::into)
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
