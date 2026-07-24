//! Shared account flow orchestration built on [`crate::client::AccountsClient`].
//!
//! This layer is intended for interactive CLI/e2e flows. Callers that need
//! raw server `code/message/status` should prefer [`crate::client::AccountsClient`].

use base64::{
    Engine,
    engine::general_purpose::{STANDARD, URL_SAFE},
};
use ente_core::crypto::{self, SecretVec, secretbox};
use std::fmt;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::{
    auth::{
        self, DecryptedSecrets, GeneratedSrpSetup, KeyDerivationStrength, derive_kek,
        generate_keys_with_strength, generate_srp_setup_with_login_key, get_recovery_key,
    },
    client::AccountsClient,
    error::{Error, Result},
    models::{
        AuthResponse, ConfigurePasskeyRecoveryRequest, EnableTwoFactorRequest, KeyAttributes,
        RemoveTwoFactorRequest, SetRecoveryKeyRequest, SetupSrpRequest, SrpAttributes,
        TwoFactorAuthorizationResponse, TwoFactorRecoveryResponse, TwoFactorType,
        UpdateSrpAndKeysRequest, UpdatedKeyAttr,
    },
    types::AccountSecrets,
};

const SRP_A_LEN: usize = 512;

/// Purpose of an OTP prompt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OtpPurpose {
    /// OTP for login/email MFA.
    Login,
    /// OTP for signup.
    Signup,
}

impl OtpPurpose {
    fn as_api_purpose(self) -> &'static str {
        match self {
            OtpPurpose::Login => "login",
            OtpPurpose::Signup => "signup",
        }
    }
}

/// Purpose of a TOTP prompt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TotpPurpose {
    /// TOTP during login.
    Login,
    /// TOTP during initial setup.
    Setup,
}

/// Supported second-factor methods during login.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecondFactorMethod {
    /// TOTP auth app code.
    Totp,
    /// Passkey verification.
    Passkey,
}

/// UI adapter for interactive account flows.
pub trait AuthFlowUi {
    /// Read an email OTP from the user.
    fn read_email_otp(&mut self, email: &str, purpose: OtpPurpose, resent: bool) -> Result<String>;
    /// Read a TOTP code from the user.
    fn read_totp_code(&mut self, purpose: TotpPurpose) -> Result<String>;
    /// Display a retryable error and continue.
    fn report_retryable_error(&mut self, message: &str) -> Result<()>;
    /// Let the user choose a second-factor method.
    fn choose_second_factor(
        &mut self,
        methods: &[SecondFactorMethod],
    ) -> Result<SecondFactorMethod>;
    /// Show a passkey verification URL.
    fn present_passkey_verification(&mut self, url: &str) -> Result<()>;
    /// Wait until the user has attempted passkey verification.
    fn wait_for_passkey_verification(&mut self) -> Result<()>;
    /// Present a TOTP secret to the user.
    fn present_totp_secret(&mut self, secret_code: &str, qr_code: &str) -> Result<()>;
}

/// Parameters for account creation.
pub struct CreateAccountParams {
    /// Email address to register.
    pub email: String,
    /// Password used for signup.
    pub password: Zeroizing<String>,
    /// Optional referral source.
    pub source: Option<String>,
}

impl fmt::Debug for CreateAccountParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CreateAccountParams")
            .field("email", &self.email)
            .field("password", &"[REDACTED]")
            .field("source", &self.source)
            .finish()
    }
}

/// Parameters for login.
pub struct LoginParams {
    /// Email address to login.
    pub email: String,
    /// Password for the account.
    pub password: Zeroizing<String>,
}

impl fmt::Debug for LoginParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LoginParams")
            .field("email", &self.email)
            .field("password", &"[REDACTED]")
            .finish()
    }
}

/// Parameters for TOTP setup.
pub struct SetupTwoFactorParams {
    /// Master key for the account.
    pub master_key: SecretVec,
    /// Optional cached key attributes.
    pub key_attributes: Option<KeyAttributes>,
}

impl fmt::Debug for SetupTwoFactorParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SetupTwoFactorParams")
            .field("master_key", &"[REDACTED]")
            .field("key_attributes", &self.key_attributes)
            .finish()
    }
}

/// Parameters for password changes.
pub struct ChangePasswordParams {
    /// Email address of the account.
    pub email: String,
    /// New password.
    pub password: Zeroizing<String>,
    /// Current master key bytes.
    pub master_key: SecretVec,
    /// Current key attributes.
    pub key_attributes: KeyAttributes,
    /// Whether to logout other devices.
    pub log_out_other_devices: bool,
}

impl fmt::Debug for ChangePasswordParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChangePasswordParams")
            .field("email", &self.email)
            .field("password", &"[REDACTED]")
            .field("master_key", &"[REDACTED]")
            .field("key_attributes", &self.key_attributes)
            .field("log_out_other_devices", &self.log_out_other_devices)
            .finish()
    }
}

/// Result of a password-change flow.
pub struct ChangePasswordResult {
    /// Updated key attributes.
    pub key_attributes: KeyAttributes,
    /// Fresh SRP attributes fetched from remote.
    pub srp_attributes: SrpAttributes,
}

impl fmt::Debug for ChangePasswordResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChangePasswordResult")
            .field("key_attributes", &self.key_attributes)
            .field("srp_attributes", &self.srp_attributes)
            .finish()
    }
}

/// Parameters for session-validity checks.
pub struct CheckSessionValidityParams {
    /// Email address used to fetch fresh SRP attributes.
    pub email: String,
    /// Locally saved SRP attributes.
    pub local_srp_attributes: SrpAttributes,
}

impl fmt::Debug for CheckSessionValidityParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CheckSessionValidityParams")
            .field("email", &self.email)
            .field("local_srp_attributes", &self.local_srp_attributes)
            .finish()
    }
}

/// Outcome of a session-validity check.
#[derive(Debug)]
#[expect(clippy::large_enum_variant)]
pub enum SessionValidity {
    /// Token is invalid.
    Invalid,
    /// Session is valid and password unchanged.
    Valid,
    /// Session is valid but password was changed elsewhere.
    ValidButPasswordChanged {
        /// Fresh key attributes from remote.
        updated_key_attributes: KeyAttributes,
        /// Fresh SRP attributes from remote.
        updated_srp_attributes: SrpAttributes,
    },
}

/// Authenticated account returned by shared flows.
pub struct AuthenticatedAccount {
    /// User ID.
    pub user_id: i64,
    /// Full key attributes.
    pub key_attributes: KeyAttributes,
    /// Decrypted account secrets.
    pub secrets: AccountSecrets,
    /// Recovery key, if derivable.
    pub recovery_key: Option<String>,
}

impl fmt::Debug for AuthenticatedAccount {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AuthenticatedAccount")
            .field("user_id", &self.user_id)
            .field("key_attributes", &self.key_attributes)
            .field("secrets", &self.secrets)
            .field("recovery_key", &"[REDACTED]")
            .finish()
    }
}

/// Result of setting up TOTP.
pub struct SetupTwoFactorResult {
    /// Secret code shown to the user.
    pub secret_code: String,
    /// QR code payload.
    pub qr_code: String,
    /// Recovery key used to encrypt the TOTP secret.
    pub recovery_key: String,
}

impl fmt::Debug for SetupTwoFactorResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SetupTwoFactorResult")
            .field("secret_code", &"[REDACTED]")
            .field("qr_code", &"[REDACTED]")
            .field("recovery_key", &"[REDACTED]")
            .finish()
    }
}

/// Result of creating a new recovery key for old accounts.
pub struct RecoveryKeyResult {
    /// Fresh recovery key in hex.
    pub recovery_key: String,
    /// Updated key attributes including recovery-key fields.
    pub key_attributes: KeyAttributes,
}

