#[derive(Clone, Debug)]
pub struct PreparedCastPayload {
    pub cast_token: String,
    pub encrypted_payload: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn prepare_cast_payload(
    public_key: String,
    pq_public_key: Option<String>,
    collection_id: i64,
    collection_key: String,
) -> Result<PreparedCastPayload, String> {
    let prepared = ente_cast::prepare_payload(
        &public_key,
        pq_public_key.as_deref(),
        collection_id,
        &collection_key,
    )
    .map_err(|error| error.to_string())?;
    Ok(PreparedCastPayload {
        cast_token: prepared.cast_token,
        encrypted_payload: prepared.encrypted_payload,
    })
}
