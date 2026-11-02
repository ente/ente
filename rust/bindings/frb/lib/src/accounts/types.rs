use ente_accounts::{AccountsClient as InnerClient, Error, auth, lifecycle, login, signup};
pub use ente_accounts::{
    auth::KeyAttributes,
    models::{
        AuthResponse, TwoFactorAuthorizationResponse, TwoFactorRecoveryResponse, TwoFactorSecret,
        TwoFactorType,
    },
};
use ente_core::{b64, crypto::SecretVec};
use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub enum AccountsError {
    NotRegistered,
    AlreadyRegistered,
    SignupIncomplete,
    EmailAlreadyInUse,
    SrpNotConfigured,
    IncorrectPassword,
    IncorrectRecoveryKey,
    MalformedRecoveryKey,
    IncorrectEmailCode,
    EmailCodeExpired,
    EmailCodeRateLimited,
    IncorrectTotp,
    TotpRateLimited,
    SessionExpired,
    KeyDerivation,
    Network { timeout: bool },
    Other { message: String },
}

impl From<Error> for AccountsError {
    fn from(error: Error) -> Self {
        match error {
            Error::NotRegistered => Self::NotRegistered,
            Error::AlreadyRegistered => Self::AlreadyRegistered,
            Error::SignupIncomplete => Self::SignupIncomplete,
            Error::EmailAlreadyInUse => Self::EmailAlreadyInUse,
            Error::SrpNotConfigured => Self::SrpNotConfigured,
            Error::IncorrectPassword => Self::IncorrectPassword,
            Error::IncorrectRecoveryKey => Self::IncorrectRecoveryKey,
            Error::MalformedRecoveryKey => Self::MalformedRecoveryKey,
            Error::IncorrectEmailVerificationCode => Self::IncorrectEmailCode,
            Error::EmailVerificationCodeExpired => Self::EmailCodeExpired,
            Error::EmailVerificationRateLimited => Self::EmailCodeRateLimited,
            Error::IncorrectTotp => Self::IncorrectTotp,
            Error::TotpRateLimited => Self::TotpRateLimited,
            Error::SecondFactorSessionExpired => Self::SessionExpired,
            Error::InsufficientMemory
            | Error::Crypto(ente_core::crypto::Error::KeyDerivationFailed)
            | Error::Crypto(ente_core::crypto::Error::InvalidKeyDerivationParams(_)) => {
                Self::KeyDerivation
            }
            Error::Http(ref error) if error.is_connect() || error.is_timeout() => Self::Network {
                timeout: error.is_timeout(),
            },
            _ => Self::Other {
                message: ente_core::error::chain(&error),
            },
        }
    }
}

#[frb(non_opaque)]
pub struct AccountsClientConfig {
    pub origin: String,
    pub client_package: String,
    pub client_version: Option<String>,
    pub user_agent: Option<String>,
}

#[frb(opaque)]
pub struct AccountsClient(pub(crate) InnerClient);

impl AccountsClient {
    pub async fn send_otp(
        &self,
        email: String,
        purpose: String,
        mobile: bool,
    ) -> Result<(), AccountsError> {
        self.0
            .send_otp(&email, &purpose, mobile)
            .await
            .map_err(Into::into)
    }

    pub async fn verify_email(
        &self,
        email: String,
        code: String,
        source: Option<String>,
    ) -> Result<AuthResponse, AccountsError> {
        self.0
            .verify_email(&email, &code, source.as_deref())
            .await
            .map_err(Into::into)
    }

    pub async fn get_srp_attributes(&self, email: String) -> Result<SrpAttributes, AccountsError> {
        self.0
            .get_srp_attributes(&email)
            .await
            .map(SrpAttributes::from)
            .map_err(Into::into)
    }

    pub async fn login_with_password(
        &self,
        attributes: SrpAttributes,
        password: String,
    ) -> Result<PasswordLogin, AccountsError> {
        let (response, kek) = self
            .0
            .login_with_srp(&password, &attributes.try_into()?)
            .await?;
        Ok(PasswordLogin {
            response,
            key_encryption_key: kek.into_vec(),
        })
    }

    pub async fn verify_totp(
        &self,
        session_id: String,
        code: String,
    ) -> Result<AuthResponse, AccountsError> {
        self.0
            .verify_totp(&session_id, &code)
            .await
            .map_err(Into::into)
    }

    pub async fn poll_passkey(
        &self,
        session_id: String,
    ) -> Result<Option<AuthResponse>, AccountsError> {
        self.0
            .check_passkey_status(&session_id)
            .await
            .map_err(Into::into)
    }