impl fmt::Debug for RecoveryKeyResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RecoveryKeyResult")
            .field("recovery_key", &"[REDACTED]")
            .field("key_attributes", &self.key_attributes)
            .finish()
    }
}

/// Shared high-level account flow orchestration.
pub struct AuthFlow<'a, U> {
    client: &'a AccountsClient,
    ui: &'a mut U,
}

impl<'a, U> AuthFlow<'a, U>
where
    U: AuthFlowUi,
{
    /// Create a new shared account flow instance.
    pub fn new(client: &'a AccountsClient, ui: &'a mut U) -> Self {
        Self { client, ui }
    }

    /// Create a new account.
    pub async fn create_account(
        &mut self,
        params: CreateAccountParams,
    ) -> Result<AuthenticatedAccount> {
        self.create_account_with_strength(params, KeyDerivationStrength::Sensitive)
            .await
    }

    /// Create a new account after the caller has already sent and collected a signup OTP.
    pub async fn create_account_with_otp(
        &mut self,
        params: CreateAccountParams,
        otp: &str,
    ) -> Result<AuthenticatedAccount> {
        let email = params.email;
        let password = params.password;
        let verification = self
            .client
            .verify_email(&email, otp, params.source.as_deref())
            .await?;

        self.finish_verified_signup(
            email,
            password,
            verification,
            KeyDerivationStrength::Sensitive,
        )
        .await
    }

    /// Login to an existing account.
    pub async fn login(&mut self, params: LoginParams) -> Result<AuthenticatedAccount> {
        let srp_attrs = self.client.get_srp_attributes(&params.email).await?;

        let (auth_response, kek) = if srp_attrs.is_email_mfa_enabled {
            self.client
                .send_otp(&params.email, OtpPurpose::Login.as_api_purpose())
                .await?;
            let response = self
                .verify_email_otp(&params.email, OtpPurpose::Login, None)
                .await?;
            let response = self.resolve_second_factor(response).await?;
            let kek = derive_kek(
                &params.password,
                &srp_attrs.kek_salt,
                srp_attrs.mem_limit,
                srp_attrs.ops_limit,
            )?;
            (response, kek)
        } else {
            let (response, kek) = self
                .client
                .login_with_srp(&params.email, &params.password)
                .await?;
            let response = self.resolve_second_factor(response).await?;
            (response, kek)
        };

        self.build_authenticated_account(auth_response, &kek)
    }

    /// Setup TOTP two-factor authentication.
    pub async fn setup_two_factor(
        &mut self,
        params: SetupTwoFactorParams,
    ) -> Result<SetupTwoFactorResult> {
        let key_attributes = if let Some(key_attributes) = params.key_attributes {
            key_attributes
        } else {
            self.client
                .get_session_validity()
                .await?
                .key_attributes
                .ok_or_else(|| {
                    Error::AuthenticationFailed(
                        "Account keys are not available for two-factor setup".into(),
                    )
                })?
        };

        let recovery_key =
            get_recovery_key(&params.master_key, &key_attributes).map_err(Error::from)?;

        let secret = self.client.setup_two_factor().await?;
        self.ui
            .present_totp_secret(&secret.secret_code, &secret.qr_code)?;

        loop {
            let code = self.ui.read_totp_code(TotpPurpose::Setup)?;
            let request = encrypt_two_factor_secret(&secret.secret_code, &recovery_key, &code)?;
            match self.client.enable_two_factor(&request).await {
                Ok(()) => {
                    return Ok(SetupTwoFactorResult {
                        secret_code: secret.secret_code,
                        qr_code: secret.qr_code,
                        recovery_key,
                    });
                }
                Err(error) if error.is_http_status(&[400, 401]) => {
                    self.ui.report_retryable_error(
                        "Incorrect TOTP code. Enter the current code from your authenticator app and try again.",
                    )?;
                }
                Err(error) => return Err(error),
            }
        }
    }

    /// Change the account password and update SRP/key attributes on remote.
    pub async fn change_password(
        &self,
        params: ChangePasswordParams,
    ) -> Result<ChangePasswordResult> {
        self.change_password_with_strength(params, KeyDerivationStrength::Sensitive)
            .await
    }

    async fn change_password_with_strength(
        &self,
        params: ChangePasswordParams,
        key_derivation_strength: KeyDerivationStrength,
    ) -> Result<ChangePasswordResult> {
        let (updated_key_attributes, login_key) =
            auth::generate_key_attributes_for_new_password_with_strength(
                &params.master_key,
                &params.key_attributes,
                &params.password,
                key_derivation_strength,
            )?;

        let updated_key_attr = UpdatedKeyAttr::from(&updated_key_attributes);

        let srp_user_id = Uuid::new_v4();
        let srp_setup = generate_srp_setup_with_login_key(&login_key, &srp_user_id.to_string())?;
        self.complete_srp_update(
            &srp_user_id,
            &srp_setup,
            &updated_key_attr,
            params.log_out_other_devices,
        )
        .await?;

        let srp_attributes = self.client.get_srp_attributes(&params.email).await?;

        let expected_salt = STANDARD.encode(&srp_setup.srp_salt);
        let mut mismatches = Vec::new();
        if srp_attributes.srp_user_id != srp_user_id {
            mismatches.push("srpUserID");
        }
        if srp_attributes.srp_salt != expected_salt {
            mismatches.push("srpSalt");
        }
        if srp_attributes.kek_salt != updated_key_attributes.kek_salt {
            mismatches.push("kekSalt");
        }
        if srp_attributes.mem_limit != updated_key_attributes.mem_limit {
            mismatches.push("memLimit");
        }
        if srp_attributes.ops_limit != updated_key_attributes.ops_limit {
            mismatches.push("opsLimit");
        }
        if !mismatches.is_empty() {
            return Err(Error::AuthenticationFailed(format!(
                "Remote SRP attributes mismatched after password change: {}",
                mismatches.join(", ")
            )));
        }

        Ok(ChangePasswordResult {
            key_attributes: updated_key_attributes,
            srp_attributes,
        })
    }

    /// Check if the current session is still valid and whether password changed elsewhere.
    pub async fn check_session_validity(
        &self,
        params: CheckSessionValidityParams,
    ) -> Result<SessionValidity> {
        let remote = match self.client.get_session_validity().await {
            Ok(remote) => remote,
            Err(error) if error.is_http_status(&[401]) => return Ok(SessionValidity::Invalid),
            Err(error) => return Err(error),
        };

        if let Some(remote_key_attributes) = remote.key_attributes {
            let remote_srp_attributes = self.client.get_srp_attributes(&params.email).await?;
            if remote_srp_attributes.kek_salt != params.local_srp_attributes.kek_salt {
                return Ok(SessionValidity::ValidButPasswordChanged {
                    updated_key_attributes: remote_key_attributes,
                    updated_srp_attributes: remote_srp_attributes,
                });
            }
        }

        Ok(SessionValidity::Valid)
    }

    /// Change the authenticated user's email address.
    pub async fn change_email(&self, email: &str, ott: &str) -> Result<()> {
        self.client.change_email(email, ott).await
    }

    /// Create a new recovery key for old accounts that do not have one yet.
    pub async fn create_recovery_key(
        &self,
        master_key: &[u8],
        existing_attributes: &KeyAttributes,
    ) -> Result<RecoveryKeyResult> {
        let (
            recovery_key,
            master_key_encrypted_with_recovery_key,
            master_key_decryption_nonce,
            recovery_key_encrypted_with_master_key,
            recovery_key_decryption_nonce,
        ) = auth::create_new_recovery_key(master_key)?;

        let request = SetRecoveryKeyRequest {
            master_key_encrypted_with_recovery_key: master_key_encrypted_with_recovery_key.clone(),
            master_key_decryption_nonce: master_key_decryption_nonce.clone(),
            recovery_key_encrypted_with_master_key: recovery_key_encrypted_with_master_key.clone(),
            recovery_key_decryption_nonce: recovery_key_decryption_nonce.clone(),
        };
        self.client.set_recovery_key_attributes(request).await?;

        let key_attributes = KeyAttributes {
            master_key_encrypted_with_recovery_key: Some(master_key_encrypted_with_recovery_key),
            master_key_decryption_nonce: Some(master_key_decryption_nonce),
            recovery_key_encrypted_with_master_key: Some(recovery_key_encrypted_with_master_key),
            recovery_key_decryption_nonce: Some(recovery_key_decryption_nonce),
            ..existing_attributes.clone()
        };

        Ok(RecoveryKeyResult {
            recovery_key,
            key_attributes,
        })
    }

    /// Get the server-side two-factor recovery payload for a pending second-factor session.
    pub async fn get_two_factor_recovery(
        &self,
        session_id: &str,
        two_factor_type: TwoFactorType,
    ) -> Result<TwoFactorRecoveryResponse> {
        self.client
            .get_two_factor_recovery(session_id, two_factor_type)
            .await
    }

    /// Remove/bypass the second factor using a recovery key input.
    pub async fn recover_two_factor(
        &self,
        two_factor_type: TwoFactorType,
        session_id: &str,
        recovery_response: &TwoFactorRecoveryResponse,
        recovery_key_mnemonic_or_hex: &str,
    ) -> Result<TwoFactorAuthorizationResponse> {
        let recovery_key = auth::recovery_key_from_mnemonic_or_hex(recovery_key_mnemonic_or_hex)?;
        let encrypted_secret = crypto::decode_b64(&recovery_response.encrypted_secret)?;
        let nonce = crypto::decode_b64(&recovery_response.secret_decryption_nonce)?;
        let secret = secretbox::decrypt(
            &encrypted_secret,
            &crypto::Nonce::try_from_slice(&nonce)?,
            &crypto::Key::try_from_slice(&recovery_key)?,
        )
        .map_err(|_| Error::AuthenticationFailed("Incorrect recovery key".into()))?;
        let request = RemoveTwoFactorRequest {
            session_id: session_id.to_string(),
            secret: String::from_utf8(secret)
                .map_err(|e| Error::Crypto(format!("invalid recovery secret: {e}")))?,
            two_factor_type,
        };
        self.client.remove_two_factor(&request).await
    }

    /// Return whether the authenticated user has TOTP enabled.
    pub async fn get_two_factor_status(&self) -> Result<bool> {
        self.client.get_two_factor_status().await
    }

    /// Disable TOTP for the authenticated user.
    pub async fn disable_two_factor(&self) -> Result<()> {
        self.client.disable_two_factor().await
    }

    /// Get passkey recovery status.
    pub async fn get_passkey_recovery_status(&self) -> Result<bool> {
        Ok(self
            .client
            .get_two_factor_recovery_status()
            .await?
            .is_passkey_recovery_enabled)
    }

    /// Configure passkey recovery by encrypting a reset secret with the user's recovery key.
    pub async fn configure_passkey_recovery(
        &self,
        secret: &str,
        recovery_key_mnemonic_or_hex: &str,
    ) -> Result<()> {
        let recovery_key = auth::recovery_key_from_mnemonic_or_hex(recovery_key_mnemonic_or_hex)?;
        let encrypted = secretbox::encrypt(
            secret.as_bytes(),
            &crypto::Key::try_from_slice(&recovery_key)?,
        );
        let request = ConfigurePasskeyRecoveryRequest {
            secret: secret.to_string(),
            user_secret_cipher: crypto::encode_b64(&encrypted.encrypted_data),
            user_secret_nonce: crypto::encode_b64(encrypted.nonce.as_bytes()),
        };
        self.client.configure_passkey_recovery(&request).await
    }

    /// Get the accounts-token response used to open the accounts broker.
    pub async fn get_accounts_token(&self) -> Result<crate::models::AccountsTokenResponse> {
        self.client.get_accounts_token().await
    }

    /// Poll passkey verification status.
    pub async fn check_passkey_status(&self, session_id: &str) -> Result<AuthResponse> {
        self.client.check_passkey_status(session_id).await
    }

    fn build_authenticated_account(
        &self,
        auth_response: AuthResponse,
        kek: &[u8],
    ) -> Result<AuthenticatedAccount> {
        let key_attributes = auth_response
            .key_attributes
            .clone()
            .ok_or_else(|| Error::AuthenticationFailed("No key attributes".into()))?;
        let secrets = decrypt_auth_response(&auth_response, &key_attributes, kek)?;
        let public_key = crypto::decode_b64(&key_attributes.public_key)?;
        let recovery_key = get_recovery_key(&secrets.master_key, &key_attributes).ok();

        Ok(AuthenticatedAccount {
            user_id: auth_response.id,
            key_attributes,
            secrets: AccountSecrets {
                token: secrets.token.into_vec(),
                master_key: secrets.master_key.into_vec(),
                secret_key: secrets.secret_key.into_vec(),
                public_key,
            },
            recovery_key,
        })
    }

    async fn create_account_with_strength(
        &mut self,
        params: CreateAccountParams,
        key_derivation_strength: KeyDerivationStrength,
    ) -> Result<AuthenticatedAccount> {
        let email = params.email;
        let password = params.password;

        self.client
            .send_otp(&email, OtpPurpose::Signup.as_api_purpose())
            .await?;

        let verification = self
            .verify_email_otp(&email, OtpPurpose::Signup, params.source.as_deref())
            .await?;

        self.finish_verified_signup(email, password, verification, key_derivation_strength)
            .await
    }

    async fn finish_verified_signup(
        &self,
        email: String,
        password: Zeroizing<String>,
        verification: AuthResponse,
        key_derivation_strength: KeyDerivationStrength,
    ) -> Result<AuthenticatedAccount> {
        let token = verification.token.clone().ok_or_else(|| {
            Error::AuthenticationFailed("Signup verification did not return a session token".into())
        })?;

        self.client.set_auth_token(Some(token.clone()));
        let session_validity = self.client.get_session_validity().await?;
        if verification.key_attributes.is_some()
            || verification.encrypted_token.is_some()
            || verification.is_mfa_required()
            || verification.is_passkey_required()
            || session_validity.has_set_keys
            || session_validity.key_attributes.is_some()
        {
            return Err(Error::AuthenticationFailed(
                "Email already has server-side key state; use the existing account or recover the incomplete signup instead of creating a new account.".into(),
            ));
        }

        let key_gen_result = generate_keys_with_strength(&password, key_derivation_strength)?;
        let srp_user_id = Uuid::new_v4();
        let srp_setup =
            generate_srp_setup_with_login_key(&key_gen_result.login_key, &srp_user_id.to_string())?;
        let key_attributes = key_gen_result.key_attributes.clone();

        self.client
            .set_user_key_attributes(key_attributes.clone())
            .await?;
        self.complete_signup_srp(&srp_user_id, &srp_setup).await?;

        let remote_srp_attributes = self.client.get_srp_attributes(&email).await?;
        validate_remote_srp_attributes(
            &remote_srp_attributes,
            &srp_user_id,
            &srp_setup,
            &key_attributes,
        )?;

        let secrets = AccountSecrets {
            token: decode_plain_token(&token)?.into_vec(),
            master_key: crypto::decode_b64(&key_gen_result.private_key_attributes.key)?,
            secret_key: crypto::decode_b64(&key_gen_result.private_key_attributes.secret_key)?,
            public_key: crypto::decode_b64(&key_attributes.public_key)?,
        };

        Ok(AuthenticatedAccount {
            user_id: verification.id,
            key_attributes,
            secrets,
            recovery_key: Some(
                key_gen_result
                    .private_key_attributes
                    .recovery_key
                    .into_string(),
            ),
        })
    }

    async fn verify_email_otp(
        &mut self,
        email: &str,
        purpose: OtpPurpose,
        source: Option<&str>,
    ) -> Result<AuthResponse> {
        let mut resent = false;

        loop {
            let otp = self.ui.read_email_otp(email, purpose, resent)?;
            match self.client.verify_email(email, &otp, source).await {
                Ok(response) => return Ok(response),
                Err(error) if error.is_http_status(&[400, 401]) => {
                    self.ui
                        .report_retryable_error("Incorrect email verification code. Try again.")?;
                    resent = false;
                }
                Err(error) if error.is_http_status(&[429]) => {
                    return Err(Error::AuthenticationFailed(
                        "Too many incorrect email verification attempts. Please wait and request a new code.".into(),
                    ));
                }
                Err(error) if error.is_http_status(&[410]) => {
                    self.client
                        .send_otp(email, purpose.as_api_purpose())
                        .await?;
                    resent = true;
                }
                Err(error) => return Err(error),
            }
        }
    }

    async fn resolve_second_factor(&mut self, auth_response: AuthResponse) -> Result<AuthResponse> {
        let has_totp = auth_response.get_two_factor_session_id().is_some();
        let has_passkey = auth_response.is_passkey_required();

        let method = match (has_totp, has_passkey) {
            (false, false) => return Ok(auth_response),
            (true, false) => SecondFactorMethod::Totp,
            (false, true) => SecondFactorMethod::Passkey,
            (true, true) => self
                .ui
                .choose_second_factor(&[SecondFactorMethod::Totp, SecondFactorMethod::Passkey])?,
        };

        match method {
            SecondFactorMethod::Totp => self.verify_totp(&auth_response).await,
            SecondFactorMethod::Passkey => self.verify_passkey(&auth_response).await,
        }
    }

    async fn verify_totp(&mut self, auth_response: &AuthResponse) -> Result<AuthResponse> {
        let session_id = auth_response
            .get_two_factor_session_id()
            .ok_or_else(|| Error::AuthenticationFailed("No 2FA session ID".into()))?;

        loop {
            let code = self.ui.read_totp_code(TotpPurpose::Login)?;
            match self.client.verify_totp(session_id, &code).await {
                Ok(response) => return Ok(response),
                Err(error) if error.is_http_status(&[400, 401]) => {
                    self.ui
                        .report_retryable_error("Incorrect TOTP code. Try again.")?;
                }
                Err(error) if error.is_http_status(&[429]) => {
                    return Err(Error::AuthenticationFailed(
                        "Too many incorrect TOTP attempts. Please restart login.".into(),
                    ));
                }
                Err(error) if error.is_http_status(&[404, 410]) => {
                    return Err(Error::AuthenticationFailed(
                        "TOTP session expired. Please restart login.".into(),
                    ));
                }
                Err(error) => return Err(error),
            }
        }
    }

    async fn verify_passkey(&mut self, auth_response: &AuthResponse) -> Result<AuthResponse> {
        let passkey_session_id = auth_response
            .passkey_session_id
            .as_ref()
            .filter(|session_id| !session_id.is_empty())
            .ok_or_else(|| Error::AuthenticationFailed("No passkey session ID".into()))?;

        let accounts_url = auth_response
            .accounts_url
            .as_deref()
            .expect("accountsUrl is required when passkeySessionID is present");

        let verification_url = build_passkey_verification_url(
            accounts_url,
            passkey_session_id,
            self.client.client_package(),
            "ente-cli://passkey",
            None,
        );

        self.ui.present_passkey_verification(&verification_url)?;

        loop {
            self.ui.wait_for_passkey_verification()?;
            match self.client.check_passkey_status(passkey_session_id).await {
                Ok(result) => return Ok(result),
                Err(error) if error.is_http_status(&[400]) => {}
                Err(error) if error.is_http_status(&[404, 410]) => {
                    return Err(Error::AuthenticationFailed(
                        "Passkey session expired. Please restart login.".into(),
                    ));
                }
                Err(error) => return Err(error),
            }
        }
    }

    async fn complete_signup_srp(
        &self,
        srp_user_id: &Uuid,
        srp_setup: &GeneratedSrpSetup,
    ) -> Result<()> {
        let mut srp_session = auth::SrpSession::new(
            &srp_user_id.to_string(),
            &srp_setup.srp_salt,
            &srp_setup.login_sub_key,
        )?;
        let srp_a = STANDARD.encode(pad_left(&srp_session.public_a(), SRP_A_LEN));

        let response = self
            .client
            .setup_srp(&SetupSrpRequest {
                srp_user_id: srp_user_id.to_string(),
                srp_salt: STANDARD.encode(&srp_setup.srp_salt),
                srp_verifier: STANDARD.encode(&srp_setup.srp_verifier),
                srp_a,
            })
            .await?;

        let srp_b = STANDARD.decode(&response.srp_b)?;
        let srp_m1 = STANDARD.encode(srp_session.compute_m1(&srp_b)?);
        let complete = self
            .client
            .complete_srp_setup(&response.setup_id, &srp_m1)
            .await?;
        let srp_m2 = STANDARD.decode(&complete.srp_m2)?;
        srp_session.verify_m2(&srp_m2).map_err(Error::from)?;
        Ok(())
    }

    async fn complete_srp_update(
        &self,
        srp_user_id: &Uuid,
        srp_setup: &GeneratedSrpSetup,
        updated_key_attr: &UpdatedKeyAttr,
        log_out_other_devices: bool,
    ) -> Result<crate::models::UpdateSrpAndKeysResponse> {
        let mut srp_session = auth::SrpSession::new(
            &srp_user_id.to_string(),
            &srp_setup.srp_salt,
            &srp_setup.login_sub_key,
        )?;
        let srp_a = STANDARD.encode(pad_left(&srp_session.public_a(), SRP_A_LEN));

        let setup = self
            .client
            .setup_srp(&SetupSrpRequest {
                srp_user_id: srp_user_id.to_string(),
                srp_salt: STANDARD.encode(&srp_setup.srp_salt),
                srp_verifier: STANDARD.encode(&srp_setup.srp_verifier),
                srp_a,
            })
            .await?;

        let srp_b = STANDARD.decode(&setup.srp_b)?;
        let srp_m1 = STANDARD.encode(srp_session.compute_m1(&srp_b)?);

        let response = self
            .client
            .update_srp_and_key_attributes(&UpdateSrpAndKeysRequest {
                setup_id: setup.setup_id.to_string(),
                srp_m1,
                updated_key_attr: updated_key_attr.clone(),
                log_out_other_devices,
            })
            .await?;

        let srp_m2 = STANDARD.decode(&response.srp_m2)?;
        srp_session.verify_m2(&srp_m2).map_err(Error::from)?;
        Ok(response)
    }
}

