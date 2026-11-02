use ente_accounts::{auth, lifecycle, login, signup};
use ente_core::{b64, crypto::SecretVec};
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use tsify::{Ts, Tsify};
use wasm_bindgen::prelude::*;

use super::Error;

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct AccountsClientConfig {
    origin: String,
    client_package: String,
    #[tsify(optional)]
    client_version: Option<String>,
}

#[wasm_bindgen]
pub struct AccountsClient(ente_accounts::AccountsClient);

#[wasm_bindgen(js_name = createAccountsClient)]
pub fn create_accounts_client(config: Ts<AccountsClientConfig>) -> Result<AccountsClient, Error> {
    let config = config.to_rust()?;
    Ok(AccountsClient(ente_accounts::AccountsClient::new(
        ente_accounts::AccountsClientConfig {
            origin: config.origin,
            client_package: config.client_package,
            client_version: config.client_version,
            user_agent: None,
            auth_token: None,
        },
    )?))
}

#[wasm_bindgen(js_name = getSRPAttributes, unchecked_return_type = "unknown")]
pub async fn get_srp_attributes(client: &AccountsClient, email: &str) -> Result<JsValue, Error> {
    let attributes = client.0.get_srp_attributes(email).await?;
    swb::to_value(&attributes).map_err(Into::into)
}

#[wasm_bindgen(js_name = sendOTP)]
pub async fn send_otp(client: &AccountsClient, email: &str, purpose: &str) -> Result<(), Error> {
    client.0.send_otp(email, purpose, false).await?;
    Ok(())
}

#[wasm_bindgen(js_name = verifyEmail, unchecked_return_type = "unknown")]
pub async fn verify_email(
    client: &AccountsClient,
    email: &str,
    code: &str,
    source: Option<String>,
) -> Result<JsValue, Error> {
    let response = client
        .0
        .verify_email(email, code, source.as_deref())
        .await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = verifySRP, unchecked_return_type = "unknown")]
pub async fn verify_srp(
    client: &AccountsClient,
    #[wasm_bindgen(unchecked_param_type = "unknown")] attributes: JsValue,
    kek: &str,
) -> Result<JsValue, Error> {
    let response = client
        .0
        .verify_srp(&swb::from_value(attributes)?, &decode(kek)?)
        .await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = verifyTwoFactor, unchecked_return_type = "unknown")]
pub async fn verify_two_factor(
    client: &AccountsClient,
    session_id: &str,
    code: &str,
) -> Result<JsValue, Error> {
    let response = client.0.verify_totp(session_id, code).await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = checkPasskeyVerificationStatus, unchecked_return_type = "unknown")]
pub async fn check_passkey_verification_status(
    client: &AccountsClient,
    session_id: &str,
) -> Result<JsValue, Error> {
    let response = client.0.check_passkey_status(session_id).await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = getSessionValidity, unchecked_return_type = "unknown")]
pub async fn get_session_validity(
    client: &AccountsClient,
    token: String,
) -> Result<JsValue, Error> {
    let response = client
        .0
        .with_auth_token(token)
        .get_session_validity()
        .await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = setKeyAttributes)]
