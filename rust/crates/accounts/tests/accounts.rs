#![cfg(test)]
#![cfg(feature = "museum")]

use ente_accounts::{
    AccountsClient, AccountsClientConfig, ChangePasswordParams, CheckSessionValidityParams, Error,
    SessionValidity, TwoFactorSetup,
    auth::{SrpSession, derive_kek, derive_srp_login_key},
    lifecycle::{
        change_password, check_session_validity, passkey_management_url, recover_two_factor,
    },
    login::{LoginFlow, LoginStep},
    models::TwoFactorType,
    signup::Signup,
};
use ente_core::{b64, crypto::SecretVec};
use ente_test_support::account_fixture::current_totp;
use ente_test_support::{HARDCODED_OTT, HARDCODED_OTT_EMAIL_SUFFIX, Museum, TestResult};
use uuid::Uuid;
use zeroize::Zeroizing;

#[test]
fn accounts() -> TestResult {
    Museum::run(|museum| tokio::runtime::Runtime::new()?.block_on(run(museum)))
}

async fn run(museum: &Museum) -> TestResult {
    let endpoint = &museum.endpoint().replace("127.0.0.1", "localhost");
    let email = format!(
        "accounts-e2e-{}{HARDCODED_OTT_EMAIL_SUFFIX}",
        Uuid::new_v4()
    );
    let password = format!("Accounts-{}!", Uuid::new_v4().simple());
    let client = accounts_client(endpoint);
    client.send_otp(&email, "signup", false).await?;
    let response = client
        .verify_email(&email, HARDCODED_OTT, Some("testAccount"))
        .await?;
    let created = Signup::verified(email.clone(), response)?
        .prepare(&client, &password)
        .await?
        .finish(&client)
        .await?;
    let setup = TwoFactorSetup::start(
        &client,
        &created.secrets.master_key,
        &created.key_attributes,
    )
    .await?;
    setup
        .enable(&client, &current_totp(&setup.secret_code)?)
        .await?;

    let login_client = accounts_client(endpoint);
    let (mut flow, mut step) = LoginFlow::start(&login_client, email.clone()).await?;
    let login = loop {
        step = match step {
            LoginStep::EmailCode => flow.submit_code(&login_client, HARDCODED_OTT).await?,
            LoginStep::Password => flow.submit_password(&login_client, &password).await?,
            LoginStep::SecondFactor { totp: true, .. } => {
                flow.submit_code(&login_client, &current_totp(&setup.secret_code)?)
                    .await?
            }
            LoginStep::SecondFactor { .. } => panic!("expected authenticator verification"),
            LoginStep::Complete(account) => break account,
        };
    };
    assert_eq!(login.user_id, created.user_id);
    assert_eq!(login.secrets.master_key, created.secrets.master_key);
    assert_eq!(client.email().await.unwrap(), email);
    assert!(client.get_two_factor_status().await.unwrap());
    let recovery_client = accounts_client(endpoint);
    recovery_client.send_otp(&email, "login", false).await?;
    let pending = recovery_client
        .verify_email(&email, HARDCODED_OTT, None)
        .await?;
    let session = pending.get_two_factor_session_id().unwrap();
    let envelope = recovery_client
        .get_two_factor_recovery(session, TwoFactorType::Totp)
        .await?;
    let recovered = recover_two_factor(
        &recovery_client,
        TwoFactorType::Totp,
        session,
        &envelope,
        &created.recovery_key,
    )
    .await?;
    assert_eq!(recovered.id, created.user_id);
    let response = recovered.into();
    let recovered = recovery_client.unlock_with_password(&response, &password)?;
    let restored =
        recovery_client.unlock_with_master_key(&response, &created.secrets.master_key)?;
    assert_eq!(restored.secrets.token, recovered.secrets.token);
    assert_eq!(restored.recovery_key, recovered.recovery_key);
    let recovery_client =
        recovery_client.with_auth_token(b64::encode_url_safe(&recovered.secrets.token));
    assert_eq!(recovery_client.email().await?, email);
    assert!(!recovery_client.get_two_factor_status().await?);
    assert_eq!(recovered.secrets.master_key, created.secrets.master_key);

    let original_srp_attributes = client.get_srp_attributes(&email).await?;
    let kek = derive_kek(
        &password,
        &original_srp_attributes.kek_salt,
        original_srp_attributes.mem_limit,
        original_srp_attributes.ops_limit,
    )?;
    let login_key = derive_srp_login_key(&kek)?;
    let mut srp_session = SrpSession::new(
        &original_srp_attributes.srp_user_id.to_string(),
        &b64::decode(&original_srp_attributes.srp_salt)?,
        &login_key,
    )?;
    let srp_session_response = client
        .create_srp_session(
            &original_srp_attributes.srp_user_id,
            &srp_session.public_a(),
        )
        .await?;
    let proof = srp_session.compute_m1(&b64::decode(&srp_session_response.srp_b)?)?;
    let expired_session_age_micros = 31 * 60 * 1_000_000;
    museum.execute_sql(&format!(
        "UPDATE srp_sessions SET created_at = now_utc_micro_seconds() - {expired_session_age_micros} WHERE id = '{}'",
        srp_session_response.session_id,
    ))?;
    assert!(matches!(
        client
            .verify_srp_session(
                &original_srp_attributes.srp_user_id,
                &srp_session_response.session_id,
                &proof,
            )
            .await,
        Err(Error::SrpSessionExpired)
    ));

    let new_password = format!("Changed-{}!", Uuid::new_v4().simple());
    let changed = change_password(
        &recovery_client,
        ChangePasswordParams {
            password: Zeroizing::new(new_password.clone()),
            master_key: SecretVec::new(recovered.secrets.master_key.clone()),
            key_attributes: recovered.key_attributes.clone(),
            log_out_other_devices: false,
        },
    )
    .await?;
    assert!(matches!(
        check_session_validity(
            &recovery_client,
            CheckSessionValidityParams {
                email: email.clone(),
                local_srp_attributes: None,
            },
        )
        .await?,
        SessionValidity::ValidButPasswordChanged { updated_key_attributes, .. }
            if updated_key_attributes.kek_salt == changed.kek_salt
    ));
    let validity = check_session_validity(
        &client,
        CheckSessionValidityParams {
            email: email.clone(),
            local_srp_attributes: Some(original_srp_attributes),
        },
    )
    .await?;
    let SessionValidity::ValidButPasswordChanged {
        updated_key_attributes,
        updated_srp_attributes,
    } = validity
    else {
        panic!("existing session did not detect the password change");
    };
    assert_eq!(updated_key_attributes.kek_salt, changed.kek_salt);

    let login_client = accounts_client(endpoint);
    assert!(matches!(
        login_client
            .login_with_srp(&password, &updated_srp_attributes)
            .await,
        Err(Error::IncorrectPassword)
    ));
    let (response, kek) = login_client
        .login_with_srp(&new_password, &updated_srp_attributes)
        .await?;
    let changed_login = login_client.unlock(&response, &kek)?;
    assert_eq!(changed_login.secrets.master_key, created.secrets.master_key);
    login_client.send_otp(&email, "login", false).await?;
    let response = login_client
        .verify_email(&email, HARDCODED_OTT, None)
        .await?;
    let recovered = login_client.recover_account(&response, &created.recovery_key)?;
    assert_eq!(recovered.secrets.secret_key, created.secrets.secret_key);
    let recovered_client =
        login_client.with_auth_token(b64::encode_url_safe(&recovered.secrets.token));
    assert_eq!(recovered_client.email().await?, email);

    let reset_password = format!("Reset-{}!", Uuid::new_v4().simple());
    change_password(
        &recovered_client,
        ChangePasswordParams {
            password: Zeroizing::new(reset_password.clone()),
            master_key: SecretVec::new(recovered.secrets.master_key.clone()),
            key_attributes: recovered.key_attributes.clone(),
            log_out_other_devices: true,
        },
    )
    .await?;
    assert!(matches!(
        check_session_validity(
            &client,
            CheckSessionValidityParams {
                email: email.clone(),
                local_srp_attributes: Some(updated_srp_attributes),
            },
        )
        .await?,
        SessionValidity::Invalid
    ));
    assert_eq!(recovered_client.email().await?, email);
    let reset_srp_attributes = login_client.get_srp_attributes(&email).await?;
    let (response, kek) = login_client
        .login_with_srp(&reset_password, &reset_srp_attributes)
        .await?;
    assert_eq!(
        login_client.unlock(&response, &kek)?.secrets.master_key,
        created.secrets.master_key
    );

    let passkey_url = passkey_management_url(&recovered_client, &created.recovery_key).await?;
    assert!(passkey_url.contains("/passkeys?token="));
    assert!(
        recovered_client
            .get_two_factor_recovery_status()
            .await?
            .is_passkey_recovery_enabled
    );
    let session = ente_core::Session::new(
        ente_core::http::ApiConfig {
            auth: Some(ente_core::http::Auth::User(b64::encode_url_safe(
                &recovered.secrets.token,
            ))),
            client_package: Some("io.ente.photos".into()),
            ..ente_core::http::ApiConfig::new(endpoint.clone())
        },
        recovered.user_id,
        ente_core::crypto::Key::try_from_slice(&recovered.secrets.master_key)?,
        ente_core::crypto::Key::try_from_slice(&hex::decode(&recovered.recovery_key)?)?,
        ente_core::crypto::SecretKey::try_from_slice(&recovered.secrets.secret_key)?,
    )?;
    let challenge = ente_accounts::deletion::get_delete_challenge(&session).await?;
    ente_accounts::deletion::delete_account(&session, &challenge, "not_listed", None).await?;
    Ok(())
}

fn accounts_client(endpoint: &str) -> AccountsClient {
    AccountsClient::new(
        AccountsClientConfig::new("io.ente.photos")
            .with_origin(endpoint)
            .with_user_agent("ente-accounts-e2e"),
    )
    .unwrap()
}
