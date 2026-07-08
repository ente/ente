//! Shared low-level account client.

use base64::{Engine, engine::general_purpose::STANDARD};
use ente_core::{
    auth::{SrpAttributes as CoreSrpAttributes, SrpSession},
    crypto::SecretVec,
    http_legacy::{Error as HttpError, HttpClient},
};
use std::time::Duration;

use crate::{
    error::{Error, Result},
    models::{
        AccountsTokenResponse, AuthResponse, CompleteSrpSetupRequest, CompleteSrpSetupResponse,
        ConfigurePasskeyRecoveryRequest, CreateSrpSessionRequest, CreateSrpSessionResponse,
        EnableTwoFactorRequest, GetSrpAttributesResponse, KeyAttributes, RemoveTwoFactorRequest,
        SendOtpRequest, SessionValidityResponse, SetRecoveryKeyRequest, SetUserAttributesRequest,
        SetupSrpRequest, SetupSrpResponse, SrpAttributes, TwoFactorAuthorizationResponse,
        TwoFactorRecoveryResponse, TwoFactorRecoveryStatusResponse, TwoFactorSecret,
        TwoFactorStatusResponse, TwoFactorType, UpdateSrpAndKeysRequest, UpdateSrpAndKeysResponse,
        VerifyEmailRequest, VerifySrpSessionRequest, VerifyTotpRequest,
    },
    types::{AccountsClientConfig, SleepFn},
};

const SRP_A_LEN: usize = 512;
const MAX_RETRIES: u32 = 3;
const INITIAL_RETRY_DELAY_MS: u64 = 250;
const MAX_RETRY_DELAY_MS: u64 = 2_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RetryPolicy {
    Default,
    NoRetry,
}

fn pad_left(data: &[u8], len: usize) -> Vec<u8> {
    if data.len() >= len {
        return data.to_vec();
    }

    let mut padded = vec![0u8; len - data.len()];
    padded.extend_from_slice(data);
    padded
}

fn require_srp_m2(auth_response: &AuthResponse) -> Result<&str> {
    auth_response
        .srp_m2
        .as_deref()
        .filter(|srp_m2| !srp_m2.is_empty())
        .ok_or_else(|| Error::AuthenticationFailed("Missing server proof".to_string()))
}

/// Shared account client built on `ente_core::http_legacy::HttpClient`.
pub struct AccountsClient {
    http: HttpClient,
    client_package: String,
    sleep_fn: SleepFn,
}

impl AccountsClient {
    /// Construct a client from a config.
    pub fn new(config: AccountsClientConfig) -> Result<Self> {
        let client_package = config.client_package.clone();
        let sleep_fn = config.sleep_fn();
        let http = HttpClient::new_with_config(config.into())?;
        Ok(Self {
            http,
            client_package,
            sleep_fn,
        })
    }

    /// Replace the auth token used for authenticated requests.
    pub fn set_auth_token(&self, auth_token: Option<String>) {
        self.http.set_auth_token(auth_token);
    }

    /// Return the client package associated with this client.
    pub fn client_package(&self) -> &str {
        &self.client_package
    }

    async fn sleep(&self, duration: Duration) {
        (self.sleep_fn)(duration).await;
    }

    fn should_retry(error: &HttpError, policy: RetryPolicy) -> bool {
        match policy {
            RetryPolicy::NoRetry => false,
            RetryPolicy::Default => match error {
                HttpError::Network(_) => true,
                HttpError::Http { status, .. } => *status == 429 || *status >= 500,
                HttpError::Parse(_) | HttpError::InvalidUrl(_) => false,
            },
        }
    }

    async fn execute<T, F, Fut>(&self, policy: RetryPolicy, mut operation: F) -> Result<T>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = std::result::Result<T, HttpError>>,
    {
        if policy == RetryPolicy::NoRetry {
            return operation().await.map_err(Error::from);
        }

        let mut attempt = 0;
        let mut delay = Duration::from_millis(INITIAL_RETRY_DELAY_MS);

        loop {
            match operation().await {
                Ok(value) => return Ok(value),
                Err(error) if Self::should_retry(&error, policy) && attempt < MAX_RETRIES => {
                    attempt += 1;
                    log::warn!(
                        "account request failed, retrying in {:?} (attempt {}/{})",
                        delay,
                        attempt,
                        MAX_RETRIES
                    );
                    self.sleep(delay).await;
                    delay = delay
                        .saturating_mul(2)
                        .min(Duration::from_millis(MAX_RETRY_DELAY_MS));
                }
                Err(error) => return Err(Error::from(error)),
            }
        }
    }

