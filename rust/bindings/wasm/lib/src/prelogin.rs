use crate::accounts::Error as AccountsError;
use ente_accounts::{auth, signup};
use ente_core::b64;
use serde::Serialize;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedSignupKeys {
    master_key: String,
    #[tsify(type = "unknown")]
    key_attributes: auth::KeyAttributes,
    srp: GeneratedSrpSetup,
}

#[wasm_bindgen(js_name = authGenerateSignupKeys)]
pub fn auth_generate_signup_keys(
    password: &str,
    srp_user_id: &str,
) -> Result<<GeneratedSignupKeys as Tsify>::JsType, AccountsError> {
    let (keys, srp) = signup::generate_keys(password, srp_user_id)?;
    GeneratedSignupKeys {
        master_key: keys.private_key_attributes.key.to_string(),
        key_attributes: keys.key_attributes,
        srp: GeneratedSrpSetup::new(srp_user_id, srp),
    }
    .into_js()
    .map_err(Into::into)
}

#[wasm_bindgen(js_name = authGenerateInteractiveKeyAttributes, unchecked_return_type = "unknown")]
pub fn auth_generate_interactive_key_attributes(
    password: &str,
    #[wasm_bindgen(unchecked_param_type = "unknown")] attributes: JsValue,
    master_key: &str,
) -> Result<JsValue, AccountsError> {
    let master_key =
        b64::decode(master_key).map_err(|error| ente_accounts::Error::Decode(error.to_string()))?;
    let (attributes, _) = auth::generate_key_attributes_for_new_password_with_strength(
        &master_key,
        &serde_wasm_bindgen::from_value(attributes)?,
        password,
        auth::KeyDerivationStrength::Interactive,
    )?;
    serde_wasm_bindgen::to_value(&attributes).map_err(Into::into)
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedSrpSetup {
    #[serde(rename = "srpUserID")]
    pub srp_user_id: String,
    pub srp_salt: String,
    pub srp_verifier: String,
    pub login_sub_key: String,
}

impl GeneratedSrpSetup {
    fn new(srp_user_id: &str, generated: auth::GeneratedSrpSetup) -> Self {
        Self {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: b64::encode(&generated.srp_salt),
            srp_verifier: b64::encode(&generated.srp_verifier),
            login_sub_key: b64::encode(&generated.login_sub_key),
        }
    }
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

#[wasm_bindgen(js_name = authGenerateSrpSetup)]
pub fn auth_generate_srp_setup(
    kek_b64: &str,
    srp_user_id: &str,
) -> Result<<GeneratedSrpSetup as Tsify>::JsType, AccountsError> {
    let kek =
        b64::decode(kek_b64).map_err(|e| ente_accounts::Error::Decode(format!("kek: {e}")))?;
    let generated = auth::generate_srp_setup(&kek, srp_user_id)?;
    GeneratedSrpSetup::new(srp_user_id, generated)
        .into_js()
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = authRecoveryKeyToMnemonic)]
pub fn auth_recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String, AccountsError> {
    let recovery_key = b64::decode(recovery_key_b64)
        .map_err(|e| ente_accounts::Error::Decode(format!("recovery_key: {e}")))?;
    auth::recovery_key_to_mnemonic(&recovery_key).map_err(Into::into)
}
