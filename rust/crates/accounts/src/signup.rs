use ente_core::{
    b64,
    crypto::{Key, SecretVec},
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::ZeroizeOnDrop;

use crate::{
    AccountSecrets, AccountsClient, AuthenticatedAccount, Error, KeyAttributes, Result,
    auth::{
        self, GeneratedSrpSetup, KeyDerivationStrength, KeyGenResult, SrpAttributes, SrpSession,
        decrypt_keys_only, derive_kek, generate_srp_setup_with_login_key, get_recovery_key,
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

pub fn generate_keys(
    password: &str,
    srp_user_id: &str,
) -> Result<(KeyGenResult, GeneratedSrpSetup)> {
    generate_keys_with_strength(password, srp_user_id, KeyDerivationStrength::Sensitive)
}

fn generate_keys_with_strength(
    password: &str,
    srp_user_id: &str,
    strength: KeyDerivationStrength,
) -> Result<(KeyGenResult, GeneratedSrpSetup)> {
    let keys = auth::generate_keys_with_strength(password, strength)?;
    let srp = generate_srp_setup_with_login_key(&keys.login_key, srp_user_id)?;
    Ok((keys, srp))
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
        if let Some(keys) = &self.keys {
            let attributes = &keys.attributes;
            let kek = derive_kek(
                password,
                &attributes.kek_salt,
                attributes.mem_limit,
                attributes.ops_limit,
            )?;
            decrypt_keys_only(&kek, attributes)?;
            return Ok(self.clone());
        }
        self.authorize(client);
        let remote = client.get_session_validity().await?;
        if remote.has_set_keys || remote.key_attributes.is_some() {
            return Err(Error::AccountAlreadyExists);
        }
        let srp_user_id = Uuid::new_v4();
        let (generated, srp) =
            generate_keys_with_strength(password, &srp_user_id.to_string(), strength)?;
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

    pub fn token(&self) -> &[u8] {
        &self.token
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
        complete_signup(
            client,
            &self.email,
            &keys.attributes,
            keys.srp_user_id,
            &GeneratedSrpSetup {
                srp_salt: keys.srp_salt.clone(),
                srp_verifier: keys.srp_verifier.clone(),
                login_sub_key: SecretVec::new(keys.login_key.clone()),
            },
        )
        .await?;
        Ok(AuthenticatedAccount {
            user_id: self.user_id,
            key_attributes: keys.attributes.clone(),
            secrets: AccountSecrets {
                token: self.token.clone(),
                master_key: keys.master_key.clone(),
                secret_key: keys.secret_key.clone(),
                public_key: b64::decode(&keys.attributes.public_key)?,
            },
            recovery_key: get_recovery_key(
                &Key::try_from_slice(&keys.master_key)?,
                &keys.attributes,
            )?,
        })
    }
}

pub async fn complete_signup(
    client: &AccountsClient,
    email: &str,
    key_attributes: &KeyAttributes,
    srp_user_id: Uuid,
    srp: &GeneratedSrpSetup,
) -> Result<SrpAttributes> {
    let remote = client.get_session_validity().await?;
    match (remote.has_set_keys, remote.key_attributes) {
        (false, None) => {
            client
                .set_user_key_attributes(key_attributes.clone())
                .await?
        }
        (true, Some(attributes)) if attributes == *key_attributes => {}
        _ => return Err(Error::AccountAlreadyExists),
    }
    if let Err(error) = setup_srp(client, srp_user_id, srp).await
        && !matches!(&error, Error::Http(error) if error.status_code() == Some(400))
    {
        return Err(error);
    }
    let remote = client.get_srp_attributes(email).await?;
    remote.validate_setup(srp_user_id, &srp.srp_salt, key_attributes, "signup")?;
    Ok(remote)
}

pub async fn setup_srp(
    client: &AccountsClient,
    srp_user_id: Uuid,
    srp: &GeneratedSrpSetup,
) -> Result<()> {
    let mut srp_session =
        SrpSession::new(&srp_user_id.to_string(), &srp.srp_salt, &srp.login_sub_key)?;
    let srp_a = b64::encode(&srp_session.public_a());
    let response = client
        .setup_srp(&SetupSrpRequest {
            srp_user_id: srp_user_id.to_string(),
            srp_salt: b64::encode(&srp.srp_salt),
            srp_verifier: b64::encode(&srp.srp_verifier),
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
