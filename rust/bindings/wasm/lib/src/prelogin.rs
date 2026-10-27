use crate::accounts::{Error as AccountsError, GeneratedKek};
use ente_accounts::auth;
use ente_core::{b64, crypto};
use serde::Serialize;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedSrpSetup {
    pub srp_salt: String,
    pub srp_verifier: String,
    pub login_sub_key: String,
}

#[wasm_bindgen(js_name = authDeriveKek)]
pub fn auth_derive_kek(
    password: &str,
    kek_salt_b64: &str,
    mem_limit: u64,
    ops_limit: u32,
) -> Result<String, AccountsError> {
    let kek = auth::derive_kek(password, kek_salt_b64, mem_limit, ops_limit)?;
    Ok(b64::encode(&kek))
}

#[wasm_bindgen(js_name = authDeriveSrpLoginKey)]
pub fn auth_derive_srp_login_key(kek_b64: &str) -> Result<String, AccountsError> {
    let kek =
        b64::decode(kek_b64).map_err(|e| ente_accounts::Error::Decode(format!("kek: {e}")))?;
    Ok(b64::encode(&auth::derive_srp_login_key(&kek)?))
}

#[wasm_bindgen(js_name = authGenerateSensitiveKek)]
pub fn auth_generate_sensitive_kek(
    password: &str,
) -> Result<<GeneratedKek as Tsify>::JsType, AccountsError> {
    GeneratedKek::from(auth::generate_sensitive_kek(password)?)
        .into_js()
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = authGenerateSrpSetup)]
pub fn auth_generate_srp_setup(
    kek_b64: &str,
    srp_user_id: &str,
) -> Result<<GeneratedSrpSetup as Tsify>::JsType, AccountsError> {
    let kek =
        b64::decode(kek_b64).map_err(|e| ente_accounts::Error::Decode(format!("kek: {e}")))?;
    let generated = auth::generate_srp_setup(&kek, srp_user_id)?;
    GeneratedSrpSetup {
        srp_salt: b64::encode(&generated.srp_salt),
        srp_verifier: b64::encode(&generated.srp_verifier),
        login_sub_key: b64::encode(&generated.login_sub_key),
    }
    .into_js()
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = authRecoveryKeyFromMnemonicOrHex)]
pub fn auth_recovery_key_from_mnemonic_or_hex(input: &str) -> Result<String, AccountsError> {
    let recovery_key = auth::recovery_key_from_mnemonic_or_hex(input)?;
    Ok(b64::encode(&recovery_key))
}

#[wasm_bindgen(js_name = authRecoveryKeyToMnemonic)]
pub fn auth_recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String, AccountsError> {
    let recovery_key = b64::decode(recovery_key_b64)
        .map_err(|e| ente_accounts::Error::Decode(format!("recovery_key: {e}")))?;
    auth::recovery_key_to_mnemonic(&recovery_key).map_err(Into::into)
}

#[wasm_bindgen]
pub struct SrpSession {
    inner: auth::SrpSession,
}

#[wasm_bindgen]
impl SrpSession {
    #[wasm_bindgen(constructor)]
    pub fn new(
        srp_user_id: &str,
        srp_salt_b64: &str,
        login_key_b64: &str,
    ) -> Result<SrpSession, AccountsError> {
        let srp_salt = b64::decode(srp_salt_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srp_salt: {e}")))?;
        let login_key = b64::decode(login_key_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("login_key: {e}")))?;
        let inner = auth::SrpSession::new(srp_user_id, &srp_salt, &login_key)?;
        Ok(Self { inner })
    }

    #[wasm_bindgen(js_name = publicA)]
    pub fn public_a(&self) -> String {
        b64::encode(&self.inner.public_a())
    }

    #[wasm_bindgen(js_name = computeM1)]
    pub fn compute_m1(&mut self, srp_b_b64: &str) -> Result<String, AccountsError> {
        let srp_b = b64::decode(srp_b_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srpB: {e}")))?;
        let m1 = self.inner.compute_m1(&srp_b)?;
        Ok(b64::encode(&m1))
    }

    #[wasm_bindgen(js_name = verifyM2)]
    pub fn verify_m2(&self, srp_m2_b64: &str) -> Result<(), AccountsError> {
        let srp_m2 = b64::decode(srp_m2_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srpM2: {e}")))?;
        self.inner.verify_m2(&srp_m2)?;
        Ok(())
    }
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct CryptoKeyPair {
    pub public_key: String,
    pub private_key: String,
}

#[wasm_bindgen(js_name = cryptoGenerateKeyPair)]
pub fn crypto_generate_key_pair() -> Result<<CryptoKeyPair as Tsify>::JsType, crate::crypto::Error>
{
    let secret_key = crypto::SecretKey::generate();
    CryptoKeyPair {
        public_key: b64::encode(secret_key.public_key().as_bytes()),
        private_key: b64::encode(secret_key.as_bytes()),
    }
    .into_js()
    .map_err(Into::into)
}
