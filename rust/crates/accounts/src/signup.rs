use ente_core::{b64, crypto::Key};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::ZeroizeOnDrop;

use crate::{
    AccountSecrets, AccountsClient, AuthenticatedAccount, Error, KeyAttributes, Result,
    auth::{
        KeyDerivationStrength, SrpSession, generate_keys_with_strength,
        generate_srp_setup_with_login_key, get_recovery_key,
    },
    models::{AuthResponse, SetupSrpRequest},
};

#[derive(Clone, Serialize, Deserialize, ZeroizeOnDrop)]
pub struct Signup {
    pub user_id: i64,
    pub email: String,
    token: Vec<u8>,
    #[zeroize(skip)]
    keys: Option<PreparedKeys>,
}

#[derive(Clone, Serialize, Deserialize, ZeroizeOnDrop)]
struct PreparedKeys {
    #[zeroize(skip)]
    attributes: KeyAttributes,
    master_key: Vec<u8>,
    secret_key: Vec<u8>,
    login_key: Vec<u8>,
    #[zeroize(skip)]
    srp_user_id: Uuid,
    srp_salt: Vec<u8>,
    srp_verifier: Vec<u8>,
}

impl Signup {
    pub fn verified(email: String, response: AuthResponse) -> Result<Self> {
        if response.key_attributes.is_some()
            || response.encrypted_token.is_some()
            || response.is_mfa_required()
            || response.is_passkey_required()
        {
            return Err(Error::AccountAlreadyExists);
        }
        let token = response.token.ok_or(Error::MissingField("token"))?;
        Ok(Self {
            user_id: response.id,
            email,
            token: b64::decode_url_safe(&token).or_else(|_| b64::decode(&token))?,
            keys: None,
        })
    }

    fn authorize(&self, client: &AccountsClient) {
        client.set_auth_token(Some(b64::encode_url_safe(&self.token)));
    }

    pub async fn prepare(&self, client: &AccountsClient, password: &str) -> Result<Self> {
        self.prepare_with_strength(client, password, KeyDerivationStrength::Sensitive)
            .await
    }

    pub(crate) async fn prepare_with_strength(
        &self,
        client: &AccountsClient,
        password: &str,
        strength: KeyDerivationStrength,
    ) -> Result<Self> {
        if self.keys.is_some() {
            return Ok(self.clone());
        }
        self.authorize(client);
        let remote = client.get_session_validity().await?;
        if remote.has_set_keys || remote.key_attributes.is_some() {
            return Err(Error::AccountAlreadyExists);
        }
        let generated = generate_keys_with_strength(password, strength)?;
        let srp_user_id = Uuid::new_v4();
        let srp =
            generate_srp_setup_with_login_key(&generated.login_key, &srp_user_id.to_string())?;
        let mut prepared = self.clone();
        prepared.keys = Some(PreparedKeys {
            master_key: b64::decode(&generated.private_key_attributes.key)?,
            secret_key: b64::decode(&generated.private_key_attributes.secret_key)?,
            attributes: generated.key_attributes,
            login_key: generated.login_key.into_vec(),
            srp_user_id,
            srp_salt: srp.srp_salt,
            srp_verifier: srp.srp_verifier,
        });
        Ok(prepared)
    }

    pub fn recovery_key(&self) -> Result<Option<String>> {
        self.keys
            .as_ref()
            .map(|keys| get_recovery_key(&Key::try_from_slice(&keys.master_key)?, &keys.attributes))
            .transpose()
    }

    pub async fn finish(&self, client: &AccountsClient) -> Result<AuthenticatedAccount> {
        let keys = self
            .keys
            .as_ref()
            .ok_or_else(|| Error::InvalidInput("Prepare signup keys first".into()))?;
        self.authorize(client);
        let remote = client.get_session_validity().await?;
        match (remote.has_set_keys, remote.key_attributes) {
            (false, None) => {
                client
                    .set_user_key_attributes(keys.attributes.clone())
                    .await?
            }
            (true, Some(attributes)) => {
                if attributes != keys.attributes {
                    return Err(Error::AccountAlreadyExists);
                }
            }
            _ => return Err(Error::AccountAlreadyExists),
        }
        // The server may have committed a previous attempt whose response was lost.
        if let Err(error) = complete_signup_srp(client, keys).await
            && !matches!(&error, Error::Http(error) if error.status_code() == Some(400))
        {
            return Err(error);
        }
        let remote = client.get_srp_attributes(&self.email).await?;
        remote.validate_setup(keys.srp_user_id, &keys.srp_salt, &keys.attributes, "signup")?;
        Ok(AuthenticatedAccount {
            user_id: self.user_id,
            key_attributes: keys.attributes.clone(),
            secrets: AccountSecrets {
                token: self.token.clone(),
                master_key: keys.master_key.clone(),
                secret_key: keys.secret_key.clone(),
                public_key: b64::decode(&keys.attributes.public_key)?,
            },
            recovery_key: self.recovery_key()?,
        })
    }
}

async fn complete_signup_srp(client: &AccountsClient, keys: &PreparedKeys) -> Result<()> {
    let mut srp_session = SrpSession::new(
        &keys.srp_user_id.to_string(),
        &keys.srp_salt,
        &keys.login_key,
    )?;
    let srp_a = b64::encode(&srp_session.public_a());
    let response = client
        .setup_srp(&SetupSrpRequest {
            srp_user_id: keys.srp_user_id.to_string(),
            srp_salt: b64::encode(&keys.srp_salt),
            srp_verifier: b64::encode(&keys.srp_verifier),
            srp_a,
        })
        .await?;
    let srp_b = b64::decode(&response.srp_b)?;
    let srp_m1 = b64::encode(&srp_session.compute_m1(&srp_b)?);
    let complete = client
        .complete_srp_setup(&response.setup_id, &srp_m1)
        .await?;
    srp_session.verify_m2(&b64::decode(&complete.srp_m2)?)?;
    Ok(())
}

#[cfg(test)]
mod tests;