/// Build the passkey verification URL for an accounts broker.
pub fn build_passkey_verification_url(
    accounts_url: &str,
    passkey_session_id: &str,
    client_package: &str,
    redirect: &str,
    recover: Option<&str>,
) -> String {
    let mut params = vec![
        ("clientPackage", client_package),
        ("passkeySessionID", passkey_session_id),
        ("redirect", redirect),
    ];
    if let Some(recover) = recover {
        params.push(("recover", recover));
    }

    let query = params
        .into_iter()
        .map(|(key, value)| format!("{key}={}", urlencoding::encode(value)))
        .collect::<Vec<_>>()
        .join("&");

    format!("{accounts_url}/passkeys/verify?{query}")
}

fn pad_left(data: &[u8], len: usize) -> Vec<u8> {
    if data.len() >= len {
        return data.to_vec();
    }

    let mut padded = vec![0u8; len - data.len()];
    padded.extend_from_slice(data);
    padded
}

fn decode_plain_token(token: &str) -> Result<SecretVec> {
    let bytes = URL_SAFE
        .decode(token)
        .or_else(|_| STANDARD.decode(token))
        .map_err(|e| Error::Crypto(format!("token: {e}")))?;
    Ok(SecretVec::new(bytes))
}

fn decrypt_auth_response(
    auth_response: &AuthResponse,
    key_attributes: &KeyAttributes,
    kek: &[u8],
) -> Result<DecryptedSecrets> {
    if let Some(encrypted_token) = auth_response.encrypted_token.as_deref() {
        auth::decrypt_secrets(kek, key_attributes, encrypted_token).map_err(Error::from)
    } else if let Some(token) = auth_response.token.as_deref() {
        let (master_key, secret_key) = auth::decrypt_keys_only(kek, key_attributes)?;
        Ok(DecryptedSecrets {
            master_key,
            secret_key,
            token: decode_plain_token(token)?,
        })
    } else {
        Err(Error::AuthenticationFailed("No token in response".into()))
    }
}

