use ente_core::{Session, http};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;

use crate::{Error, Result};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Family {
    pub members: Vec<Member>,
    // The admin's plan, excluding bonuses; account details zero it once the plan expires.
    pub storage: i64,
    #[serde(default)]
    pub expiry_time: i64,
    pub admin_bonus: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Member {
    pub id: Uuid,
    pub email: String,
    pub status: MemberStatus,
    #[serde(default)]
    pub usage: i64,
    #[serde(default)]
    pub is_admin: bool,
    pub storage_limit: Option<i64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum MemberStatus {
    #[serde(rename = "SELF")]
    Admin,
    Accepted,
    Invited,
}

impl Family {
    pub fn usage(&self) -> i64 {
        self.members.iter().map(|member| member.usage).sum()
    }

    pub fn total_storage(&self) -> i64 {
        self.storage + self.admin_bonus
    }
}

pub async fn get(session: &Session) -> Result<Option<Family>> {
    match send(session.api.get("/family/members")).await {
        Ok(response) => Ok(Some(response.json().await?)),
        Err(error) if error.status_code() == Some(400) => Ok(None),
        Err(error) => Err(error.into()),
    }
}

pub async fn create(session: &Session) -> Result<()> {
    send(session.api.post("/family/create"))
        .await
        .map_err(|error| match error.status_code() {
            Some(400) => Error::InAnotherFamily,
            Some(402) => Error::PaidPlanRequired,
            _ => error.into(),
        })?;
    Ok(())
}

pub async fn invite(session: &Session, email: &str) -> Result<()> {
    send(
        session
            .api
            .post("/family/add-member")
            .json(&json!({"email": email})),
    )
    .await
    .map_err(|error| match error.status_code() {
        Some(400) => Error::NotFamilyAdmin,
        Some(402) => Error::PaidPlanRequired,
        Some(404) => Error::NotRegistered,
        Some(406) => Error::InviteeInFamily,
        Some(409) => Error::InviteeHasPaidPlan,
        Some(412) => Error::FamilyFull,
        _ => error.into(),
    })?;
    Ok(())
}

pub async fn remove_member(session: &Session, id: Uuid) -> Result<()> {
    send(session.api.delete(&format!("/family/remove-member/{id}")))
        .await
        .map_err(member_error)?;
    Ok(())
}

pub async fn revoke_invite(session: &Session, id: Uuid) -> Result<()> {
    send(session.api.delete(&format!("/family/revoke-invite/{id}")))
        .await
        .map_err(member_error)?;
    Ok(())
}

pub async fn set_storage_limit(session: &Session, id: Uuid, limit: Option<i64>) -> Result<()> {
    send(
        session
            .api
            .post("/family/modify-storage")
            .json(&json!({"id": id, "storageLimit": limit})),
    )
    .await
    .map_err(|error| match &error {
        http::Error::Api {
            status: 400,
            message: Some(message),
            ..
        } if message == "Failed to reduce storage" => Error::StorageLimitBelowUsage,
        _ if error.status_code() == Some(426) => Error::StorageLimitAboveFamilyStorage,
        _ => member_error(error),
    })?;
    Ok(())
}

pub async fn leave(session: &Session) -> Result<()> {
    send(session.api.delete("/family/leave"))
        .await
        .map_err(|error| match error.status_code() {
            Some(403) => Error::FamilyAdminCannotLeave,
            _ => error.into(),
        })?;
    Ok(())
}

fn member_error(error: http::Error) -> Error {
    match error.status_code() {
        Some(403) => Error::NotFamilyAdmin,
        Some(404) => Error::FamilyMemberNotFound,
        _ => error.into(),
    }
}

async fn send(
    request: http::RequestBuilder,
) -> std::result::Result<http::SuccessResponse, http::Error> {
    request.send().await?.error_for_code().await
}
