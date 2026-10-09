use super::AccountSpaceCtx;
use crate::error::Result;

impl AccountSpaceCtx {
    pub async fn send_poke(
        &self,
        sender_space_id: &str,
        space_id: &str,
        client_request_id: &str,
    ) -> Result<()> {
        let path = format!("/spaces/{sender_space_id}/friends/{space_id}/pokes");
        self.api()
            .post(&path)
            .json(&serde_json::json!({"clientRequestId": client_request_id}))
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }
}
