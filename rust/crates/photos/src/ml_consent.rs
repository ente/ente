use ente_core::{Session, http};
use serde::Deserialize;

pub async fn granted(session: &Session) -> Result<bool, http::Error> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct FeatureFlags {
        face_search_enabled: Option<bool>,
    }
    let flags: FeatureFlags = http::retry(|| async {
        session
            .api
            .get("/remote-store/feature-flags")
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await
    })
    .await?;
    Ok(flags.face_search_enabled.unwrap_or_default())
}