    pub fn generate_signup_keys(
        &self,
        password: String,
        srp_user_id: String,
    ) -> Result<SignupKeys, AccountsError> {
        let (keys, srp) = signup::generate_keys(&password, &srp_user_id)?;
        Ok(SignupKeys {
            key_attributes: keys.key_attributes,
            master_key: keys.private_key_attributes.key.into_string(),
            secret_key: keys.private_key_attributes.secret_key.into_string(),
            recovery_key: keys.private_key_attributes.recovery_key.into_string(),
            srp: SrpSetup {
                srp_user_id,
                srp_salt: srp.srp_salt,
                srp_verifier: srp.srp_verifier,
                login_key: srp.login_sub_key.into_vec(),
            },
        })
    }

    pub async fn complete_signup(
        &self,
        email: String,
        token: String,
        key_attributes: KeyAttributes,
        srp: SrpSetup,
    ) -> Result<(), AccountsError> {
        let client = self.0.with_auth_token(token);
        let srp_user_id = srp
            .srp_user_id
            .parse()
            .map_err(|_| Error::InvalidInput("Invalid SRP user ID".into()))?;
        signup::complete_signup(
            &client,
            &email,
            &key_attributes,
            srp_user_id,
            &srp.into_core(),
        )
        .await
        .map(|_| ())
        .map_err(Into::into)
    }

    pub async fn setup_srp(
        &self,
        token: String,
        srp_user_id: String,
        login_key: Vec<u8>,
    ) -> Result<(), AccountsError> {
        let client = self.0.with_auth_token(token);
        let srp = auth::generate_srp_setup_with_login_key(&login_key, &srp_user_id)?;
        let srp_user_id = srp_user_id
            .parse()
            .map_err(|_| Error::InvalidInput("Invalid SRP user ID".into()))?;
        signup::setup_srp(&client, srp_user_id, &srp)
            .await
            .map_err(Into::into)
    }

    pub fn unlock(
        &self,
        response: AuthResponse,
        password: String,
        key_encryption_key: Option<Vec<u8>>,
    ) -> Result<UnlockedAccount, AccountsError> {
        let attributes = response
            .key_attributes
            .as_ref()
            .ok_or(Error::MissingKeyAttributes)?;
        let kek = match key_encryption_key {
            Some(key) => SecretVec::new(key),
            None => auth::derive_kek(
                &password,
                &attributes.kek_salt,
                attributes.mem_limit,
                attributes.ops_limit,
            )?,
        };
        let account = login::unlock(&response, &kek)?;
        Ok(UnlockedAccount {
            master_key: b64::encode(&account.secrets.master_key),
            secret_key: b64::encode(&account.secrets.secret_key),
            token: b64::encode_url_safe(&account.secrets.token),
            login_key: auth::derive_srp_login_key(&kek)?.into_vec(),
        })
    }

    pub fn recover_account(
        &self,
        response: AuthResponse,
        recovery_key: String,
    ) -> Result<RecoveredAccount, AccountsError> {
        let account = login::recover_account(&response, &recovery_key)?;
        Ok(RecoveredAccount {
            master_key: b64::encode(&account.secrets.master_key),
            secret_key: b64::encode(&account.secrets.secret_key),
            token: b64::encode_url_safe(&account.secrets.token),
        })
    }

    pub async fn change_password(
        &self,
        token: String,
        password: String,
        master_key: Vec<u8>,
        key_attributes: KeyAttributes,
        log_out_other_devices: bool,
    ) -> Result<KeyAttributes, AccountsError> {
        lifecycle::change_password(
            &self.0.with_auth_token(token),
            lifecycle::ChangePasswordParams {
                password: password.into(),
                master_key: SecretVec::new(master_key),
                key_attributes,
                log_out_other_devices,
            },
        )
        .await
        .map_err(Into::into)
    }

    pub async fn setup_two_factor(&self, token: String) -> Result<TwoFactorSecret, AccountsError> {
        self.0
            .with_auth_token(token)
            .setup_two_factor()
            .await
            .map_err(Into::into)
    }

    pub async fn enable_two_factor(
        &self,
        token: String,
        secret: String,
        recovery_key: String,
        code: String,
    ) -> Result<(), AccountsError> {
        lifecycle::enable_two_factor(
            &self.0.with_auth_token(token),
            &secret,
            &recovery_key,
            &code,
        )
        .await
        .map_err(Into::into)
    }

    pub async fn passkey_management_url(
        &self,
        token: String,
        recovery_key: String,
    ) -> Result<String, AccountsError> {
        lifecycle::passkey_management_url(&self.0.with_auth_token(token), &recovery_key)
            .await
            .map_err(Into::into)
    }

    pub async fn get_two_factor_recovery(
        &self,
        two_factor_type: TwoFactorType,
        session_id: String,
    ) -> Result<TwoFactorRecoveryResponse, AccountsError> {
        self.0
            .get_two_factor_recovery(&session_id, two_factor_type)
            .await
            .map_err(Into::into)
    }