    /// Get SRP attributes for a user by email.
    pub async fn get_srp_attributes(&self, email: &str) -> Result<SrpAttributes> {
        let query = [("email", email.to_string())];
        let response: GetSrpAttributesResponse = self
            .execute(RetryPolicy::Default, || {
                self.http.get_json("/users/srp/attributes", &query)
            })
            .await?;
        Ok(response.attributes)
    }

    /// Run the full SRP login handshake and return the auth response plus KEK.
    pub async fn login_with_srp(
        &self,
        email: &str,
        password: &str,
    ) -> Result<(AuthResponse, SecretVec)> {
        let srp_attrs = self.get_srp_attributes(email).await?;
        let core_attrs = CoreSrpAttributes {
            srp_user_id: srp_attrs.srp_user_id.to_string(),
            srp_salt: srp_attrs.srp_salt.clone(),
            mem_limit: srp_attrs.mem_limit as u32,
            ops_limit: srp_attrs.ops_limit as u32,
            kek_salt: srp_attrs.kek_salt.clone(),
            is_email_mfa_enabled: srp_attrs.is_email_mfa_enabled,
        };

        let creds = ente_core::auth::derive_srp_credentials(password, &core_attrs)?;
        let srp_salt = STANDARD.decode(&srp_attrs.srp_salt)?;
        let mut srp_session =
            SrpSession::new(&core_attrs.srp_user_id, &srp_salt, &creds.login_key)?;
        let a_pub = pad_left(&srp_session.public_a(), SRP_A_LEN);

        let session = self
            .create_srp_session(&srp_attrs.srp_user_id, &a_pub)
            .await?;

        self.sleep(Duration::from_millis(100)).await;

        let server_b = STANDARD.decode(&session.srp_b)?;
        let proof = srp_session.compute_m1(&server_b)?;
        let auth_response = self
            .verify_srp_session(&srp_attrs.srp_user_id, &session.session_id, &proof)
            .await?;

        let srp_m2 = require_srp_m2(&auth_response)?;
        let server_proof = STANDARD.decode(srp_m2)?;
        srp_session.verify_m2(&server_proof).map_err(|_| {
            Error::AuthenticationFailed("Server proof verification failed".to_string())
        })?;

        Ok((auth_response, creds.kek))
    }

