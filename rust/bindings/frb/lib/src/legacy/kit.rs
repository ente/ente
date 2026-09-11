use super::types::{LegacyError, LegacyKit, LegacyKitCreateResult, LegacyKitShare};
use crate::session::Session;

pub async fn kits(session: &Session) -> Result<Vec<LegacyKit>, LegacyError> {
    ente_legacy::kits(session.as_ref())
        .await
        .map(|kits| kits.into_iter().map(Into::into).collect())
        .map_err(Into::into)
}

pub async fn create_kit(
    session: &Session,
    part_names: Vec<String>,
    notice_period_in_hours: i32,
) -> Result<LegacyKitCreateResult, LegacyError> {
    let part_names: [String; 3] = part_names.try_into().map_err(|_| LegacyError::Other {
        message: "legacy kit requires exactly three part names".into(),
    })?;
    ente_legacy::create_kit(session.as_ref(), part_names, notice_period_in_hours)
        .await?
        .try_into()
}

pub async fn download_kit_shares(
    session: &Session,
    kit_id: String,
) -> Result<Vec<LegacyKitShare>, LegacyError> {
    ente_legacy::download_kit_shares(session.as_ref(), &kit_id)
        .await?
        .into_iter()
        .map(TryInto::try_into)
        .collect()
}

pub async fn update_kit_recovery_notice(
    session: &Session,
    kit_id: String,
    notice_period_in_hours: i32,
) -> Result<(), LegacyError> {
    ente_legacy::update_kit_recovery_notice(session.as_ref(), &kit_id, notice_period_in_hours)
        .await
        .map_err(Into::into)
}

pub async fn block_kit_recovery(session: &Session, kit_id: String) -> Result<(), LegacyError> {
    ente_legacy::block_kit_recovery(session.as_ref(), &kit_id)
        .await
        .map_err(Into::into)
}

pub async fn delete_kit(session: &Session, kit_id: String) -> Result<(), LegacyError> {
    ente_legacy::delete_kit(session.as_ref(), &kit_id)
        .await
        .map_err(Into::into)
}
