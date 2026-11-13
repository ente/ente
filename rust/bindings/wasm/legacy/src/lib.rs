mod types;

use ente_legacy::LegacyKitRecoveryClient;
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use types::{LegacyKitRecoverySession, LegacyKitShare, OpenKitRecoveryInput};
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Legacy(#[from] ente_legacy::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Legacy(ente_legacy::Error::DifferentLegacyKits) => Some("different_legacy_kits"),
            Self::Legacy(ente_legacy::Error::DuplicateLegacyKitShare) => {
                Some("duplicate_legacy_kit_share")
            }
            Self::Legacy(ente_legacy::Error::LegacyKitInactive) => Some("legacy_kit_inactive"),
            Self::Legacy(ente_legacy::Error::LegacyKitSessionExpired) => {
                Some("legacy_kit_session_expired")
            }
            _ => None,
        }
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        ente_wasm_lib::js_error(&error, error.name())
    }
}

#[wasm_bindgen(js_name = parseLegacyKitShare)]
pub fn parse_legacy_kit_share(input: &str) -> Result<<LegacyKitShare as Tsify>::JsType, Error> {
    LegacyKitShare::from(ente_legacy::LegacyKitShare::parse(input)?)
        .into_js()
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = validateLegacyKitSharePair)]
pub fn validate_legacy_kit_share_pair(
    first: <LegacyKitShare as Tsify>::JsType,
    second: <LegacyKitShare as Tsify>::JsType,
) -> Result<(), Error> {
    ente_legacy::validate_share_pair(
        &LegacyKitShare::from_js(first)?.into(),
        &LegacyKitShare::from_js(second)?.into(),
    )
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = openKitRecovery)]
pub async fn open_kit_recovery(
    input: <OpenKitRecoveryInput as Tsify>::JsType,
) -> Result<LegacyKitRecoveryHandle, Error> {
    let input = OpenKitRecoveryInput::from_js(input)?;
    let client = LegacyKitRecoveryClient::new_with_headers(
        input.base_url,
        input.client_package,
        input.client_version,
        None,
    )?;
    let shares = input.shares.into_iter().map(Into::into).collect::<Vec<_>>();
    let handle = client
        .open_from_shares(&shares, input.email.as_deref())
        .await?;
    Ok(LegacyKitRecoveryHandle { inner: handle })
}

#[wasm_bindgen]
pub struct LegacyKitRecoveryHandle {
    inner: ente_legacy::LegacyKitRecoveryHandle,
}

#[wasm_bindgen]
impl LegacyKitRecoveryHandle {
    pub fn session(&self) -> Result<<LegacyKitRecoverySession as Tsify>::JsType, Error> {
        LegacyKitRecoverySession::from(self.inner.session().clone())
            .into_js()
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = refreshSession)]
    pub async fn refresh_session(
        &self,
    ) -> Result<<LegacyKitRecoverySession as Tsify>::JsType, Error> {
        LegacyKitRecoverySession::from(self.inner.refresh_session().await?)
            .into_js()
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = changePassword)]
    pub async fn change_password(&self, new_password: String) -> Result<(), Error> {
        Ok(self.inner.change_password(&new_password).await?)
    }
}
