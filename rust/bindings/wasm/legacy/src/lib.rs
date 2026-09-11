mod types;

use ente_core::b64;
use ente_legacy::LegacyKitRecoveryClient;
use ente_wasm_lib::session::Session;
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use types::{
    LegacyContactState, LegacyInfo, LegacyKitRecoverySession, LegacyKitShare, OpenKitRecoveryInput,
};
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Legacy(#[from] ente_legacy::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Legacy(ente_legacy::Error::DifferentLegacyKits) => Some("different_legacy_kits"),
            Self::Legacy(ente_legacy::Error::DuplicateLegacyKitShare) => {
                Some("duplicate_legacy_kit_share")
            }
            Self::Legacy(ente_legacy::Error::LegacyKitInactive) => Some("legacy_kit_inactive"),
            Self::Legacy(ente_legacy::Error::ContactNotOnEnte) => Some("contact_not_on_ente"),
            Self::Legacy(ente_legacy::Error::ActiveRecoverySession) => {
                Some("active_recovery_session")
            }
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

#[wasm_bindgen(js_name = legacyGetInfo)]
pub async fn legacy_get_info(session: &Session) -> Result<<LegacyInfo as Tsify>::JsType, Error> {
    LegacyInfo::from(ente_legacy::info(session.inner()).await?)
        .into_js()
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyPublicKey)]
pub async fn legacy_public_key(session: &Session, email: String) -> Result<Option<String>, Error> {
    ente_legacy::public_key(session.inner(), &email)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyVerificationID)]
pub fn legacy_verification_id(public_key_b64: String) -> Result<String, Error> {
    ente_legacy::verification_id(&public_key_b64).map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyAddContact)]
pub async fn legacy_add_contact(
    session: &Session,
    email: String,
    recovery_notice_in_days: Option<i32>,
) -> Result<(), Error> {
    ente_legacy::add_contact(session.inner(), &email, recovery_notice_in_days)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyUpdateContact)]
pub async fn legacy_update_contact(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
    state: <LegacyContactState as Tsify>::JsType,
) -> Result<(), Error> {
    let state = LegacyContactState::from_js(state)?;
    ente_legacy::update_contact(session.inner(), user_id, emergency_contact_id, state.into())
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyUpdateRecoveryNotice)]
pub async fn legacy_update_recovery_notice(
    session: &Session,
    emergency_contact_id: i64,
    recovery_notice_in_days: i32,
) -> Result<(), Error> {
    ente_legacy::update_recovery_notice(
        session.inner(),
        emergency_contact_id,
        recovery_notice_in_days,
    )
    .await
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyStartRecovery)]
pub async fn legacy_start_recovery(
    session: &Session,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), Error> {
    ente_legacy::start_recovery(session.inner(), user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyStopRecovery)]
pub async fn legacy_stop_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), Error> {
    ente_legacy::stop_recovery(session.inner(), &recovery_id, user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyRejectRecovery)]
pub async fn legacy_reject_recovery(
    session: &Session,
    recovery_id: String,
    user_id: i64,
    emergency_contact_id: i64,
) -> Result<(), Error> {
    ente_legacy::reject_recovery(session.inner(), &recovery_id, user_id, emergency_contact_id)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = legacyChangePassword)]
pub async fn legacy_change_password(
    session: &Session,
    recovery_id: String,
    new_password: String,
) -> Result<(), Error> {
    ente_legacy::change_password(session.inner(), &recovery_id, &new_password)
        .await
        .map_err(Into::into)
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
