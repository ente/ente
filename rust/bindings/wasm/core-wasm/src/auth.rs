use ente_accounts::auth;
use ente_core::b64;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Accounts(#[from] ente_accounts::Error),
}

impl Error {
    fn name(&self) -> Option<&'static str> {
        match self {
            Self::Accounts(ente_accounts::Error::InsufficientMemory) => Some("insufficient_memory"),
            _ => None,
        }
    }

    fn message(&self) -> String {
        ente_core::error::chain(self)
    }
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        let js_error = js_sys::Error::new(&error.message());
        if let Some(name) = error.name() {
            js_error.set_name(name);
        }
        js_error.into()
    }
}

#[wasm_bindgen]
pub struct GeneratedKek {
    key: String,
    salt: String,
    mem_limit: u32,
    ops_limit: u32,
}

#[wasm_bindgen]
impl GeneratedKek {
    #[wasm_bindgen(getter)]
    pub fn key(&self) -> String {
        self.key.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn salt(&self) -> String {
        self.salt.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn mem_limit(&self) -> u32 {
        self.mem_limit
    }

    #[wasm_bindgen(getter)]
    pub fn ops_limit(&self) -> u32 {
        self.ops_limit
    }
}

#[wasm_bindgen]
pub struct GeneratedSrpSetup {
    srp_salt: String,
    srp_verifier: String,
    login_sub_key: String,
}

#[wasm_bindgen]
impl GeneratedSrpSetup {
    #[wasm_bindgen(getter)]
    pub fn srp_salt(&self) -> String {
        self.srp_salt.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn srp_verifier(&self) -> String {
        self.srp_verifier.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn login_sub_key(&self) -> String {
        self.login_sub_key.clone()
    }
}

#[wasm_bindgen]
pub fn auth_derive_kek(
    password: &str,
    kek_salt_b64: &str,
    mem_limit: u32,
    ops_limit: u32,
) -> Result<String, Error> {
    let kek = auth::derive_kek(password, kek_salt_b64, mem_limit, ops_limit)?;
    Ok(b64::encode(&kek))
}

#[wasm_bindgen]
pub fn auth_generate_sensitive_kek(password: &str) -> Result<GeneratedKek, Error> {
    let generated = auth::generate_sensitive_kek(password)?;
    Ok(GeneratedKek {
        key: b64::encode(&generated.key),
        salt: b64::encode(&generated.salt),
        mem_limit: generated.mem_limit,
        ops_limit: generated.ops_limit,
    })
}

#[wasm_bindgen]
pub fn auth_generate_interactive_kek(password: &str) -> Result<GeneratedKek, Error> {
    let generated = auth::generate_interactive_kek(password)?;
    Ok(GeneratedKek {
        key: b64::encode(&generated.key),
        salt: b64::encode(&generated.salt),
        mem_limit: generated.mem_limit,
        ops_limit: generated.ops_limit,
    })
}

#[wasm_bindgen]
pub fn auth_generate_srp_setup(
    kek_b64: &str,
    srp_user_id: &str,
) -> Result<GeneratedSrpSetup, Error> {
    let kek =
        b64::decode(kek_b64).map_err(|e| ente_accounts::Error::Decode(format!("kek: {e}")))?;

    let generated = auth::generate_srp_setup(&kek, srp_user_id)?;
    Ok(GeneratedSrpSetup {
        srp_salt: b64::encode(&generated.srp_salt),
        srp_verifier: b64::encode(&generated.srp_verifier),
        login_sub_key: b64::encode(&generated.login_sub_key),
    })
}

#[wasm_bindgen]
pub fn auth_recovery_key_from_mnemonic_or_hex(input: &str) -> Result<String, Error> {
    let recovery_key = auth::recovery_key_from_mnemonic_or_hex(input)?;
    Ok(b64::encode(&recovery_key))
}

#[wasm_bindgen]
pub fn auth_recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String, Error> {
    auth::recovery_key_to_mnemonic(recovery_key_b64).map_err(Into::into)
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
    ) -> Result<SrpSession, Error> {
        let srp_salt = b64::decode(srp_salt_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srp_salt: {}", e)))?;
        let login_key = b64::decode(login_key_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("login_key: {}", e)))?;

        let inner = auth::SrpSession::new(srp_user_id, &srp_salt, &login_key)?;
        Ok(Self { inner })
    }

    pub fn public_a(&self) -> String {
        b64::encode(&self.inner.public_a())
    }

    pub fn compute_m1(&mut self, srp_b_b64: &str) -> Result<String, Error> {
        let srp_b = b64::decode(srp_b_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srpB: {}", e)))?;
        let m1 = self.inner.compute_m1(&srp_b)?;
        Ok(b64::encode(&m1))
    }

    pub fn verify_m2(&self, srp_m2_b64: &str) -> Result<(), Error> {
        let srp_m2 = b64::decode(srp_m2_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srpM2: {}", e)))?;
        self.inner.verify_m2(&srp_m2)?;
        Ok(())
    }
}
