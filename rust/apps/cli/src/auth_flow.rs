use crate::{
    api::{AppClient, client::USER_AGENT, models::KeyAttributes},
    models::{
        account::AccountSecrets,
        error::{Error, Result},
    },
};

use ente_core::b64;
use ente_core::crypto::SecretVec;
use serde::{Serialize, de::DeserializeOwned};
use std::fmt;
use zeroize::Zeroizing;

fn convert<T, U>(value: T) -> Result<U>
where
    T: Serialize,
    U: DeserializeOwned,
{
    serde_json::from_value(serde_json::to_value(value)?).map_err(Error::from)
}

fn shared_client(
    app_client: &AppClient,
    authenticated: bool,
) -> Result<ente_accounts::AccountsClient> {
    let mut config = ente_accounts::AccountsClientConfig::new(app_client.app().client_package())
        .with_origin(app_client.origin().to_string())
        .with_user_agent(USER_AGENT);
    if let Some(token) = authenticated.then(|| app_client.token()).flatten() {
        config = config.with_auth_token(token);
    }
    ente_accounts::AccountsClient::new(config).map_err(Error::from)
}

fn to_shared_error(error: Error) -> ente_accounts::Error {
    match error {
        Error::Io(source) => ente_accounts::Error::Generic(source.to_string()),
        Error::Serialization(source) => ente_accounts::Error::Serialization(source),
        Error::Database(source) => ente_accounts::Error::Generic(source.to_string()),
        Error::Crypto(message) => ente_accounts::Error::Crypto(message),
        Error::AuthenticationFailed(message) => ente_accounts::Error::AuthenticationFailed(message),
        Error::InvalidConfig(message) => ente_accounts::Error::Generic(message),
        Error::NotFound(message) => ente_accounts::Error::Generic(message),
        Error::InvalidInput(message) => ente_accounts::Error::InvalidInput(message),
        Error::Srp(message) => ente_accounts::Error::Srp(message),
        Error::Base64Decode(source) => ente_accounts::Error::Base64Decode(source),
        Error::Zip(source) => ente_accounts::Error::Generic(source.to_string()),
        Error::Http(source) => ente_accounts::Error::Http(source),
        Error::Generic(message) => ente_accounts::Error::Generic(message),
    }
}

pub use ente_accounts::{OtpPurpose, SecondFactorMethod, TotpPurpose};

pub trait AuthFlowUi {
    fn read_email_otp(&mut self, email: &str, purpose: OtpPurpose, resent: bool) -> Result<String>;
    fn read_totp_code(&mut self, purpose: TotpPurpose) -> Result<String>;
    fn report_retryable_error(&mut self, message: &str) -> Result<()>;
    fn choose_second_factor(
        &mut self,
        methods: &[SecondFactorMethod],
    ) -> Result<SecondFactorMethod>;
    fn present_passkey_verification(&mut self, url: &str) -> Result<()>;
    fn wait_for_passkey_verification(&mut self) -> Result<()>;
    fn present_totp_secret(&mut self, secret_code: &str, qr_code: &str) -> Result<()>;
}

struct UiAdapter<'a, U> {
    inner: &'a mut U,
}

impl<U: AuthFlowUi> ente_accounts::AuthFlowUi for UiAdapter<'_, U> {
    fn read_email_otp(
        &mut self,
        email: &str,
        purpose: OtpPurpose,
        resent: bool,
    ) -> ente_accounts::Result<String> {
        self.inner
            .read_email_otp(email, purpose, resent)
            .map_err(to_shared_error)
    }

    fn read_totp_code(&mut self, purpose: TotpPurpose) -> ente_accounts::Result<String> {
        self.inner.read_totp_code(purpose).map_err(to_shared_error)
    }

    fn report_retryable_error(&mut self, message: &str) -> ente_accounts::Result<()> {
        self.inner
            .report_retryable_error(message)
            .map_err(to_shared_error)
    }

    fn choose_second_factor(
        &mut self,
        methods: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        self.inner
            .choose_second_factor(methods)
            .map_err(to_shared_error)
    }

    fn present_passkey_verification(&mut self, url: &str) -> ente_accounts::Result<()> {
        self.inner
            .present_passkey_verification(url)
            .map_err(to_shared_error)
    }

    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        self.inner
            .wait_for_passkey_verification()
            .map_err(to_shared_error)
    }

    fn present_totp_secret(
        &mut self,
        secret_code: &str,
        qr_code: &str,
    ) -> ente_accounts::Result<()> {
        self.inner
            .present_totp_secret(secret_code, qr_code)
            .map_err(to_shared_error)
    }
}

