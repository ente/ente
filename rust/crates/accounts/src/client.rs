use ente_core::b64;
use ente_core::{
    crypto::SecretVec,
    http::{self, Api, ApiConfig, Auth, Http},
};

use crate::{
    auth::{self, SrpSession},
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
    types::AccountsClientConfig,
};

const SRP_A_LEN: usize = 512;

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
        .ok_or_else(|| Error::Srp("Missing server proof".to_string()))
}

pub struct AccountsClient {
    api: Api,
    client_package: String,
}

impl AccountsClient {
    pub fn new(config: AccountsClientConfig) -> Result<Self> {
        let api = Api::new(
            Http::new()?,
            ApiConfig {
                origin: config.origin,
                client_package: Some(config.client_package.clone()),
                client_version: config.client_version,
                user_agent: config.user_agent,
                auth: config.auth_token.map(Auth::User),
            },
        );
        Ok(Self {
            api,
            client_package: config.client_package,
        })
    }

    pub fn set_auth_token(&self, auth_token: Option<String>) {
        self.api.set_auth(auth_token.map(Auth::User));
    }

    pub fn client_package(&self) -> &str {
        &self.client_package
    }

    pub async fn email(&self) -> Result<String> {
        #[derive(serde::Deserialize)]
        struct Details {
            email: String,
        }

        let details: Details = self
            .api
            .get("/users/details/v2")
            .query(&[("memoryCount", false)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?;
        Ok(details.email)
    }

    pub async fn get_srp_attributes(&self, email: &str) -> Result<SrpAttributes> {
        let query = [("email", email.to_string())];
        let response: GetSrpAttributesResponse = http::retry(|| async {
            self.api
                .get("/users/srp/attributes")
                .query(&query)
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok(response.attributes)
    }

    pub(crate) async fn login_with_srp(
        &self,
        password: &str,
        srp_attrs: &SrpAttributes,
    ) -> Result<(AuthResponse, SecretVec)> {
        let creds = auth::derive_srp_credentials(password, srp_attrs)?;
        let srp_salt = b64::decode(&srp_attrs.srp_salt)?;
        let mut srp_session = SrpSession::new(
            &srp_attrs.srp_user_id.to_string(),
            &srp_salt,
            &creds.login_key,
        )?;
        let a_pub = pad_left(&srp_session.public_a(), SRP_A_LEN);

        let session = self
            .create_srp_session(&srp_attrs.srp_user_id, &a_pub)
            .await?;

        let server_b = b64::decode(&session.srp_b)?;
        let proof = srp_session.compute_m1(&server_b)?;
        let auth_response = self
            .verify_srp_session(&srp_attrs.srp_user_id, &session.session_id, &proof)
            .await?;

        let srp_m2 = require_srp_m2(&auth_response)?;
        let server_proof = b64::decode(srp_m2)?;
        srp_session
            .verify_m2(&server_proof)
            .map_err(|_| Error::Srp("Server proof verification failed".to_string()))?;

        Ok((auth_response, creds.kek))
    }

    pub async fn create_srp_session(
        &self,
        srp_user_id: &uuid::Uuid,
        client_public: &[u8],
    ) -> Result<CreateSrpSessionResponse> {
        let request = CreateSrpSessionRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_a: b64::encode(client_public),
        };
        Ok(http::retry(|| async {
            self.api
                .post("/users/srp/create-session")
                .json(&request)
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }

    pub async fn verify_srp_session(
        &self,
        srp_user_id: &uuid::Uuid,
        session_id: &uuid::Uuid,
        client_proof: &[u8],
    ) -> Result<AuthResponse> {
        let request = VerifySrpSessionRequest {
            srp_user_id: srp_user_id.to_string(),
            session_id: session_id.to_string(),
            srp_m1: b64::encode(client_proof),
        };
        Ok(self
            .api
            .post("/users/srp/verify-session")
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(|error| match error.status_code() {
                Some(401) => Error::IncorrectPassword,
                _ => error.into(),
            })?
            .json()
            .await?)
    }

    pub async fn send_otp(&self, email: &str, purpose: &str) -> Result<()> {
        let request = SendOtpRequest {
            email: email.to_string(),
            purpose: purpose.to_string(),
        };
        Ok(http::retry(|| async {
            self.api
                .post("/users/ott")
                .json(&request)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?)
    }

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
        Ok(self
            .api
            .post("/users/verify-email")
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(|error| match error.status_code() {
                Some(400 | 401) => Error::IncorrectEmailVerificationCode,
                Some(410) => Error::EmailVerificationCodeExpired,
                Some(429) => Error::EmailVerificationRateLimited,
                _ => error.into(),
            })?
            .json()
            .await?)
    }

    pub async fn set_user_key_attributes(&self, key_attributes: KeyAttributes) -> Result<()> {
        let request = SetUserAttributesRequest { key_attributes };
        Ok(http::retry(|| async {
            self.api
                .put("/users/attributes")
                .json(&request)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?)
    }

    pub async fn set_recovery_key_attributes(&self, request: SetRecoveryKeyRequest) -> Result<()> {
        Ok(http::retry(|| async {
            self.api
                .put("/users/recovery-key")
                .json(&request)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?)
    }

    pub async fn setup_srp(&self, request: &SetupSrpRequest) -> Result<SetupSrpResponse> {
        Ok(http::retry(|| async {
            self.api
                .post("/users/srp/setup")
                .json(request)
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }

    pub async fn complete_srp_setup(
        &self,
        setup_id: &uuid::Uuid,
        srp_m1: &str,
    ) -> Result<CompleteSrpSetupResponse> {
        let request = CompleteSrpSetupRequest {
            setup_id: setup_id.to_string(),
            srp_m1: srp_m1.to_string(),
        };
        Ok(self
            .api
            .post("/users/srp/complete")
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

    pub async fn update_srp_and_key_attributes(
        &self,
        request: &UpdateSrpAndKeysRequest,
    ) -> Result<UpdateSrpAndKeysResponse> {
        Ok(self
            .api
            .post("/users/srp/update")
            .json(request)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

    pub async fn get_session_validity(&self) -> Result<SessionValidityResponse> {
        http::retry(|| async {
            self.api
                .get("/users/session-validity/v2")
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await
        .map_err(|error| match error.status_code() {
            Some(401) => Error::SessionInvalid,
            _ => error.into(),
        })
    }

    pub async fn change_email(&self, email: &str, ott: &str) -> Result<()> {
        let body = serde_json::json!({ "email": email, "ott": ott });
        self.api
            .post("/users/change-email")
            .json(&body)
            .send()
            .await?
            .error_for_code()
            .await?;
        Ok(())
    }

    pub async fn logout(&self) -> Result<()> {
        let body = serde_json::json!({});
        Ok(http::retry(|| async {
            self.api
                .post("/users/logout")
                .json(&body)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?)
    }

    pub async fn get_two_factor_status(&self) -> Result<bool> {
        let response: TwoFactorStatusResponse = http::retry(|| async {
            self.api
                .get("/users/two-factor/status")
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok(response.status)
    }

    pub async fn setup_two_factor(&self) -> Result<TwoFactorSecret> {
        let body = serde_json::json!({});
        Ok(self
            .api
            .post("/users/two-factor/setup")
            .json(&body)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

    pub async fn enable_two_factor(&self, request: &EnableTwoFactorRequest) -> Result<()> {
        self.api
            .post("/users/two-factor/enable")
            .json(request)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(|error| match error.status_code() {
                Some(400 | 401) => Error::IncorrectTotp,
                _ => error.into(),
            })?;
        Ok(())
    }

    pub async fn disable_two_factor(&self) -> Result<()> {
        let body = serde_json::json!({});
        Ok(http::retry(|| async {
            self.api
                .post("/users/two-factor/disable")
                .json(&body)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?)
    }

    pub async fn verify_totp(&self, session_id: &str, code: &str) -> Result<AuthResponse> {
        let request = VerifyTotpRequest {
            session_id: session_id.to_string(),
            code: code.to_string(),
        };
        Ok(self
            .api
            .post("/users/two-factor/verify")
            .json(&request)
            .send()
            .await?
            .error_for_code()
            .await
            .map_err(|error| match error.status_code() {
                Some(400 | 401) => Error::IncorrectTotp,
                Some(404 | 410) => Error::SecondFactorSessionExpired,
                Some(429) => Error::TotpRateLimited,
                _ => error.into(),
            })?
            .json()
            .await?)
    }

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
        Ok(http::retry(|| async {
            self.api
                .get("/users/two-factor/recover")
                .query(&query)
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }

    pub async fn remove_two_factor(
        &self,
        request: &RemoveTwoFactorRequest,
    ) -> Result<TwoFactorAuthorizationResponse> {
        Ok(self
            .api
            .post("/users/two-factor/remove")
            .json(request)
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

    pub async fn get_two_factor_recovery_status(&self) -> Result<TwoFactorRecoveryStatusResponse> {
        Ok(http::retry(|| async {
            self.api
                .get("/users/two-factor/recovery-status")
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }

    pub async fn configure_passkey_recovery(
        &self,
        request: &ConfigurePasskeyRecoveryRequest,
    ) -> Result<()> {
        Ok(http::retry(|| async {
            self.api
                .post("/users/two-factor/passkeys/configure-recovery")
                .json(request)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?)
    }

    pub async fn check_passkey_status(&self, session_id: &str) -> Result<Option<AuthResponse>> {
        let query = [("sessionID", session_id.to_string())];
        match http::retry(|| async {
            self.api
                .get("/users/two-factor/passkeys/get-token")
                .query(&query)
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await
        {
            Ok(response) => Ok(Some(response)),
            Err(error) => match error.status_code() {
                Some(400) => Ok(None),
                Some(404 | 410) => Err(Error::SecondFactorSessionExpired),
                _ => Err(error.into()),
            },
        }
    }

    pub async fn get_accounts_token(&self) -> Result<AccountsTokenResponse> {
        Ok(http::retry(|| async {
            self.api
                .get("/users/accounts-token")
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::AccountsClientConfig;
    use mockito::Server;

    fn make_client(origin: String) -> AccountsClient {
        AccountsClient::new(
            AccountsClientConfig::new("io.ente.photos")
                .with_origin(origin)
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

        assert!(matches!(&error, Error::Http(e) if e.status_code() == Some(500)));
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

        assert!(matches!(error, Error::EmailVerificationRateLimited));
        verify.assert_async().await;
    }
}
