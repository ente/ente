use ente_accounts::auth;
use ente_core::b64;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct AccountsError {
    code: String,
    message: String,
}

#[wasm_bindgen]
impl AccountsError {
    #[wasm_bindgen(getter)]
    pub fn code(&self) -> String {
        self.code.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn message(&self) -> String {
        self.message.clone()
    }
}

impl From<ente_accounts::Error> for AccountsError {
    fn from(e: ente_accounts::Error) -> Self {
        use ente_accounts::Error as E;

        let code = match &e {
            E::Http(_) => "http",
            E::Serialization(_) => "serialization",
            E::Crypto(_) => "crypto",
            E::Decode(_) => "decode",
            E::IncorrectPassword => "incorrect_password",
            E::IncorrectRecoveryKey => "incorrect_recovery_key",
            E::InvalidKeyAttributes => "invalid_key_attributes",
            E::InsufficientMemory => "insufficient_memory",
            E::MissingField(_) => "missing_field",
            E::InvalidKey(_) => "invalid_key",
            E::Srp(_) => "srp",
            E::InvalidInput(_) => "invalid_input",
            E::IncorrectEmailVerificationCode => "incorrect_email_verification_code",
            E::EmailVerificationCodeExpired => "email_verification_code_expired",
            E::EmailVerificationRateLimited => "email_verification_rate_limited",
            E::IncorrectTotp => "incorrect_totp",
            E::TotpRateLimited => "totp_rate_limited",
            E::SecondFactorSessionExpired => "second_factor_session_expired",
            E::SessionInvalid => "session_invalid",
            E::MissingKeyAttributes => "missing_key_attributes",
            E::AccountAlreadyExists => "account_already_exists",
            E::Protocol(_) => "protocol",
            E::Ui(_) => "ui",
        }
        .to_string();

        Self {
            code,
            message: ente_core::error::chain(&e),
        }
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
) -> Result<String, AccountsError> {
    let kek = auth::derive_kek(password, kek_salt_b64, mem_limit, ops_limit)?;
    Ok(b64::encode(&kek))
}

#[wasm_bindgen]
pub fn auth_generate_sensitive_kek(password: &str) -> Result<GeneratedKek, AccountsError> {
    let generated = auth::generate_sensitive_kek(password)?;
    Ok(GeneratedKek {
        key: b64::encode(&generated.key),
        salt: b64::encode(&generated.salt),
        mem_limit: generated.mem_limit,
        ops_limit: generated.ops_limit,
    })
}

#[wasm_bindgen]
pub fn auth_generate_interactive_kek(password: &str) -> Result<GeneratedKek, AccountsError> {
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
) -> Result<GeneratedSrpSetup, AccountsError> {
    let kek = b64::decode(kek_b64).map_err(|e| AccountsError {
        code: "decode".to_string(),
        message: format!("kek: {}", e),
    })?;

    let generated = auth::generate_srp_setup(&kek, srp_user_id)?;
    Ok(GeneratedSrpSetup {
        srp_salt: b64::encode(&generated.srp_salt),
        srp_verifier: b64::encode(&generated.srp_verifier),
        login_sub_key: b64::encode(&generated.login_sub_key),
    })
}

#[wasm_bindgen]
pub fn auth_recovery_key_from_mnemonic_or_hex(input: &str) -> Result<String, AccountsError> {
    let recovery_key = auth::recovery_key_from_mnemonic_or_hex(input)?;
    Ok(b64::encode(&recovery_key))
}

#[wasm_bindgen]
pub fn auth_recovery_key_to_mnemonic(recovery_key_b64: &str) -> Result<String, AccountsError> {
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
    ) -> Result<SrpSession, AccountsError> {
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

    pub fn compute_m1(&mut self, srp_b_b64: &str) -> Result<String, AccountsError> {
        let srp_b = b64::decode(srp_b_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srpB: {}", e)))?;
        let m1 = self.inner.compute_m1(&srp_b)?;
        Ok(b64::encode(&m1))
    }

    pub fn verify_m2(&self, srp_m2_b64: &str) -> Result<(), AccountsError> {
        let srp_m2 = b64::decode(srp_m2_b64)
            .map_err(|e| ente_accounts::Error::Decode(format!("srpM2: {}", e)))?;
        self.inner.verify_m2(&srp_m2)?;
        Ok(())
    }
}
