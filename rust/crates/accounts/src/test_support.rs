use ente_core::b64;
use serde::{Deserialize, de::DeserializeOwned};
use sha2::{Digest, Sha256};
use srp::ServerG4096;
use uuid::Uuid;

use crate::{AccountsClient, AccountsClientConfig, KeyAttributes, auth::SrpAttributes};

#[derive(Default)]
pub(crate) struct SrpState {
    pub(crate) uploaded_key_attributes: Option<KeyAttributes>,
    pub(crate) remote_srp_attributes: Option<SrpAttributes>,
    pub(crate) pending_setup_id: Option<Uuid>,
    pub(crate) pending_client_proof: Option<Vec<u8>>,
    pub(crate) pending_server_proof: Option<Vec<u8>>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SetupSrpPayload {
    #[serde(rename = "srpUserID")]
    pub(crate) srp_user_id: String,
    #[serde(rename = "srpSalt")]
    pub(crate) srp_salt: String,
    #[serde(rename = "srpVerifier")]
    pub(crate) srp_verifier: String,
    #[serde(rename = "srpA")]
    pub(crate) srp_a: String,
}

pub(crate) fn parse_request_body<T>(request: &mockito::Request) -> T
where
    T: DeserializeOwned,
{
    serde_json::from_str(&request.utf8_lossy_body().unwrap()).unwrap()
}

pub(crate) fn make_client(origin: String) -> AccountsClient {
    AccountsClient::new(
        AccountsClientConfig::new("io.ente.photos")
            .with_origin(origin)
            .with_user_agent("ente-accounts-test"),
    )
    .unwrap()
}

pub(crate) fn srp_proofs(payload: &SetupSrpPayload) -> (Vec<u8>, Vec<u8>, Vec<u8>) {
    let srp_salt = b64::decode(&payload.srp_salt).unwrap();
    let srp_verifier = b64::decode(&payload.srp_verifier).unwrap();
    let srp_a = b64::decode(&payload.srp_a).unwrap();
    let server = ServerG4096::<Sha256>::new();
    let b_private = [0x33u8; 64];
    let srp_b = pad(&server.compute_public_ephemeral(&b_private, &srp_verifier));
    let verifier = server
        .process_reply(
            payload.srp_user_id.as_bytes(),
            &srp_salt,
            &b_private,
            &srp_verifier,
            &srp_a,
        )
        .unwrap();
    let srp_a = pad(&srp_a);
    let shared_secret = pad(verifier.key());

    let mut client_proof_hasher = Sha256::new();
    client_proof_hasher.update(&srp_a);
    client_proof_hasher.update(&srp_b);
    client_proof_hasher.update(&shared_secret);
    let client_proof = client_proof_hasher.finalize().to_vec();

    let server_key = Sha256::digest(&shared_secret);
    let mut server_proof_hasher = Sha256::new();
    server_proof_hasher.update(&srp_a);
    server_proof_hasher.update(&client_proof);
    server_proof_hasher.update(server_key);
    let server_proof = server_proof_hasher.finalize().to_vec();
    (srp_b, client_proof, server_proof)
}

fn pad(data: &[u8]) -> Vec<u8> {
    if data.len() >= 512 {
        return data.to_vec();
    }
    let mut padded = vec![0u8; 512 - data.len()];
    padded.extend_from_slice(data);
    padded
}