fn validate_remote_srp_attributes(
    remote: &SrpAttributes,
    srp_user_id: &Uuid,
    srp_setup: &GeneratedSrpSetup,
    key_attributes: &KeyAttributes,
) -> Result<()> {
    let expected_salt = STANDARD.encode(&srp_setup.srp_salt);
    let mut mismatches = Vec::new();

    if remote.srp_user_id != *srp_user_id {
        mismatches.push("srpUserID");
    }
    if remote.srp_salt != expected_salt {
        mismatches.push("srpSalt");
    }
    if remote.kek_salt != key_attributes.kek_salt {
        mismatches.push("kekSalt");
    }
    if remote.mem_limit != key_attributes.mem_limit {
        mismatches.push("memLimit");
    }
    if remote.ops_limit != key_attributes.ops_limit {
        mismatches.push("opsLimit");
    }

    if !mismatches.is_empty() {
        return Err(Error::AuthenticationFailed(format!(
            "Remote SRP attributes mismatched after signup: {}",
            mismatches.join(", ")
        )));
    }

    Ok(())
}

fn encrypt_two_factor_secret(
    secret_code: &str,
    recovery_key_hex: &str,
    code: &str,
) -> Result<EnableTwoFactorRequest> {
    let recovery_key =
        hex::decode(recovery_key_hex).map_err(|e| Error::Crypto(format!("recovery_key: {e}")))?;
    let encrypted = secretbox::encrypt(
        secret_code.as_bytes(),
        &crypto::Key::try_from_slice(&recovery_key)?,
    );

    Ok(EnableTwoFactorRequest {
        code: code.to_string(),
        encrypted_two_factor_secret: crypto::encode_b64(&encrypted.encrypted_data),
        two_factor_secret_decryption_nonce: crypto::encode_b64(encrypted.nonce.as_bytes()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};
    use serde::{Deserialize, de::DeserializeOwned};
    use sha2::{Digest, Sha256};
    use srp::ServerG4096;
    use std::{
        collections::VecDeque,
        sync::{Arc, Mutex},
    };

    use crate::types::AccountsClientConfig;

    #[derive(Default)]
    struct MockSignupState {
        uploaded_key_attributes: Option<KeyAttributes>,
        remote_srp_attributes: Option<SrpAttributes>,
        pending_setup_id: Option<Uuid>,
        pending_client_proof: Option<Vec<u8>>,
        pending_server_proof: Option<Vec<u8>>,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SetUserAttributesPayload {
        key_attributes: KeyAttributes,
    }

    #[derive(Debug, Deserialize)]
    struct SetupSrpPayload {
        #[serde(rename = "srpUserID")]
        srp_user_id: String,
        #[serde(rename = "srpSalt")]
        srp_salt: String,
        #[serde(rename = "srpVerifier")]
        srp_verifier: String,
        #[serde(rename = "srpA")]
        srp_a: String,
    }

    #[derive(Debug, Deserialize)]
    struct CompleteSrpSetupPayload {
        #[serde(rename = "setupID")]
        setup_id: String,
        #[serde(rename = "srpM1")]
        srp_m1: String,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct UpdateSrpPayload {
        setup_id: String,
        srp_m1: String,
        updated_key_attr: UpdatedKeyAttr,
        log_out_other_devices: bool,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ConfigurePasskeyRecoveryPayload {
        secret: String,
        user_secret_cipher: String,
        user_secret_nonce: String,
    }

    fn parse_request_body<T>(request: &mockito::Request) -> T
    where
        T: DeserializeOwned,
    {
        serde_json::from_str(&request.utf8_lossy_body().unwrap()).unwrap()
    }

    struct ScriptedUi {
        email_otps: VecDeque<String>,
        login_totps: VecDeque<String>,
        setup_totps: VecDeque<String>,
        chosen_second_factor: Option<SecondFactorMethod>,
        last_totp_secret: Option<String>,
        passkey_presented: bool,
        retryable_errors: Vec<String>,
    }

    impl ScriptedUi {
        fn new() -> Self {
            Self {
                email_otps: VecDeque::new(),
                login_totps: VecDeque::new(),
                setup_totps: VecDeque::new(),
                chosen_second_factor: None,
                last_totp_secret: None,
                passkey_presented: false,
                retryable_errors: Vec::new(),
            }
        }
    }

    impl AuthFlowUi for ScriptedUi {
        fn read_email_otp(
            &mut self,
            _email: &str,
            _purpose: OtpPurpose,
            _resent: bool,
        ) -> Result<String> {
            self.email_otps
                .pop_front()
                .ok_or_else(|| Error::InvalidInput("No scripted email OTP available".into()))
        }

        fn read_totp_code(&mut self, purpose: TotpPurpose) -> Result<String> {
            let queue = match purpose {
                TotpPurpose::Login => &mut self.login_totps,
                TotpPurpose::Setup => &mut self.setup_totps,
            };

            queue
                .pop_front()
                .ok_or_else(|| Error::InvalidInput("No scripted TOTP code available".into()))
        }

        fn report_retryable_error(&mut self, message: &str) -> Result<()> {
            self.retryable_errors.push(message.to_string());
            Ok(())
        }

        fn choose_second_factor(
            &mut self,
            methods: &[SecondFactorMethod],
        ) -> Result<SecondFactorMethod> {
            if let Some(choice) = self.chosen_second_factor {
                Ok(choice)
            } else {
                methods
                    .first()
                    .copied()
                    .ok_or_else(|| Error::InvalidInput("No second-factor method available".into()))
            }
        }

        fn present_passkey_verification(&mut self, _url: &str) -> Result<()> {
            self.passkey_presented = true;
            Ok(())
        }

        fn wait_for_passkey_verification(&mut self) -> Result<()> {
            Ok(())
        }

        fn present_totp_secret(&mut self, secret_code: &str, _qr_code: &str) -> Result<()> {
            self.last_totp_secret = Some(secret_code.to_string());
            Ok(())
        }
    }

    fn make_client(origin: String) -> AccountsClient {
        AccountsClient::new(
            AccountsClientConfig::new("io.ente.photos")
                .with_origin(origin)
                .with_user_agent("ente-accounts-test"),
        )
        .unwrap()
    }

    fn build_login_response(
        password: &str,
        token: &str,
    ) -> (KeyAttributes, String, String, String, String) {
        let key_gen =
            auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let key_attributes = key_gen.key_attributes.clone();
        let encrypted_token = {
            let public_key = crypto::decode_b64(&key_attributes.public_key).unwrap();
            let sealed = crypto::sealed::seal(
                token.as_bytes(),
                &crypto::PublicKey::try_from_slice(&public_key).unwrap(),
            )
            .unwrap();
            crypto::encode_b64(&sealed)
        };

        (
            key_attributes,
            encrypted_token,
            key_gen.private_key_attributes.recovery_key.into_string(),
            key_gen.private_key_attributes.key.into_string(),
            key_gen.private_key_attributes.secret_key.into_string(),
        )
    }

    #[tokio::test]
    async fn login_with_email_mfa_and_totp_decrypts_account() {
        let password = "hunter2";
        let (key_attributes, encrypted_token, recovery_key, _, _) =
            build_login_response(password, "plain-auth-token");

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());
        ui.login_totps.push_back("654321".into());

        let srp_attrs = server
            .mock("GET", Matcher::Any)
            .match_request(|request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query() == "/users/srp/attributes?email=user%40example.org"
            })
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "attributes": {
                        "srpUserID": Uuid::new_v4(),
                        "srpSalt": STANDARD.encode([1u8; 16]),
                        "memLimit": key_attributes.mem_limit,
                        "opsLimit": key_attributes.ops_limit,
                        "kekSalt": key_attributes.kek_salt,
                        "isEmailMFAEnabled": true
                    }
                })
                .to_string(),
            )
            .create_async()
            .await;

        let ott = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .create_async()
            .await;

        let verify_email = server
            .mock("POST", "/users/verify-email")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "id": 77,
                    "twoFactorSessionID": "session-1",
                })
                .to_string(),
            )
            .create_async()
            .await;

        let verify_totp = server
            .mock("POST", "/users/two-factor/verify")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "id": 77,
                    "keyAttributes": key_attributes,
                    "encryptedToken": encrypted_token,
                })
                .to_string(),
            )
            .create_async()
            .await;

        let client = make_client(server.url());
        let mut flow = AuthFlow::new(&client, &mut ui);

        let result = flow
            .login(LoginParams {
                email: "user@example.org".into(),
                password: Zeroizing::new(password.into()),
            })
            .await
            .unwrap();

        assert_eq!(result.user_id, 77);
        assert_eq!(result.secrets.token, b"plain-auth-token");
        assert_eq!(result.recovery_key.as_deref(), Some(recovery_key.as_str()));

        srp_attrs.assert_async().await;
        ott.assert_async().await;
        verify_email.assert_async().await;
        verify_totp.assert_async().await;
    }

    #[tokio::test]
    async fn login_with_email_mfa_treats_429_as_terminal_error() {
        let password = "hunter2";
        let key_gen =
            auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let key_attributes = key_gen.key_attributes.clone();

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());

        let srp_attrs = server
            .mock("GET", Matcher::Any)
            .match_request(|request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query() == "/users/srp/attributes?email=user%40example.org"
            })
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "attributes": {
                        "srpUserID": Uuid::new_v4(),
                        "srpSalt": STANDARD.encode([1u8; 16]),
                        "memLimit": key_attributes.mem_limit,
                        "opsLimit": key_attributes.ops_limit,
                        "kekSalt": key_attributes.kek_salt,
                        "isEmailMFAEnabled": true
                    }
                })
                .to_string(),
            )
            .create_async()
            .await;

        let ott = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .create_async()
            .await;

        let verify_email = server
            .mock("POST", "/users/verify-email")
            .with_status(429)
            .with_body("too many attempts")
            .create_async()
            .await;

        let client = make_client(server.url());
        let mut flow = AuthFlow::new(&client, &mut ui);

        let error = flow
            .login(LoginParams {
                email: "user@example.org".into(),
                password: Zeroizing::new(password.into()),
            })
            .await
            .unwrap_err();

        match error {
            Error::AuthenticationFailed(message) => {
                assert_eq!(
                    message,
                    "Too many incorrect email verification attempts. Please wait and request a new code."
                );
            }
            other => panic!("unexpected error: {other:?}"),
        }
        assert!(ui.retryable_errors.is_empty());

        srp_attrs.assert_async().await;
        ott.assert_async().await;
        verify_email.assert_async().await;
    }

    #[tokio::test]
    async fn login_with_totp_treats_404_as_expired_session() {
        let password = "hunter2";
        let key_gen =
            auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let key_attributes = key_gen.key_attributes.clone();

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());
        ui.login_totps.push_back("654321".into());

        let srp_attrs = server
            .mock("GET", Matcher::Any)
            .match_request(|request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query() == "/users/srp/attributes?email=user%40example.org"
            })
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "attributes": {
                        "srpUserID": Uuid::new_v4(),
                        "srpSalt": STANDARD.encode([1u8; 16]),
                        "memLimit": key_attributes.mem_limit,
                        "opsLimit": key_attributes.ops_limit,
                        "kekSalt": key_attributes.kek_salt,
                        "isEmailMFAEnabled": true
                    }
                })
                .to_string(),
            )
            .create_async()
            .await;

        let ott = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .create_async()
            .await;

        let verify_email = server
            .mock("POST", "/users/verify-email")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "id": 77,
                    "twoFactorSessionID": "session-1",
                })
                .to_string(),
            )
            .create_async()
            .await;

        let verify_totp = server
            .mock("POST", "/users/two-factor/verify")
            .with_status(404)
            .with_body("missing session")
            .create_async()
            .await;

        let client = make_client(server.url());
        let mut flow = AuthFlow::new(&client, &mut ui);

        let error = flow
            .login(LoginParams {
                email: "user@example.org".into(),
                password: Zeroizing::new(password.into()),
            })
            .await
            .unwrap_err();

        match error {
            Error::AuthenticationFailed(message) => {
                assert_eq!(message, "TOTP session expired. Please restart login.");
            }
            other => panic!("unexpected error: {other:?}"),
        }

        srp_attrs.assert_async().await;
        ott.assert_async().await;
        verify_email.assert_async().await;
        verify_totp.assert_async().await;
    }

    #[tokio::test]
    async fn login_with_totp_treats_429_as_terminal_error() {
        let password = "hunter2";
        let key_gen =
            auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let key_attributes = key_gen.key_attributes.clone();

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());
        ui.login_totps.push_back("654321".into());

        let srp_attrs = server
            .mock("GET", Matcher::Any)
            .match_request(|request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query() == "/users/srp/attributes?email=user%40example.org"
            })
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "attributes": {
                        "srpUserID": Uuid::new_v4(),
                        "srpSalt": STANDARD.encode([1u8; 16]),
                        "memLimit": key_attributes.mem_limit,
                        "opsLimit": key_attributes.ops_limit,
                        "kekSalt": key_attributes.kek_salt,
                        "isEmailMFAEnabled": true
                    }
                })
                .to_string(),
            )
            .create_async()
            .await;

        let ott = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .create_async()
            .await;

        let verify_email = server
            .mock("POST", "/users/verify-email")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "id": 77,
                    "twoFactorSessionID": "session-1",
                })
                .to_string(),
            )
            .create_async()
            .await;

        let verify_totp = server
            .mock("POST", "/users/two-factor/verify")
            .with_status(429)
            .with_body("too many attempts")
            .create_async()
            .await;

        let client = make_client(server.url());
        let mut flow = AuthFlow::new(&client, &mut ui);

        let error = flow
            .login(LoginParams {
                email: "user@example.org".into(),
                password: Zeroizing::new(password.into()),
            })
            .await
            .unwrap_err();

        match error {
            Error::AuthenticationFailed(message) => {
                assert_eq!(
                    message,
                    "Too many incorrect TOTP attempts. Please restart login."
                );
            }
            other => panic!("unexpected error: {other:?}"),
        }
        assert!(ui.retryable_errors.is_empty());

        srp_attrs.assert_async().await;
        ott.assert_async().await;
        verify_email.assert_async().await;
        verify_totp.assert_async().await;
    }

    #[tokio::test]
    async fn setup_two_factor_encrypts_secret_with_recovery_key() {
        let password = "pw";
        let key_gen =
            auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let recovery_key = key_gen.private_key_attributes.recovery_key.into_string();
        let master_key = crypto::decode_b64(&key_gen.private_key_attributes.key).unwrap();
        let key_attributes = key_gen.key_attributes.clone();

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.setup_totps.push_back("123123".into());

        let setup = server
            .mock("POST", "/users/two-factor/setup")
            .match_header("x-auth-token", "session-token")
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "secretCode": "JBSWY3DPEHPK3PXP",
                    "qrCode": "qr-png-b64"
                })
                .to_string(),
            )
            .create_async()
            .await;

        let enable = server
            .mock("POST", "/users/two-factor/enable")
            .match_header("x-auth-token", "session-token")
            .match_header("x-client-package", "io.ente.photos")
            .match_body(Matcher::Regex("\"encryptedTwoFactorSecret\"".into()))
            .with_status(200)
            .create_async()
            .await;

        let client = make_client(server.url());
        client.set_auth_token(Some("session-token".into()));
        let mut flow = AuthFlow::new(&client, &mut ui);

        let result = flow
            .setup_two_factor(SetupTwoFactorParams {
                master_key: SecretVec::new(master_key),
                key_attributes: Some(key_attributes),
            })
            .await
            .unwrap();

        assert_eq!(result.secret_code, "JBSWY3DPEHPK3PXP");
        assert_eq!(result.recovery_key, recovery_key);
        assert_eq!(ui.last_totp_secret.as_deref(), Some("JBSWY3DPEHPK3PXP"));

        setup.assert_async().await;
        enable.assert_async().await;
    }

    #[tokio::test]
    async fn configure_passkey_recovery_accepts_hex_recovery_key() {
        let key_gen =
            auth::generate_keys_with_strength("pw", auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let recovery_key_hex = key_gen.private_key_attributes.recovery_key.into_string();
        let expected_recovery_key = hex::decode(&recovery_key_hex).unwrap();

        let mut server = Server::new_async().await;
        let configure = server
            .mock("POST", "/users/two-factor/passkeys/configure-recovery")
            .match_header("x-auth-token", "session-token")
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body_from_request(move |request| {
                let payload: ConfigurePasskeyRecoveryPayload = parse_request_body(request);
                let cipher = crypto::decode_b64(&payload.user_secret_cipher).unwrap();
                let nonce = crypto::decode_b64(&payload.user_secret_nonce).unwrap();
                let decrypted = secretbox::decrypt(
                    &cipher,
                    &crypto::Nonce::try_from_slice(&nonce).unwrap(),
                    &crypto::Key::try_from_slice(&expected_recovery_key).unwrap(),
                )
                .unwrap();
                assert_eq!(payload.secret, "reset-secret");
                assert_eq!(String::from_utf8(decrypted).unwrap(), "reset-secret");
                Vec::new()
            })
            .create_async()
            .await;

        let client = make_client(server.url());
        client.set_auth_token(Some("session-token".into()));
        let mut ui = ScriptedUi::new();
        let flow = AuthFlow::new(&client, &mut ui);

        flow.configure_passkey_recovery("reset-secret", &recovery_key_hex)
            .await
            .unwrap();

        configure.assert_async().await;
    }

    #[tokio::test]
    async fn login_with_passkey_treats_404_as_expired_session() {
        let password = "hunter2";
        let key_gen =
            auth::generate_keys_with_strength(password, auth::KeyDerivationStrength::Interactive)
                .unwrap();
        let key_attributes = key_gen.key_attributes.clone();

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());

        let srp_attrs = server
            .mock("GET", Matcher::Any)
            .match_request(|request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query() == "/users/srp/attributes?email=user%40example.org"
            })
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "attributes": {
                        "srpUserID": Uuid::new_v4(),
                        "srpSalt": STANDARD.encode([1u8; 16]),
                        "memLimit": key_attributes.mem_limit,
                        "opsLimit": key_attributes.ops_limit,
                        "kekSalt": key_attributes.kek_salt,
                        "isEmailMFAEnabled": true
                    }
                })
                .to_string(),
            )
            .create_async()
            .await;

        let ott = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .create_async()
            .await;

        let verify_email = server
            .mock("POST", "/users/verify-email")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "id": 77,
                    "passkeySessionID": "passkey-session",
                    "accountsUrl": "https://accounts.example.org"
                })
                .to_string(),
            )
            .create_async()
            .await;

        let passkey_status = server
            .mock("GET", "/users/two-factor/passkeys/get-token")
            .match_query(Matcher::UrlEncoded(
                "sessionID".into(),
                "passkey-session".into(),
            ))
            .with_status(404)
            .with_body("expired")
            .create_async()
            .await;

        let client = make_client(server.url());
        let mut flow = AuthFlow::new(&client, &mut ui);

        let error = flow
            .login(LoginParams {
                email: "user@example.org".into(),
                password: Zeroizing::new(password.into()),
            })
            .await
            .unwrap_err();

        match error {
            Error::AuthenticationFailed(message) => {
                assert_eq!(message, "Passkey session expired. Please restart login.");
            }
            other => panic!("unexpected error: {other:?}"),
        }
        assert!(ui.passkey_presented);

        srp_attrs.assert_async().await;
        ott.assert_async().await;
        verify_email.assert_async().await;
        passkey_status.assert_async().await;
    }

    #[tokio::test]
    async fn create_account_uploads_keys_and_completes_srp_setup() {
        let email = "fresh-user@example.org";
        let encoded_email = urlencoding::encode(email).into_owned();
        let signup_token_bytes = b"signup-session-token";
        let signup_token = URL_SAFE.encode(signup_token_bytes);
        let signup_state = Arc::new(Mutex::new(MockSignupState::default()));

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());

        let send_otp = server
            .mock("POST", "/users/ott")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "email": email,
                "purpose": "signup",
            })))
            .with_status(200)
            .create_async()
            .await;

        let verify_email = server
            .mock("POST", "/users/verify-email")
            .match_body(Matcher::PartialJson(serde_json::json!({
                "email": email,
                "ott": "123456",
                "source": "testAccount",
            })))
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "id": 99,
                    "token": signup_token,
                })
                .to_string(),
            )
            .create_async()
            .await;

        let session_validity = server
            .mock("GET", "/users/session-validity/v2")
            .match_header("x-auth-token", signup_token.as_str())
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "hasSetKeys": false,
                })
                .to_string(),
            )
            .create_async()
            .await;

        let state = Arc::clone(&signup_state);
        let set_attributes = server
            .mock("PUT", "/users/attributes")
            .match_header("x-auth-token", signup_token.as_str())
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body_from_request(move |request| {
                let payload: SetUserAttributesPayload = parse_request_body(request);
                let key_attributes = payload.key_attributes;
                let mem_limit = u64::from(key_attributes.mem_limit);
                let ops_limit = u64::from(key_attributes.ops_limit);

                assert_eq!(mem_limit * ops_limit, 4_294_967_296);
                assert!(
                    key_attributes
                        .master_key_encrypted_with_recovery_key
                        .is_some()
                );
                assert!(
                    key_attributes
                        .recovery_key_encrypted_with_master_key
                        .is_some()
                );

                state.lock().unwrap().uploaded_key_attributes = Some(key_attributes);
                Vec::new()
            })
            .create_async()
            .await;

        let state = Arc::clone(&signup_state);
        let setup_srp = server
            .mock("POST", "/users/srp/setup")
            .match_header("x-auth-token", signup_token.as_str())
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body_from_request(move |request| {
                let payload: SetupSrpPayload = parse_request_body(request);
                let srp_user_id = Uuid::parse_str(&payload.srp_user_id).unwrap();
                let srp_salt = STANDARD.decode(&payload.srp_salt).unwrap();
                let srp_verifier = STANDARD.decode(&payload.srp_verifier).unwrap();
                let srp_a = STANDARD.decode(&payload.srp_a).unwrap();
                let server = ServerG4096::<Sha256>::new();
                let b_private = [0x33u8; 64];
                let srp_b = pad_left(
                    &server.compute_public_ephemeral(&b_private, &srp_verifier),
                    SRP_A_LEN,
                );
                let verifier = server
                    .process_reply(
                        payload.srp_user_id.as_bytes(),
                        &srp_salt,
                        &b_private,
                        &srp_verifier,
                        &srp_a,
                    )
                    .unwrap();
                let setup_id = Uuid::new_v4();
                let srp_a = pad_left(&srp_a, SRP_A_LEN);
                let shared_secret = pad_left(verifier.key(), SRP_A_LEN);

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

                let mut state = state.lock().unwrap();
                let uploaded_key_attributes = state.uploaded_key_attributes.clone().unwrap();
                state.pending_setup_id = Some(setup_id);
                state.remote_srp_attributes = Some(SrpAttributes {
                    srp_user_id,
                    srp_salt: payload.srp_salt,
                    mem_limit: uploaded_key_attributes.mem_limit,
                    ops_limit: uploaded_key_attributes.ops_limit,
                    kek_salt: uploaded_key_attributes.kek_salt,
                    is_email_mfa_enabled: false,
                });
                state.pending_client_proof = Some(client_proof);
                state.pending_server_proof = Some(server_proof);

                serde_json::json!({
                    "setupID": setup_id,
                    "srpB": STANDARD.encode(&srp_b),
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let state = Arc::clone(&signup_state);
        let complete_srp = server
            .mock("POST", "/users/srp/complete")
            .match_header("x-auth-token", signup_token.as_str())
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body_from_request(move |request| {
                let payload: CompleteSrpSetupPayload = parse_request_body(request);
                let setup_id = Uuid::parse_str(&payload.setup_id).unwrap();
                let srp_m1 = STANDARD.decode(&payload.srp_m1).unwrap();

                let mut state = state.lock().unwrap();
                assert_eq!(state.pending_setup_id, Some(setup_id));
                assert_eq!(state.pending_client_proof.take().unwrap(), srp_m1);

                serde_json::json!({
                    "setupID": setup_id,
                    "srpM2": STANDARD.encode(state.pending_server_proof.take().unwrap()),
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let state = Arc::clone(&signup_state);
        let get_srp_attributes = server
            .mock("GET", Matcher::Any)
            .match_request(move |request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query()
                        == format!("/users/srp/attributes?email={encoded_email}")
            })
            .with_status(200)
            .with_body_from_request(move |_| {
                let state = state.lock().unwrap();
                serde_json::json!({
                    "attributes": state.remote_srp_attributes.as_ref().unwrap()
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let client = make_client(server.url());
        let mut flow = AuthFlow::new(&client, &mut ui);

        let created = flow
            .create_account(CreateAccountParams {
                email: email.into(),
                password: Zeroizing::new("CorrectHorseBatteryStaple!".into()),
                source: Some("testAccount".into()),
            })
            .await
            .unwrap();

        assert_eq!(created.user_id, 99);
        assert_eq!(created.secrets.token, signup_token_bytes);
        assert!(created.recovery_key.is_some());

        send_otp.assert_async().await;
        verify_email.assert_async().await;
        session_validity.assert_async().await;
        set_attributes.assert_async().await;
        setup_srp.assert_async().await;
        complete_srp.assert_async().await;
        get_srp_attributes.assert_async().await;
    }

    #[tokio::test]
    async fn change_password_updates_srp_and_keys() {
        let original = auth::generate_keys_with_strength(
            "old-password",
            auth::KeyDerivationStrength::Interactive,
        )
        .unwrap();
        let key_attributes = original.key_attributes.clone();
        let master_key = crypto::decode_b64(&original.private_key_attributes.key).unwrap();
        let state = Arc::new(Mutex::new(MockSignupState::default()));

        let mut server = Server::new_async().await;

        let state_for_setup = Arc::clone(&state);
        let setup_srp = server
            .mock("POST", "/users/srp/setup")
            .match_header("x-auth-token", "session-token")
            .with_status(200)
            .with_body_from_request(move |request| {
                let payload: SetupSrpPayload = parse_request_body(request);
                let srp_salt = STANDARD.decode(&payload.srp_salt).unwrap();
                let srp_verifier = STANDARD.decode(&payload.srp_verifier).unwrap();
                let srp_a = STANDARD.decode(&payload.srp_a).unwrap();
                let server = ServerG4096::<Sha256>::new();
                let b_private = [0x44u8; 64];
                let srp_b = pad_left(
                    &server.compute_public_ephemeral(&b_private, &srp_verifier),
                    SRP_A_LEN,
                );
                let setup_id = Uuid::new_v4();
                let verifier = server
                    .process_reply(
                        payload.srp_user_id.as_bytes(),
                        &srp_salt,
                        &b_private,
                        &srp_verifier,
                        &srp_a,
                    )
                    .unwrap();
                let srp_a = pad_left(&srp_a, SRP_A_LEN);
                let shared_secret = pad_left(verifier.key(), SRP_A_LEN);

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

                let state = &mut *state_for_setup.lock().unwrap();
                state.pending_setup_id = Some(setup_id);
                state.pending_client_proof = Some(client_proof);
                state.pending_server_proof = Some(server_proof);
                state.remote_srp_attributes = Some(SrpAttributes {
                    srp_user_id: Uuid::parse_str(&payload.srp_user_id).unwrap(),
                    srp_salt: payload.srp_salt.clone(),
                    mem_limit: 0,
                    ops_limit: 0,
                    kek_salt: String::new(),
                    is_email_mfa_enabled: false,
                });

                serde_json::json!({
                    "setupID": setup_id,
                    "srpB": STANDARD.encode(&srp_b),
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let state_for_update = Arc::clone(&state);
        let update_srp = server
            .mock("POST", "/users/srp/update")
            .match_header("x-auth-token", "session-token")
            .with_status(200)
            .with_body_from_request(move |request| {
                let payload: UpdateSrpPayload = parse_request_body(request);
                let state = &mut *state_for_update.lock().unwrap();
                assert_eq!(
                    payload.setup_id,
                    state.pending_setup_id.unwrap().to_string()
                );
                assert_eq!(
                    STANDARD.decode(&payload.srp_m1).unwrap(),
                    state.pending_client_proof.as_ref().unwrap().clone()
                );
                assert!(payload.log_out_other_devices);
                state.remote_srp_attributes =
                    state.remote_srp_attributes.clone().map(|mut attrs| {
                        attrs.mem_limit = payload.updated_key_attr.mem_limit;
                        attrs.ops_limit = payload.updated_key_attr.ops_limit;
                        attrs.kek_salt = payload.updated_key_attr.kek_salt.clone();
                        attrs
                    });
                serde_json::json!({
                    "setupID": payload.setup_id,
                    "srpM2": STANDARD.encode(state.pending_server_proof.as_ref().unwrap()),
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let state_for_attrs = Arc::clone(&state);
        let get_srp_attributes = server
            .mock("GET", "/users/srp/attributes")
            .match_query(Matcher::UrlEncoded(
                "email".into(),
                "user@example.org".into(),
            ))
            .with_status(200)
            .with_body_from_request(move |_| {
                let state = state_for_attrs.lock().unwrap();
                serde_json::json!({
                    "attributes": state.remote_srp_attributes
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let client = make_client(server.url());
        client.set_auth_token(Some("session-token".into()));
        let mut ui = ScriptedUi::new();
        let flow = AuthFlow::new(&client, &mut ui);

        let result = flow
            .change_password_with_strength(
                ChangePasswordParams {
                    email: "user@example.org".into(),
                    password: Zeroizing::new("new-password".into()),
                    master_key: SecretVec::new(master_key),
                    key_attributes,
                    log_out_other_devices: true,
                },
                KeyDerivationStrength::Interactive,
            )
            .await
            .unwrap();

        assert_eq!(
            result.srp_attributes.kek_salt,
            result.key_attributes.kek_salt
        );

        setup_srp.assert_async().await;
        update_srp.assert_async().await;
        get_srp_attributes.assert_async().await;
    }
}
