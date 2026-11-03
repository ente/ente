use ente_accounts::deletion;
use serde::Serialize;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use crate::session::{Error, Session};

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct AccountDeletionSummary {
    photos_and_videos_count: i64,
    authenticator_codes_count: i64,
    locker_records_count: i64,
}

#[wasm_bindgen(js_name = getAccountDeletionSummary)]
pub async fn get_account_deletion_summary(
    session: &Session,
) -> Result<Option<<AccountDeletionSummary as Tsify>::JsType>, Error> {
    deletion::get_deletion_summary(session.inner())
        .await?
        .map(|summary| {
            AccountDeletionSummary {
                photos_and_videos_count: summary.photos_and_videos_count,
                authenticator_codes_count: summary.authenticator_codes_count,
                locker_records_count: summary.locker_records_count,
            }
            .into_js()
        })
        .transpose()
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = getAccountDeleteChallenge)]
pub async fn get_account_delete_challenge(session: &Session) -> Result<String, Error> {
    Ok(deletion::get_delete_challenge(session.inner()).await?)
}

#[wasm_bindgen(js_name = deleteAccount)]
pub async fn delete_account(
    session: &Session,
    encrypted_challenge: &str,
    reason: &str,
    feedback: Option<String>,
) -> Result<(), Error> {
    deletion::delete_account(
        session.inner(),
        encrypted_challenge,
        reason,
        feedback.as_deref(),
    )
    .await
    .map_err(Into::into)
}
