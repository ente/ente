use ente_core::{
    b64,
    crypto::{Key, Nonce, SecretKey, SecretVec, sealed, secretbox},
};

use crate::{
    AccountSecrets, AccountsClient, AuthenticatedAccount, Error, Result,
    auth::{self, KeyAttributes, SrpAttributes, derive_kek, get_recovery_key, payload},
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
    attributes: Option<SrpAttributes>,
    state: State,
}

impl LoginFlow {
    pub async fn start(client: &AccountsClient, email: String) -> Result<(Self, LoginStep)> {
        let (flow, step) = Self::prepare(client, email).await?;
        if matches!(step, LoginStep::EmailCode) {
            flow.resend_code(client).await?;
        }
        Ok((flow, step))
    }

    pub async fn prepare(client: &AccountsClient, email: String) -> Result<(Self, LoginStep)> {
        let attributes = match client.get_srp_attributes(&email).await {
            Ok(attributes) => Some(attributes),
            Err(Error::SrpNotConfigured) => None,
            Err(error) => return Err(error),
        };
        let (state, step) = if attributes.as_ref().is_none_or(|a| a.is_email_mfa_enabled) {
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
            let account = client.unlock_with_password(response, password)?;
            self.state = State::Complete;
            Ok(LoginStep::Complete(Box::new(account)))
        } else {
            let attributes = self
                .attributes
                .as_ref()
                .ok_or(Error::MissingField("SRP attributes"))?;
            let (response, kek) = client.login_with_srp(password, attributes).await?;
            self.advance(client, response, Some(kek))
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
        self.advance(client, response, kek)
    }

    pub async fn resend_code(&self, client: &AccountsClient) -> Result<()> {
        if !matches!(self.state, State::EmailCode) {
            return Err(Error::InvalidInput("Email code is not expected".into()));
        }
        client.send_otp(&self.email, "login", false).await
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
        self.advance(client, verified, kek).map(Some)
    }

    fn passkey_response(&self) -> Result<&AuthResponse> {
        match &self.state {
            State::SecondFactor { response, .. } if response.is_passkey_required() => Ok(response),
            _ => Err(Error::InvalidInput("Passkey is not expected".into())),
        }
    }

    fn advance(
        &mut self,
        client: &AccountsClient,
        response: AuthResponse,
        kek: Option<SecretVec>,
    ) -> Result<LoginStep> {
        let totp = response.is_mfa_required();
        let passkey = response.is_passkey_required();
        if totp || passkey {
            self.state = State::SecondFactor { response, kek };
            return Ok(LoginStep::SecondFactor { totp, passkey });
        }
        if let Some(kek) = kek {
            let account = client.unlock(&response, &kek)?;
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

impl AccountsClient {
    pub fn unlock_with_password(
        &self,
        auth_response: &AuthResponse,
        password: &str,
    ) -> Result<AuthenticatedAccount> {
        let attributes = auth_response
            .key_attributes
            .as_ref()
            .ok_or(Error::MissingKeyAttributes)?;
        let kek = derive_kek(
            password,
            &attributes.kek_salt,
            attributes.mem_limit,
            attributes.ops_limit,
        )?;
        self.unlock(auth_response, &kek)
    }

    pub fn unlock(&self, auth_response: &AuthResponse, kek: &[u8]) -> Result<AuthenticatedAccount> {
        let key_attributes = auth_response
            .key_attributes
            .as_ref()
            .ok_or(Error::MissingKeyAttributes)?;
        let (master_key, secret_key) = auth::decrypt_keys_only(kek, key_attributes)?;
        self.finish_unlock(auth_response, key_attributes, master_key, secret_key)
    }

    pub fn recover_account(
        &self,
        auth_response: &AuthResponse,
        recovery_key: &str,
    ) -> Result<AuthenticatedAccount> {
        let attributes = auth_response
            .key_attributes
            .as_ref()
            .ok_or(Error::MissingKeyAttributes)?;
        let recovery_key = auth::recovery_key_from_mnemonic_or_hex(recovery_key)?;
        let encrypted = attributes
            .master_key_encrypted_with_recovery_key
            .as_ref()
            .ok_or(Error::MissingField(
                "master_key_encrypted_with_recovery_key",
            ))?;
        let nonce = attributes
            .master_key_decryption_nonce
            .as_ref()
            .ok_or(Error::MissingField("master_key_decryption_nonce"))?;
        let master_key = SecretVec::new(
            secretbox::decrypt(
                &b64::decode(encrypted)?,
                &Nonce::try_from_slice(&b64::decode(nonce)?)?,
                &Key::try_from_slice(&recovery_key)?,
            )
            .map_err(|_| Error::IncorrectRecoveryKey)?,
        );
        self.unlock_with_master_key(auth_response, &master_key)
    }

    pub fn unlock_with_master_key(
        &self,
        auth_response: &AuthResponse,
        master_key: &[u8],
    ) -> Result<AuthenticatedAccount> {
        let key_attributes = auth_response
            .key_attributes
            .as_ref()
            .ok_or(Error::MissingKeyAttributes)?;
        let master_key = Key::try_from_slice(master_key)?;
        let secret_key = auth::decrypt_secret_key(&master_key, key_attributes)?;
        self.finish_unlock(auth_response, key_attributes, master_key, secret_key)
    }

    fn finish_unlock(
        &self,
        auth_response: &AuthResponse,
        key_attributes: &KeyAttributes,
        master_key: Key,
        secret_key: SecretKey,
    ) -> Result<AuthenticatedAccount> {
        if auth_response.is_mfa_required() || auth_response.is_passkey_required() {
            return Err(Error::InvalidInput(
                "Second factor verification is required".into(),
            ));
        }
        let token = if let Some(encrypted_token) = &auth_response.encrypted_token {
            let token = SecretVec::new(
                sealed::open(
                    &b64::decode(encrypted_token)?,
                    &secret_key.public_key(),
                    &secret_key,
                )
                .map_err(|_| Error::InvalidKeyAttributes)?,
            );
            payload::validate_auth_token(&self.api, &token)?;
            token
        } else if let Some(token) = &auth_response.token {
            decode_plain_token(token)?
        } else {
            return Err(Error::Protocol("No token in response".into()));
        };
        let public_key = b64::decode(&key_attributes.public_key)?;
        let recovery_key = get_recovery_key(&master_key, key_attributes)?;
        Ok(AuthenticatedAccount {
            user_id: auth_response.id,
            key_attributes: key_attributes.clone(),
            secrets: AccountSecrets {
                token: token.into_vec(),
                master_key: master_key.as_bytes().to_vec(),
                secret_key: secret_key.as_bytes().to_vec(),
                public_key,
            },
            recovery_key,
        })
    }
}

fn decode_plain_token(token: &str) -> Result<SecretVec> {
    let bytes = b64::decode_url_safe(token)
        .or_else(|_| b64::decode(token))
        .map_err(|e| Error::Decode(format!("token: {e}")))?;
    Ok(SecretVec::new(bytes))
}

#[cfg(test)]
mod tests;
