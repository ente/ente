//! Space entity keys.
//!
//! Entity keys are small wrapped keys the server stores per account under a
//! string type tag (for example the Space root key). These methods read and
//! write them through the generic `/user-entity/key` endpoints. Space callers
//! keep using a combined secretbox payload; this layer splits and joins the
//! nonce/header required by the generic API.

use super::AccountSpaceCtx;
use crate::error::{Result, SpaceError};
use crate::transport::{CreateEntityKeyRequest, EntityKeyPayload, EntityKeyResponse};
use ente_core::b64;

const SPACE_ENTITY_KEY_HEADER_BYTES: usize = 24;

impl AccountSpaceCtx {
    pub async fn get_entity_key(&self, key_type: &str) -> Result<Option<EntityKeyPayload>> {
        let query = vec![("type", key_type.to_owned())];
        let response = self
            .api()
            .get("/user-entity/key")
            .query(&query)
            .send()
            .await?;
        if response.status() == 404 {
            return Ok(None);
        }
        combine_entity_key_response(response.error_for_status()?.json().await?).map(Some)
    }

    pub async fn create_entity_key(
        &self,
        key_type: &str,
        payload: &EntityKeyPayload,
    ) -> Result<()> {
        let (header, encrypted_key) = split_entity_key_payload(payload)?;
        let request = CreateEntityKeyRequest {
            key_type: key_type.to_owned(),
            encrypted_key,
            header,
        };
        let response = self
            .api()
            .post("/user-entity/key")
            .json(&request)
            .send()
            .await?;
        if response.status() == 409 {
            return Err(SpaceError::EntityKeyConflict);
        }
        response.error_for_status()?;
        Ok(())
    }

    pub async fn ensure_entity_key(
        &self,
        key_type: &str,
        payload: &EntityKeyPayload,
    ) -> Result<EntityKeyPayload> {
        let (header, encrypted_key) = split_entity_key_payload(payload)?;
        let request = CreateEntityKeyRequest {
            key_type: key_type.to_owned(),
            encrypted_key,
            header,
        };
        let response = self
            .api()
            .post("/user-entity/key/ensure")
            .json(&request)
            .send()
            .await?
            .error_for_status()?
            .json::<EntityKeyResponse>()
            .await?;
        combine_entity_key_response(response)
    }
}

fn split_entity_key_payload(payload: &EntityKeyPayload) -> Result<(String, String)> {
    let combined = b64::decode(&payload.encrypted_key)?;
    if combined.len() <= SPACE_ENTITY_KEY_HEADER_BYTES {
        return Err(SpaceError::InvalidInput(
            "entity key payload is missing header".into(),
        ));
    }
    Ok((
        b64::encode(&combined[..SPACE_ENTITY_KEY_HEADER_BYTES]),
        b64::encode(&combined[SPACE_ENTITY_KEY_HEADER_BYTES..]),
    ))
}

fn combine_entity_key_response(response: EntityKeyResponse) -> Result<EntityKeyPayload> {
    let mut combined = b64::decode(&response.header)?;
    let encrypted_key = b64::decode(&response.encrypted_key)?;
    combined.extend_from_slice(&encrypted_key);
    Ok(EntityKeyPayload {
        encrypted_key: b64::encode(&combined),
    })
}
