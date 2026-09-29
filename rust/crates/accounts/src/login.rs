use ente_core::{b64, crypto::SecretVec};

use crate::{
    AccountSecrets, AccountsClient, AuthenticatedAccount, Error, Result,
    auth::{self, DecryptedSecrets, KeyAttributes, SrpAttributes, derive_kek, get_recovery_key},
    models::AuthResponse,
};

pub enum LoginStep {
    EmailCode,
    Password,
    SecondFactor { totp: bool, passkey: bool },
    Complete(Box<AuthenticatedAccount>),
}

enum State {
    EmailCode,
    Password(Option<AuthResponse>),
    SecondFactor {
        response: AuthResponse,
        kek: Option<SecretVec>,
    },
    Complete,
}

pub struct LoginFlow {
    email: String,
    attributes: SrpAttributes,
    state: State,
}

impl LoginFlow {
    pub async fn start(client: &AccountsClient, email: String) -> Result<(Self, LoginStep)> {
        let attributes = client.get_srp_attributes(&email).await?;
        let (state, step) = if attributes.is_email_mfa_enabled {
            client.send_otp(&email, "login").await?;
            (State::EmailCode, LoginStep::EmailCode)
        } else {
            (State::Password(None), LoginStep::Password)
        };
        Ok((
            Self {
                email,
                attributes,
                state,
            },
            step,
        ))
    }

    pub async fn submit_password(
        &mut self,
        client: &AccountsClient,
        password: &str,
    ) -> Result<LoginStep> {
        let State::Password(response) = &self.state else {
            return Err(Error::InvalidInput("Password is not expected".into()));
        };
        if let Some(response) = response {
            let kek = derive_kek(
                password,
                &self.attributes.kek_salt,
                self.attributes.mem_limit,
                self.attributes.ops_limit,
            )?;
            let account = build_authenticated_account(response, &kek)?;
            self.state = State::Complete;
            Ok(LoginStep::Complete(Box::new(account)))
        } else {
            let (response, kek) = client.login_with_srp(password, &self.attributes).await?;
            self.advance(response, Some(kek))
        }
    }

    pub async fn submit_code(&mut self, client: &AccountsClient, code: &str) -> Result<LoginStep> {
        let (response, kek) = match &self.state {
            State::EmailCode => (client.verify_email(&self.email, code, None).await?, None),
            State::SecondFactor { response, kek } => {
                let id = response.get_two_factor_session_id().ok_or_else(|| {
                    Error::InvalidInput("Authenticator code is not expected".into())
                })?;
                let verified = client.verify_totp(id, code).await?;
                (
                    verified,
                    kek.as_ref().map(|key| SecretVec::new(key.to_vec())),
                )
            }
            _ => {
                return Err(Error::InvalidInput(
                    "Verification code is not expected".into(),
                ));
            }
        };
        self.advance(response, kek)
    }

    pub async fn resend_code(&self, client: &AccountsClient) -> Result<()> {
        if !matches!(self.state, State::EmailCode) {
            return Err(Error::InvalidInput("Email code is not expected".into()));
        }
        client.send_otp(&self.email, "login").await
    }

    pub fn passkey_url(&self, client: &AccountsClient, redirect: &str) -> Result<String> {
        let response = self.passkey_response()?;
        Ok(build_passkey_verification_url(
            response
                .accounts_url
                .as_deref()
                .ok_or(Error::MissingField("accountsUrl"))?,
            response
                .passkey_session_id
                .as_deref()
                .ok_or(Error::MissingField("passkeySessionID"))?,
            client.client_package(),
            redirect,
            None,
        ))
    }

    pub async fn poll_passkey(&mut self, client: &AccountsClient) -> Result<Option<LoginStep>> {
        let response = self.passkey_response()?;
        let id = response
            .passkey_session_id
            .as_deref()
            .ok_or(Error::MissingField("passkeySessionID"))?;
        let Some(verified) = client.check_passkey_status(id).await? else {
            return Ok(None);
        };
        let kek = match &self.state {
            State::SecondFactor { kek, .. } => kek.as_ref().map(|key| SecretVec::new(key.to_vec())),
            _ => None,
        };
        self.advance(verified, kek).map(Some)
    }

    fn passkey_response(&self) -> Result<&AuthResponse> {
        match &self.state {
            State::SecondFactor { response, .. } if response.is_passkey_required() => Ok(response),
            _ => Err(Error::InvalidInput("Passkey is not expected".into())),
        }
    }

    fn advance(&mut self, response: AuthResponse, kek: Option<SecretVec>) -> Result<LoginStep> {
        let totp = response.is_mfa_required();
        let passkey = response.is_passkey_required();
        if totp || passkey {
            self.state = State::SecondFactor { response, kek };
            return Ok(LoginStep::SecondFactor { totp, passkey });
        }
        if let Some(kek) = kek {
            let account = build_authenticated_account(&response, &kek)?;
            self.state = State::Complete;
            Ok(LoginStep::Complete(Box::new(account)))
        } else {
            self.state = State::Password(Some(response));
            Ok(LoginStep::Password)
        }
    }
}

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

fn build_authenticated_account(
    auth_response: &AuthResponse,
    kek: &[u8],
) -> Result<AuthenticatedAccount> {
    let key_attributes = auth_response
        .key_attributes
        .clone()
        .ok_or(Error::MissingKeyAttributes)?;
    let secrets = decrypt_auth_response(auth_response, &key_attributes, kek)?;
    let public_key = b64::decode(&key_attributes.public_key)?;
    let recovery_key = get_recovery_key(&secrets.master_key, &key_attributes).ok();
    Ok(AuthenticatedAccount {
        user_id: auth_response.id,
        key_attributes,
        secrets: AccountSecrets {
            token: secrets.token.into_vec(),
            master_key: secrets.master_key.as_bytes().to_vec(),
            secret_key: secrets.secret_key.as_bytes().to_vec(),
            public_key,
        },
        recovery_key,
    })
}

fn decode_plain_token(token: &str) -> Result<SecretVec> {
    let bytes = b64::decode_url_safe(token)
        .or_else(|_| b64::decode(token))
        .map_err(|e| Error::Decode(format!("token: {e}")))?;
    Ok(SecretVec::new(bytes))
}

fn decrypt_auth_response(
    auth_response: &AuthResponse,
    key_attributes: &KeyAttributes,
    kek: &[u8],
) -> Result<DecryptedSecrets> {
    if let Some(encrypted_token) = auth_response.encrypted_token.as_deref() {
        auth::decrypt_secrets(kek, key_attributes, encrypted_token)
    } else if let Some(token) = auth_response.token.as_deref() {
        let (master_key, secret_key) = auth::decrypt_keys_only(kek, key_attributes)?;
        Ok(DecryptedSecrets {
            master_key,
            secret_key,
            token: decode_plain_token(token)?,
        })
    } else {
        Err(Error::Protocol("No token in response".into()))
    }
}

#[cfg(test)]
mod tests;