pub async fn set_key_attributes(
    client: &AccountsClient,
    token: String,
    #[wasm_bindgen(unchecked_param_type = "unknown")] attributes: JsValue,
) -> Result<(), Error> {
    client
        .0
        .with_auth_token(token)
        .set_user_key_attributes(swb::from_value(attributes)?)
        .await?;
    Ok(())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SrpSetup {
    #[serde(rename = "srpUserID")]
    srp_user_id: String,
    srp_salt: String,
    srp_verifier: String,
    login_sub_key: String,
}

impl SrpSetup {
    fn decode(&self) -> Result<auth::GeneratedSrpSetup, Error> {
        Ok(auth::GeneratedSrpSetup {
            srp_salt: decode(&self.srp_salt)?,
            srp_verifier: decode(&self.srp_verifier)?,
            login_sub_key: SecretVec::new(decode(&self.login_sub_key)?),
        })
    }
}

#[wasm_bindgen(js_name = setupSRP)]
pub async fn setup_srp(
    client: &AccountsClient,
    token: String,
    #[wasm_bindgen(unchecked_param_type = "unknown")] setup: JsValue,
) -> Result<(), Error> {
    let setup: SrpSetup = swb::from_value(setup)?;
    signup::setup_srp(
        &client.0.with_auth_token(token),
        setup
            .srp_user_id
            .parse()
            .map_err(|_| ente_accounts::Error::InvalidInput("Invalid SRP user ID".into()))?,
        &setup.decode()?,
    )
    .await?;
    Ok(())
}

#[wasm_bindgen(js_name = completeSignup, unchecked_return_type = "unknown")]
pub async fn complete_signup(
    client: &AccountsClient,
    email: &str,
    token: String,
    #[wasm_bindgen(unchecked_param_type = "unknown")] attributes: JsValue,
    #[wasm_bindgen(unchecked_param_type = "unknown")] setup: JsValue,
) -> Result<JsValue, Error> {
    let setup: SrpSetup = swb::from_value(setup)?;
    let attributes = signup::complete_signup(
        &client.0.with_auth_token(token),
        email,
        &swb::from_value(attributes)?,
        setup
            .srp_user_id
            .parse()
            .map_err(|_| ente_accounts::Error::InvalidInput("Invalid SRP user ID".into()))?,
        &setup.decode()?,
    )
    .await?;
    swb::to_value(&attributes).map_err(Into::into)
}

#[wasm_bindgen(js_name = unlockAccount, unchecked_return_type = "unknown")]
pub fn unlock_account(
    #[wasm_bindgen(unchecked_param_type = "unknown")] response: JsValue,
    kek: &str,
) -> Result<JsValue, Error> {
    let account = login::unlock(&swb::from_value(response)?, &decode(kek)?)?;
    unlocked_account(account)
}

#[wasm_bindgen(js_name = unlockAccountWithMasterKey, unchecked_return_type = "unknown")]
pub fn unlock_account_with_master_key(
    #[wasm_bindgen(unchecked_param_type = "unknown")] response: JsValue,
    master_key: &str,
) -> Result<JsValue, Error> {
    let account = login::unlock_with_master_key(&swb::from_value(response)?, &decode(master_key)?)?;
    unlocked_account(account)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UnlockedAccount {
    master_key: String,
    token: String,
}

fn unlocked_account(account: ente_accounts::AuthenticatedAccount) -> Result<JsValue, Error> {
    swb::to_value(&UnlockedAccount {
        master_key: b64::encode(&account.secrets.master_key),
        token: b64::encode_url_safe(&account.secrets.token),
    })
    .map_err(Into::into)
}

fn decode(value: &str) -> Result<Vec<u8>, Error> {
    b64::decode(value).map_err(|error| ente_accounts::Error::Decode(error.to_string()).into())
}

#[wasm_bindgen(js_name = getTwoFactorRecovery, unchecked_return_type = "unknown")]
pub async fn get_two_factor_recovery(
    client: &AccountsClient,
    two_factor_type: &str,
    session_id: &str,
) -> Result<JsValue, Error> {
    let response = client
        .0
        .get_two_factor_recovery(
            session_id,
            swb::from_value(JsValue::from_str(two_factor_type))?,
        )
        .await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = recoverTwoFactor, unchecked_return_type = "unknown")]
pub async fn recover_two_factor(
    client: &AccountsClient,
    two_factor_type: &str,
    session_id: &str,
    #[wasm_bindgen(unchecked_param_type = "unknown")] recovery_response: JsValue,
    recovery_key: &str,
) -> Result<JsValue, Error> {
    let response = lifecycle::recover_two_factor(
        &client.0,
        swb::from_value(JsValue::from_str(two_factor_type))?,
        session_id,
        &swb::from_value(recovery_response)?,
        recovery_key,
    )
    .await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = recoverAccount, unchecked_return_type = "unknown")]
pub fn recover_account(
    #[wasm_bindgen(unchecked_param_type = "unknown")] response: JsValue,
    recovery_key: &str,
) -> Result<JsValue, Error> {
    let account = login::recover_account(&swb::from_value(response)?, recovery_key)?;
    unlocked_account(account)
}

#[wasm_bindgen(js_name = changePassword, unchecked_return_type = "unknown")]
pub async fn change_password(
    client: &AccountsClient,
    token: String,
    password: String,
    master_key: &str,
    #[wasm_bindgen(unchecked_param_type = "unknown")] key_attributes: JsValue,
) -> Result<JsValue, Error> {
    let result = lifecycle::change_password(
        &client.0.with_auth_token(token),
        lifecycle::ChangePasswordParams {
            password: password.into(),
            master_key: SecretVec::new(decode(master_key)?),
            key_attributes: swb::from_value(key_attributes)?,
            log_out_other_devices: false,
        },
    )
    .await?;
    swb::to_value(&result).map_err(Into::into)
}

#[wasm_bindgen(js_name = setupTwoFactor, unchecked_return_type = "unknown")]
pub async fn setup_two_factor(client: &AccountsClient, token: String) -> Result<JsValue, Error> {
    let response = client.0.with_auth_token(token).setup_two_factor().await?;
    swb::to_value(&response).map_err(Into::into)
}

#[wasm_bindgen(js_name = enableTwoFactor)]
pub async fn enable_two_factor(
    client: &AccountsClient,
    token: String,
    secret: &str,
    recovery_key: &str,
    code: &str,
) -> Result<(), Error> {
    lifecycle::enable_two_factor(&client.0.with_auth_token(token), secret, recovery_key, code)
        .await?;
    Ok(())
}

#[wasm_bindgen(js_name = passkeyManagementURL)]
pub async fn passkey_management_url(
    client: &AccountsClient,
    token: String,
    recovery_key: &str,
) -> Result<String, Error> {
    lifecycle::passkey_management_url(&client.0.with_auth_token(token), recovery_key)
        .await
        .map_err(Into::into)
}

#[wasm_bindgen(js_name = checkSessionValidity, unchecked_return_type = "unknown")]
pub async fn check_session_validity(
    client: &AccountsClient,
    token: String,
    email: String,
    #[wasm_bindgen(unchecked_param_type = "unknown")] local_srp_attributes: JsValue,
) -> Result<JsValue, Error> {
    let result = lifecycle::check_session_validity(
        &client.0.with_auth_token(token),
        lifecycle::CheckSessionValidityParams {
            email,
            local_srp_attributes: swb::from_value(local_srp_attributes)?,
        },
    )
    .await?;
    swb::to_value(&result).map_err(Into::into)
}
