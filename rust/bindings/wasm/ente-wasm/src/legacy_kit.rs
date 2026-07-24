//! WASM bindings for offline legacy-kit recovery.

use ente_contacts::{LegacyKitRecoveryClient, LegacyKitShare};
use serde::Deserialize;
use serde_wasm_bindgen as swb;
use wasm_bindgen::prelude::*;

use crate::contacts::ContactsError;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenLegacyKitRecoveryInput {
    base_url: String,
    shares: Vec<LegacyKitShare>,
    email: Option<String>,
    client_package: Option<String>,
    client_version: Option<String>,
    user_agent: Option<String>,
}

/// Open a legacy-kit recovery session from two matching kit shares.
#[wasm_bindgen]
pub async fn legacy_kit_open_recovery(
    input: JsValue,
) -> Result<LegacyKitRecoveryHandle, ContactsError> {
    let input: OpenLegacyKitRecoveryInput = swb::from_value(input)?;
    let client = LegacyKitRecoveryClient::new_with_headers(
        input.base_url,
        input.client_package,
        input.client_version,
        input.user_agent,
    )?;
    let handle = client
        .open_from_shares(&input.shares, input.email.as_deref())
        .await?;
    Ok(LegacyKitRecoveryHandle { inner: handle })
}

/// Handle to an opened legacy-kit recovery session.
#[wasm_bindgen]
pub struct LegacyKitRecoveryHandle {
    inner: ente_contacts::LegacyKitRecoveryHandle,
}

#[wasm_bindgen]
impl LegacyKitRecoveryHandle {
    /// Return the currently opened session.
    pub fn session(&self) -> Result<JsValue, ContactsError> {
        swb::to_value(self.inner.session()).map_err(Into::into)
    }

    /// Refresh the recovery session status.
    pub async fn refresh_session(&self) -> Result<JsValue, ContactsError> {
        let session = self.inner.refresh_session().await?;
        swb::to_value(&session).map_err(Into::into)
    }

    /// Complete password reset using this recovery session.
    pub async fn change_password(&self, new_password: String) -> Result<(), ContactsError> {
        self.inner
            .change_password(&new_password)
            .await
            .map_err(Into::into)
    }
}