    /// Create an SRP session.
    pub async fn create_srp_session(
        &self,
        srp_user_id: &uuid::Uuid,
        client_public: &[u8],
    ) -> Result<CreateSrpSessionResponse> {
        let request = CreateSrpSessionRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_a: STANDARD.encode(client_public),
        };
        self.execute(RetryPolicy::Default, || {
            self.http.post_json("/users/srp/create-session", &request)
        })
        .await
    }

    /// Verify an SRP session.
    pub async fn verify_srp_session(
        &self,
        srp_user_id: &uuid::Uuid,
        session_id: &uuid::Uuid,
        client_proof: &[u8],
    ) -> Result<AuthResponse> {
        let request = VerifySrpSessionRequest {
            srp_user_id: srp_user_id.to_string(),
            session_id: session_id.to_string(),
            srp_m1: STANDARD.encode(client_proof),
        };
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/srp/verify-session", &request)
        })
        .await
    }

    /// Send an OTP/OTT.
    pub async fn send_otp(&self, email: &str, purpose: &str) -> Result<()> {
        let request = SendOtpRequest {
            email: email.to_string(),
            purpose: purpose.to_string(),
        };
        self.execute(RetryPolicy::Default, || {
            self.http.post_empty("/users/ott", &request)
        })
        .await
    }

    /// Verify email ownership with an OTT.
    pub async fn verify_email(
        &self,
        email: &str,
        ott: &str,
        source: Option<&str>,
    ) -> Result<AuthResponse> {
        let request = VerifyEmailRequest {
            email: email.to_string(),
            ott: ott.to_string(),
            source: source.map(str::to_string),
        };
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/verify-email", &request)
        })
        .await
    }

    /// Upload user key attributes.
    pub async fn set_user_key_attributes(&self, key_attributes: KeyAttributes) -> Result<()> {
        let request = SetUserAttributesRequest { key_attributes };
        self.execute(RetryPolicy::Default, || {
            self.http.put_empty("/users/attributes", &request)
        })
        .await
    }

    /// Upload recovery-key attributes.
    pub async fn set_recovery_key_attributes(&self, request: SetRecoveryKeyRequest) -> Result<()> {
        self.execute(RetryPolicy::Default, || {
            self.http.put_empty("/users/recovery-key", &request)
        })
        .await
    }

    /// Start SRP setup for an authenticated user.
    pub async fn setup_srp(&self, request: &SetupSrpRequest) -> Result<SetupSrpResponse> {
        self.execute(RetryPolicy::Default, || {
            self.http.post_json("/users/srp/setup", request)
        })
        .await
    }

    /// Complete SRP setup.
    pub async fn complete_srp_setup(
        &self,
        setup_id: &uuid::Uuid,
        srp_m1: &str,
    ) -> Result<CompleteSrpSetupResponse> {
        let request = CompleteSrpSetupRequest {
            setup_id: setup_id.to_string(),
            srp_m1: srp_m1.to_string(),
        };
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/srp/complete", &request)
        })
        .await
    }

    /// Update SRP and key attributes after a password change.
    pub async fn update_srp_and_key_attributes(
        &self,
        request: &UpdateSrpAndKeysRequest,
    ) -> Result<UpdateSrpAndKeysResponse> {
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/srp/update", request)
        })
        .await
    }

    /// Get session validity and optional remote key attributes.
    pub async fn get_session_validity(&self) -> Result<SessionValidityResponse> {
        self.execute(RetryPolicy::Default, || {
            self.http.get_json("/users/session-validity/v2", &[])
        })
        .await
    }

    /// Change the authenticated user's email.
    pub async fn change_email(&self, email: &str, ott: &str) -> Result<()> {
        let body = serde_json::json!({ "email": email, "ott": ott });
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_empty("/users/change-email", &body)
        })
        .await
    }

    /// Logout the current authenticated session.
    pub async fn logout(&self) -> Result<()> {
        let body = serde_json::json!({});
        self.execute(RetryPolicy::Default, || {
            self.http.post_empty("/users/logout", &body)
        })
        .await
    }

    /// Return whether two-factor is enabled.
    pub async fn get_two_factor_status(&self) -> Result<bool> {
        let response: TwoFactorStatusResponse = self
            .execute(RetryPolicy::Default, || {
                self.http.get_json("/users/two-factor/status", &[])
            })
            .await?;
        Ok(response.status)
    }

    /// Start TOTP setup.
    pub async fn setup_two_factor(&self) -> Result<TwoFactorSecret> {
        let body = serde_json::json!({});
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/two-factor/setup", &body)
        })
        .await
    }

    /// Enable TOTP two-factor with encrypted recovery material.
    pub async fn enable_two_factor(&self, request: &EnableTwoFactorRequest) -> Result<()> {
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_empty("/users/two-factor/enable", request)
        })
        .await
    }

    /// Disable TOTP two-factor.
    pub async fn disable_two_factor(&self) -> Result<()> {
        let body = serde_json::json!({});
        self.execute(RetryPolicy::Default, || {
            self.http.post_empty("/users/two-factor/disable", &body)
        })
        .await
    }

    /// Verify a TOTP code during login.
    pub async fn verify_totp(&self, session_id: &str, code: &str) -> Result<AuthResponse> {
        let request = VerifyTotpRequest {
            session_id: session_id.to_string(),
            code: code.to_string(),
        };
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/two-factor/verify", &request)
        })
        .await
    }

    /// Fetch 2FA recovery information.
    pub async fn get_two_factor_recovery(
        &self,
        session_id: &str,
        two_factor_type: TwoFactorType,
    ) -> Result<TwoFactorRecoveryResponse> {
        let query = [
            ("sessionID", session_id.to_string()),
            (
                "twoFactorType",
                match two_factor_type {
                    TwoFactorType::Totp => "totp".to_string(),
                    TwoFactorType::Passkey => "passkey".to_string(),
                },
            ),
        ];
        self.execute(RetryPolicy::Default, || {
            self.http.get_json("/users/two-factor/recover", &query)
        })
        .await
    }

    /// Remove 2FA using the decrypted recovery secret.
    pub async fn remove_two_factor(
        &self,
        request: &RemoveTwoFactorRequest,
    ) -> Result<TwoFactorAuthorizationResponse> {
        self.execute(RetryPolicy::NoRetry, || {
            self.http.post_json("/users/two-factor/remove", request)
        })
        .await
    }

    /// Get passkey recovery status.
    pub async fn get_two_factor_recovery_status(&self) -> Result<TwoFactorRecoveryStatusResponse> {
        self.execute(RetryPolicy::Default, || {
            self.http.get_json("/users/two-factor/recovery-status", &[])
        })
        .await
    }

    /// Configure passkey recovery.
    pub async fn configure_passkey_recovery(
        &self,
        request: &ConfigurePasskeyRecoveryRequest,
    ) -> Result<()> {
        self.execute(RetryPolicy::Default, || {
            self.http
                .post_empty("/users/two-factor/passkeys/configure-recovery", request)
        })
        .await
    }

    /// Poll passkey verification completion.
    pub async fn check_passkey_status(&self, session_id: &str) -> Result<AuthResponse> {
        let query = [("sessionID", session_id.to_string())];
        self.execute(RetryPolicy::Default, || {
            self.http
                .get_json("/users/two-factor/passkeys/get-token", &query)
        })
        .await
    }

    /// Fetch accounts-app broker token and URL.
    pub async fn get_accounts_token(&self) -> Result<AccountsTokenResponse> {
        self.execute(RetryPolicy::Default, || {
            self.http.get_json("/users/accounts-token", &[])
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::AccountsClientConfig;
    use mockito::Server;
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    fn make_client(base_url: String) -> AccountsClient {
        AccountsClient::new(
            AccountsClientConfig::new("io.ente.photos")
                .with_base_url(base_url)
                .with_user_agent("ente-accounts-test"),
        )
        .unwrap()
    }

    #[tokio::test]
    async fn send_otp_retries_on_server_error() {
        let mut server = Server::new_async().await;
        let first = server
            .mock("POST", "/users/ott")
            .with_status(500)
            .with_body("temporary failure")
            .expect(1)
            .create_async()
            .await;
        let second = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .expect(1)
            .create_async()
            .await;

        let client = make_client(server.url());
        client.send_otp("user@example.org", "login").await.unwrap();

        first.assert_async().await;
        second.assert_async().await;
    }

    #[tokio::test]
    async fn send_otp_uses_configured_sleep_fn_for_retry() {
        let mut server = Server::new_async().await;
        let first = server
            .mock("POST", "/users/ott")
            .with_status(500)
            .with_body("temporary failure")
            .expect(1)
            .create_async()
            .await;
        let second = server
            .mock("POST", "/users/ott")
            .with_status(200)
            .expect(1)
            .create_async()
            .await;

        let sleep_calls = Arc::new(AtomicUsize::new(0));
        let client = AccountsClient::new(
            AccountsClientConfig::new("io.ente.photos")
                .with_base_url(server.url())
                .with_user_agent("ente-accounts-test")
                .with_sleep_fn({
                    let sleep_calls = Arc::clone(&sleep_calls);
                    move |_| {
                        let sleep_calls = Arc::clone(&sleep_calls);
                        async move {
                            sleep_calls.fetch_add(1, Ordering::SeqCst);
                        }
                    }
                }),
        )
        .unwrap();

        client.send_otp("user@example.org", "login").await.unwrap();

        assert_eq!(sleep_calls.load(Ordering::SeqCst), 1);
        first.assert_async().await;
        second.assert_async().await;
    }

    #[tokio::test]
    async fn verify_srp_session_does_not_retry_on_server_error() {
        let mut server = Server::new_async().await;
        let verify = server
            .mock("POST", "/users/srp/verify-session")
            .with_status(500)
            .with_body("temporary failure")
            .expect(1)
            .create_async()
            .await;

        let client = make_client(server.url());
        let error = client
            .verify_srp_session(&uuid::Uuid::new_v4(), &uuid::Uuid::new_v4(), &[1u8; 32])
            .await
            .unwrap_err();

        assert_eq!(error.status_code(), Some(500));
        verify.assert_async().await;
    }

    #[tokio::test]
    async fn verify_srp_session_rejects_passkey_response_without_accounts_url() {
        let mut server = Server::new_async().await;
        let verify = server
            .mock("POST", "/users/srp/verify-session")
            .with_status(200)
            .with_header("content-type", "application/json")
            .with_body(r#"{"id":1,"passkeySessionID":"passkey-session"}"#)
            .expect(1)
            .create_async()
            .await;

        let client = make_client(server.url());
        let error = client
            .verify_srp_session(&uuid::Uuid::new_v4(), &uuid::Uuid::new_v4(), &[1u8; 32])
            .await
            .unwrap_err();

        assert!(error.to_string().contains("accountsUrl is required"));
        verify.assert_async().await;
    }

    #[tokio::test]
    async fn verify_email_does_not_retry_on_too_many_requests() {
        let mut server = Server::new_async().await;
        let verify = server
            .mock("POST", "/users/verify-email")
            .with_status(429)
            .with_body("rate limited")
            .expect(1)
            .create_async()
            .await;

        let client = make_client(server.url());
        let error = client
            .verify_email("user@example.org", "123456", Some("testAccount"))
            .await
            .unwrap_err();

        assert_eq!(error.status_code(), Some(429));
        verify.assert_async().await;
    }
}
