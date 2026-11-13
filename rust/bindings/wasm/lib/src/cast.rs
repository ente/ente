use serde::Serialize;
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Cast(#[from] ente_cast::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, None)
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct PreparedCastPayload {
    cast_token: String,
    encrypted_payload: String,
}

#[wasm_bindgen(js_name = castPreparePayload)]
pub fn prepare_payload(
    public_key: &str,
    pq_public_key: Option<String>,
    collection_id: i64,
    collection_key: &str,
) -> Result<<PreparedCastPayload as Tsify>::JsType, Error> {
    let payload = ente_cast::prepare_payload(
        public_key,
        pq_public_key.as_deref(),
        collection_id,
        collection_key,
    )?;
    PreparedCastPayload {
        cast_token: payload.cast_token,
        encrypted_payload: payload.encrypted_payload,
    }
    .into_js()
    .map_err(Into::into)
}