    pub async fn recover_two_factor(
        &self,
        two_factor_type: TwoFactorType,
        session_id: String,
        recovery_response: TwoFactorRecoveryResponse,
        recovery_key: String,
    ) -> Result<TwoFactorAuthorizationResponse, AccountsError> {
        lifecycle::recover_two_factor(
            &self.0,
            two_factor_type,
            &session_id,
            &recovery_response,
            &recovery_key,
        )
        .await
        .map_err(Into::into)
    }
}

#[frb(non_opaque)]
pub struct SrpAttributes {
    pub srp_user_id: String,
    pub srp_salt: String,
    pub mem_limit: u64,
    pub ops_limit: u32,
    pub kek_salt: String,
    pub is_email_mfa_enabled: bool,
}

impl From<auth::SrpAttributes> for SrpAttributes {
    fn from(value: auth::SrpAttributes) -> Self {
        Self {
            srp_user_id: value.srp_user_id.to_string(),
            srp_salt: value.srp_salt,
            mem_limit: value.mem_limit,
            ops_limit: value.ops_limit,
            kek_salt: value.kek_salt,
            is_email_mfa_enabled: value.is_email_mfa_enabled,
        }
    }
}

impl TryFrom<SrpAttributes> for auth::SrpAttributes {
    type Error = ente_accounts::Error;

    fn try_from(value: SrpAttributes) -> Result<Self, Self::Error> {
        Ok(Self {
            srp_user_id: value
                .srp_user_id
                .parse()
                .map_err(|_| Error::InvalidInput("Invalid SRP user ID".into()))?,
            srp_salt: value.srp_salt,
            mem_limit: value.mem_limit,
            ops_limit: value.ops_limit,
            kek_salt: value.kek_salt,
            is_email_mfa_enabled: value.is_email_mfa_enabled,
        })
    }
}

#[frb(non_opaque)]
pub struct PasswordLogin {
    pub response: AuthResponse,
    pub key_encryption_key: Vec<u8>,
}

#[frb(non_opaque)]
pub struct SrpSetup {
    pub srp_user_id: String,
    pub srp_salt: Vec<u8>,
    pub srp_verifier: Vec<u8>,
    pub login_key: Vec<u8>,
}

impl SrpSetup {
    fn into_core(self) -> auth::GeneratedSrpSetup {
        auth::GeneratedSrpSetup {
            srp_salt: self.srp_salt,
            srp_verifier: self.srp_verifier,
            login_sub_key: SecretVec::new(self.login_key),
        }
    }
}

#[frb(non_opaque)]
pub struct SignupKeys {
    pub key_attributes: KeyAttributes,
    pub master_key: String,
    pub secret_key: String,
    pub recovery_key: String,
    pub srp: SrpSetup,
}

#[frb(non_opaque)]
pub struct UnlockedAccount {
    pub master_key: String,
    pub secret_key: String,
    pub token: String,
    pub login_key: Vec<u8>,
}

#[frb(mirror(AuthResponse))]
pub struct _AuthResponse {
    pub id: i64,
    pub key_attributes: Option<KeyAttributes>,
    pub encrypted_token: Option<String>,
    pub token: Option<String>,
    pub two_factor_session_id: Option<String>,
    pub two_factor_session_id_v2: Option<String>,
    pub passkey_session_id: Option<String>,
    pub srp_m2: Option<String>,
    pub accounts_url: Option<String>,
}

#[frb(mirror(TwoFactorType))]
pub enum _TwoFactorType {
    Totp,
    Passkey,
}

#[frb(mirror(TwoFactorRecoveryResponse))]
pub struct _TwoFactorRecoveryResponse {
    pub encrypted_secret: String,
    pub secret_decryption_nonce: String,
}

#[frb(mirror(TwoFactorAuthorizationResponse))]
pub struct _TwoFactorAuthorizationResponse {
    pub id: i64,
    pub key_attributes: KeyAttributes,
    pub encrypted_token: String,
}

#[frb(mirror(KeyAttributes))]
pub struct _KeyAttributes {
    pub kek_salt: String,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub public_key: String,
    pub encrypted_secret_key: String,
    pub secret_key_decryption_nonce: String,
    pub mem_limit: u64,
    pub ops_limit: u32,
    pub master_key_encrypted_with_recovery_key: Option<String>,
    pub master_key_decryption_nonce: Option<String>,
    pub recovery_key_encrypted_with_master_key: Option<String>,
    pub recovery_key_decryption_nonce: Option<String>,
}

#[frb(non_opaque)]
pub struct RecoveredAccount {
    pub master_key: String,
    pub secret_key: String,
    pub token: String,
}

#[frb(mirror(TwoFactorSecret))]
pub struct _TwoFactorSecret {
    pub secret_code: String,
    pub qr_code: String,
}