pub struct CreateAccountParams {
    pub email: String,
    pub password: Zeroizing<String>,
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

pub struct LoginParams {
    pub email: String,
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

pub struct SetupTwoFactorParams {
    pub account_id: String,
    pub master_key: SecretVec,
    pub key_attributes: Option<KeyAttributes>,
}

impl fmt::Debug for SetupTwoFactorParams {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SetupTwoFactorParams")
            .field("account_id", &self.account_id)
            .field("master_key", &"[REDACTED]")
            .field("key_attributes", &self.key_attributes)
            .finish()
    }
}

pub struct AuthenticatedAccount {
    pub user_id: i64,
    pub key_attributes: KeyAttributes,
    pub secrets: AccountSecrets,
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

pub struct SetupTwoFactorResult {
    pub secret_code: String,
    pub qr_code: String,
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

fn from_shared_account(
    account: ente_accounts::AuthenticatedAccount,
) -> Result<AuthenticatedAccount> {
    Ok(AuthenticatedAccount {
        user_id: account.user_id,
        key_attributes: convert(account.key_attributes)?,
        secrets: AccountSecrets {
            token: account.secrets.token.clone(),
            master_key: account.secrets.master_key.clone(),
            secret_key: account.secrets.secret_key.clone(),
            public_key: account.secrets.public_key.clone(),
        },
        recovery_key: account.recovery_key,
    })
}

pub struct AuthFlow<'a, U> {
    app_client: &'a AppClient,
    ui: &'a mut U,
}

impl<'a, U> AuthFlow<'a, U>
where
    U: AuthFlowUi,
{
    pub fn new(app_client: &'a AppClient, ui: &'a mut U) -> Self {
        Self { app_client, ui }
    }

    pub async fn create_account(
        &mut self,
        params: CreateAccountParams,
    ) -> Result<AuthenticatedAccount> {
        let client = shared_client(self.app_client, false)?;
        let mut ui = UiAdapter { inner: self.ui };
        let mut flow = ente_accounts::AuthFlow::new(&client, &mut ui);
        let account = from_shared_account(
            flow.create_account(ente_accounts::CreateAccountParams {
                email: params.email,
                password: params.password,
                source: params.source,
            })
            .await
            .map_err(Error::from)?,
        )?;
        self.app_client
            .set_token(&b64::encode_url_safe(&account.secrets.token));
        Ok(account)
    }

    pub async fn login(&mut self, params: LoginParams) -> Result<AuthenticatedAccount> {
        let client = shared_client(self.app_client, false)?;
        let mut ui = UiAdapter { inner: self.ui };
        let mut flow = ente_accounts::AuthFlow::new(&client, &mut ui);
        from_shared_account(
            flow.login(ente_accounts::LoginParams {
                email: params.email,
                password: params.password,
            })
            .await
            .map_err(Error::from)?,
        )
    }

    pub async fn setup_two_factor(
        &mut self,
        params: SetupTwoFactorParams,
    ) -> Result<SetupTwoFactorResult> {
        let client = shared_client(self.app_client, true)?;
        let mut ui = UiAdapter { inner: self.ui };
        let mut flow = ente_accounts::AuthFlow::new(&client, &mut ui);
        let result = flow
            .setup_two_factor(ente_accounts::SetupTwoFactorParams {
                master_key: params.master_key,
                key_attributes: params.key_attributes.map(convert).transpose()?,
            })
            .await
            .map_err(Error::from)?;
        Ok(SetupTwoFactorResult {
            secret_code: result.secret_code,
            qr_code: result.qr_code,
            recovery_key: result.recovery_key,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::account::App;
    use mockito::{Matcher, Server};
    use serde::{Deserialize, de::DeserializeOwned};
    use sha2::{Digest, Sha256};
    use srp::ServerG4096;
    use std::{
        collections::VecDeque,
        sync::{Arc, Mutex},
    };
    use uuid::Uuid;

    const SRP_A_LEN: usize = 512;

    #[derive(Default)]
    struct MockSignupState {
        uploaded_key_attributes: Option<KeyAttributes>,
        remote_srp_attributes: Option<ente_accounts::models::SrpAttributes>,
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

    struct ScriptedUi {
        email_otps: VecDeque<String>,
        setup_totps: VecDeque<String>,
        last_totp_secret: Option<String>,
    }

    impl ScriptedUi {
        fn new() -> Self {
            Self {
                email_otps: VecDeque::new(),
                setup_totps: VecDeque::new(),
                last_totp_secret: None,
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

        fn read_totp_code(&mut self, _purpose: TotpPurpose) -> Result<String> {
            self.setup_totps
                .pop_front()
                .ok_or_else(|| Error::InvalidInput("No scripted TOTP code available".into()))
        }

        fn report_retryable_error(&mut self, _message: &str) -> Result<()> {
            Ok(())
        }

        fn choose_second_factor(
            &mut self,
            _methods: &[SecondFactorMethod],
        ) -> Result<SecondFactorMethod> {
            Ok(SecondFactorMethod::Totp)
        }

        fn present_passkey_verification(&mut self, _url: &str) -> Result<()> {
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

    fn parse_request_body<T>(request: &mockito::Request) -> T
    where
        T: DeserializeOwned,
    {
        serde_json::from_str(&request.utf8_lossy_body().unwrap()).unwrap()
    }

    fn pad_left(data: &[u8], len: usize) -> Vec<u8> {
        if data.len() >= len {
            return data.to_vec();
        }

        let mut padded = vec![0u8; len - data.len()];
        padded.extend_from_slice(data);
        padded
    }

    #[tokio::test]
    async fn create_account_persists_token_for_setup_two_factor() {
        let email = "fresh-user@example.org";
        let encoded_email = urlencoding::encode(email).into_owned();
        let signup_token_bytes = b"signup-session-token";
        let signup_token = b64::encode_url_safe(signup_token_bytes);
        let signup_state = Arc::new(Mutex::new(MockSignupState::default()));

        let mut server = Server::new_async().await;
        let mut ui = ScriptedUi::new();
        ui.email_otps.push_back("123456".into());
        ui.setup_totps.push_back("123123".into());

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
                state.lock().unwrap().uploaded_key_attributes = Some(payload.key_attributes);
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
                let srp_salt = b64::decode(&payload.srp_salt).unwrap();
                let srp_verifier = b64::decode(&payload.srp_verifier).unwrap();
                let srp_a = b64::decode(&payload.srp_a).unwrap();
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
                state.remote_srp_attributes = Some(ente_accounts::models::SrpAttributes {
                    srp_user_id,
                    srp_salt: payload.srp_salt,
                    mem_limit: uploaded_key_attributes.mem_limit,
                    ops_limit: uploaded_key_attributes.ops_limit,
                    kek_salt: uploaded_key_attributes.kek_salt,
                    is_email_mfa_enabled: false,
                });
                state.pending_setup_id = Some(setup_id);
                state.pending_client_proof = Some(client_proof);
                state.pending_server_proof = Some(server_proof);

                serde_json::json!({
                    "setupID": setup_id,
                    "srpB": b64::encode(&srp_b),
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
                let srp_m1 = b64::decode(&payload.srp_m1).unwrap();

                let mut state = state.lock().unwrap();
                assert_eq!(state.pending_setup_id, Some(setup_id));
                assert_eq!(state.pending_client_proof.take().unwrap(), srp_m1);

                serde_json::json!({
                    "setupID": setup_id,
                    "srpM2": b64::encode(&state.pending_server_proof.take().unwrap()),
                })
                .to_string()
                .into_bytes()
            })
            .create_async()
            .await;

        let state = Arc::clone(&signup_state);
        let srp_attributes = server
            .mock("GET", Matcher::Any)
            .match_request(move |request| {
                request.path() == "/users/srp/attributes"
                    && request.path_and_query()
                        == format!("/users/srp/attributes?email={encoded_email}")
            })
            .with_status(200)
            .with_body_from_request(move |_| {
                let state = state.lock().unwrap();
                serde_json::to_vec(&serde_json::json!({
                    "attributes": state.remote_srp_attributes.as_ref().unwrap()
                }))
                .unwrap()
            })
            .create_async()
            .await;

        let setup_two_factor = server
            .mock("POST", "/users/two-factor/setup")
            .match_header("x-auth-token", signup_token.as_str())
            .match_header("x-client-package", "io.ente.photos")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "secretCode": "JBSWY3DPEHPK3PXP",
                    "qrCode": "qr-png-b64",
                })
                .to_string(),
            )
            .create_async()
            .await;

        let enable_two_factor = server
            .mock("POST", "/users/two-factor/enable")
            .match_header("x-auth-token", signup_token.as_str())
            .match_header("x-client-package", "io.ente.photos")
            .match_body(Matcher::Regex("\"encryptedTwoFactorSecret\"".into()))
            .with_status(200)
            .create_async()
            .await;

        let app_client = AppClient::new(Some(server.url()), App::Photos).unwrap();
        let mut flow = AuthFlow::new(&app_client, &mut ui);

        let created = flow
            .create_account(CreateAccountParams {
                email: email.into(),
                password: Zeroizing::new("correct horse battery staple".into()),
                source: Some("testAccount".into()),
            })
            .await
            .unwrap();

        assert_eq!(app_client.token().as_deref(), Some(signup_token.as_str()));

        let (uploaded_key_attributes, remote_srp_attributes) = {
            let state = signup_state.lock().unwrap();
            (
                state.uploaded_key_attributes.clone().unwrap(),
                state.remote_srp_attributes.clone().unwrap(),
            )
        };

        assert_eq!(created.user_id, 99);
        assert_eq!(created.secrets.token, signup_token_bytes);
        assert_eq!(
            remote_srp_attributes.kek_salt,
            uploaded_key_attributes.kek_salt
        );
        assert_eq!(
            remote_srp_attributes.mem_limit,
            uploaded_key_attributes.mem_limit
        );
        assert_eq!(
            remote_srp_attributes.ops_limit,
            uploaded_key_attributes.ops_limit
        );

        let setup = flow
            .setup_two_factor(SetupTwoFactorParams {
                account_id: email.into(),
                master_key: SecretVec::new(created.secrets.master_key.clone()),
                key_attributes: Some(created.key_attributes),
            })
            .await
            .unwrap();

        assert_eq!(setup.secret_code, "JBSWY3DPEHPK3PXP");
        assert_eq!(ui.last_totp_secret.as_deref(), Some("JBSWY3DPEHPK3PXP"));

        send_otp.assert_async().await;
        verify_email.assert_async().await;
        session_validity.assert_async().await;
        set_attributes.assert_async().await;
        setup_srp.assert_async().await;
        complete_srp.assert_async().await;
        srp_attributes.assert_async().await;
        setup_two_factor.assert_async().await;
        enable_two_factor.assert_async().await;
    }
}
