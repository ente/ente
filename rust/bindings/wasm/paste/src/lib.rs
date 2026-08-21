use ente_paste::{Client, OpenPaste, PasteSession};
use ente_wasm_log as _;
use wasm_bindgen::prelude::*;

pub struct PasteError(ente_paste::Error);

impl From<ente_paste::Error> for PasteError {
    fn from(error: ente_paste::Error) -> Self {
        Self(error)
    }
}

impl From<PasteError> for JsValue {
    fn from(error: PasteError) -> Self {
        let js_error = js_sys::Error::new(&error.0.to_string());
        js_error.set_name(error.0.code());
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
    pub fn new(api_origin: String) -> Result<Self, PasteError> {
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
    ) -> Result<CreatedPaste, PasteError> {
        let link = self.client.create(text, password.as_deref()).await?;
        Ok(CreatedPaste {
            url: link.url(paste_origin),
            password_required: link.password_required(),
        })
    }

    pub async fn open(&mut self, url: &str) -> Result<OpenedPaste, PasteError> {
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
    pub async fn submit_password(&mut self, password: &str) -> Result<String, PasteError> {
        self.session
            .as_mut()
            .ok_or(ente_paste::Error::SessionNotOpen)?
            .consume(&self.client, Some(password))
            .await
            .map_err(Into::into)
    }
}
