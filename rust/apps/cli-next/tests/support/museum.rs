use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, AuthenticatedAccount,
    CreateAccountParams, OtpPurpose, SecondFactorMethod, TotpPurpose,
};
use ente_core::crypto::{PublicKey, blob, sealed, secretbox};
use ente_test_support::{HARDCODED_OTT, Museum, TestResult};
use uuid::Uuid;
use zeroize::Zeroizing;

use super::*;

const PASSWORD: &str = "disposable-cli-integration-password";

#[test]
fn login_and_photos_across_processes() -> TestResult {
    Museum::run_async(exercise)
}

#[cfg(unix)]
#[test]
fn login_save_failures_follow_the_vault_replacement() -> TestResult {
    use std::os::unix::fs::PermissionsExt;

    Museum::run_async(|origin| async move {
        let email = format!("save-failure-{}@example.org", Uuid::new_v4());
        let owner = create_account(&origin, &email).await;
        for (relogin, before_replacement) in
            [(false, true), (false, false), (true, true), (true, false)]
        {
            let home = TestHome::new();
            if relogin {
                login(&home, "photos", &email, &["--host", &origin]);
            }
            let before = session_count(&origin, &owner).await;
            let vault_path = home.dir.path().join("vault.json");
            let previous_vault = fs::read(&vault_path).ok();
            let snapshot_vault = previous_vault.clone().unwrap_or_else(|| {
                home.write_vault(&json!({"accounts": [], "selected": null}));
                fs::read(&vault_path).unwrap()
            });
            fs::remove_file(&vault_path).unwrap();
            // Pause login at its first vault read.
            assert!(
                Command::new("mkfifo")
                    .arg(&vault_path)
                    .status()
                    .unwrap()
                    .success()
            );
            let mut child = home
                .command(&[
                    "photos", "login", "--host", &origin, "--input", "-", "--json",
                ])
                .stdin(Stdio::piped())
                .spawn()
                .unwrap();
            child
                .stdin
                .take()
                .unwrap()
                .write_all(&credentials(&email))
                .unwrap();
            let mut snapshot_writer = fs::OpenOptions::new()
                .write(true)
                .open(&vault_path)
                .unwrap();
            fs::remove_file(&vault_path).unwrap();
            if let Some(previous) = &previous_vault {
                fs::write(&vault_path, previous).unwrap();
            }
            let concurrent_name = if relogin && !before_replacement {
                let mut state = home.read_vault();
                state["accounts"][0]["name"] = json!("renamed");
                home.write_vault(&state);
                Some("renamed")
            } else {
                None
            };
            if before_replacement {
                fs::set_permissions(home.dir.path(), fs::Permissions::from_mode(0o500)).unwrap();
            } else {
                // Allow replacement, but deny opening the directory for its final sync.
                fs::set_permissions(home.dir.path(), fs::Permissions::from_mode(0o300)).unwrap();
            }
            snapshot_writer.write_all(&snapshot_vault).unwrap();
            drop(snapshot_writer);
            let output = child.wait_with_output().unwrap();
            fs::set_permissions(home.dir.path(), fs::Permissions::from_mode(0o700)).unwrap();
            if before_replacement {
                failure(&output);
                assert_eq!(
                    fs::read(home.dir.path().join("vault.json")).ok(),
                    previous_vault
                );
                if relogin {
                    assert_eq!(
                        home.json(&["photos", "api", "/users/details/v2"])["email"],
                        email
                    );
                }
                assert_eq!(
                    session_count(&origin, &owner).await,
                    before,
                    "failed login left an unsaved server session active"
                );
            } else {
                let stderr = String::from_utf8(output.stderr).unwrap();
                assert!(
                    output.status.success(),
                    "saved vault was reported as failed: {stderr}"
                );
                assert!(
                    stderr.contains("vault saved, but could not sync its directory"),
                    "{stderr}"
                );
                let logged_in: Value = serde_json::from_slice(&output.stdout).unwrap();
                assert_eq!(logged_in["account"]["id"], owner.user_id.to_string());
                if let Some(name) = concurrent_name {
                    assert_eq!(logged_in["account"]["name"], name);
                }
                assert_eq!(
                    home.json(&["photos", "api", "/users/details/v2"])["email"],
                    email
                );
                assert_eq!(
                    session_count(&origin, &owner).await,
                    before + usize::from(!relogin),
                    "successful login left a replaced server session active"
                );
            }
        }
        Ok(())
    })
}

async fn exercise(origin: String) -> TestResult {
    let alice_email = format!("alice-{}@example.org", Uuid::new_v4());
    let bob_email = format!("bob-{}@example.org", Uuid::new_v4());
    let alice = create_account(&origin, &alice_email).await;
    let alice_id = alice.user_id.to_string();
    let bob = create_account(&origin, &bob_email).await;
    let (album, key) = create_album(&origin, &alice, "Monsoon 🌧", "folder").await;
    let (archive, archive_key) = create_album(&origin, &alice, "Archive", "album").await;
    let (hidden, hidden_key) = create_album(&origin, &alice, "Private album", "album").await;
    let (default_hidden, default_hidden_key) =
        create_album(&origin, &alice, "Default hidden", "album").await;
    set_album_metadata(
        &origin,
        &alice,
        archive,
        &archive_key,
        "magic-metadata",
        json!({"visibility": 1}),
    )
    .await;
    set_album_metadata(
        &origin,
        &alice,
        hidden,
        &hidden_key,
        "magic-metadata",
        json!({"visibility": 2}),
    )
    .await;
    set_album_metadata(
        &origin,
        &alice,
        default_hidden,
        &default_hidden_key,
        "magic-metadata",
        json!({"subType": 1}),
    )
    .await;
    let (bob_album, _) = create_album(&origin, &bob, "Bob's album", "album").await;
    let shared_key = sealed::seal(
        key.as_bytes(),
        &PublicKey::try_from_slice(&bob.secrets.public_key).unwrap(),
    )
    .unwrap();
    reqwest::Client::new().post(format!("{origin}/collections/share"))
        .header("x-auth-token", b64::encode_url_safe(&alice.secrets.token)).header("x-client-package", "io.ente.photos")
        .json(&json!({"collectionID": album, "email": bob_email, "encryptedKey": b64::encode(&shared_key), "role": "VIEWER"}))
        .send().await.unwrap().error_for_status().unwrap();
    set_album_metadata(
        &origin,
        &bob,
        album,
        &key,
        "sharee-magic-metadata",
        json!({"visibility": 2}),
    )
    .await;

    let home = TestHome::new();
    login(&home, "photos", &alice_email, &["--host", &origin]);
    let initial = home.read_vault();
    let first_id = initial["accounts"][0]["storage_id"].clone();
    assert_eq!(initial["accounts"][0]["name"], alice_email);
    let albums = home.json(&["photos", "album", "list"]);
    let mut listed: Vec<_> = albums
        .as_array()
        .unwrap()
        .iter()
        .map(|a| {
            (
                a["name"].as_str().unwrap(),
                a["visibility"].as_str().unwrap(),
            )
        })
        .collect();
    listed.sort();
    let expected = [
        ("Archive", "archived"),
        ("Default hidden", "hidden"),
        ("Monsoon 🌧", "visible"),
        ("Private album", "hidden"),
    ];
    assert_eq!(listed, expected);
    let monsoon = albums
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["name"] == "Monsoon 🌧")
        .unwrap();
    assert_eq!(monsoon["id"], album.to_string());
    assert_eq!(monsoon["ownerId"], alice_id);
    assert_eq!(monsoon["type"], "album");
    assert_eq!(
        chrono::DateTime::parse_from_rfc3339(monsoon["updatedAt"].as_str().unwrap())
            .unwrap()
            .offset()
            .local_minus_utc(),
        0
    );
    let human = String::from_utf8(success(home.run(&["photos", "album", "list"])).stdout).unwrap();
    assert!(human.starts_with("ID  "));
    let raw: Value =
        serde_json::from_slice(&success(home.run(&["photos", "api", "/collections/v2"])).stdout)
            .unwrap();
    assert!(raw["collections"].as_array().unwrap().iter().any(|a| a["id"] == album && a["encryptedName"].as_str().is_some_and(|s| !s.is_empty())));

    // Two origins with the same server user ID are still different accounts.
    let alias_origin = origin.replace("127.0.0.1", "localhost");
    assert_ne!(alias_origin, origin);
    let before = fs::read(home.dir.path().join("vault.json")).unwrap();
    assert!(
        failure(&home.with_input(
            &["photos", "login", "--host", &alias_origin, "--input", "-"],
            &credentials(&alice_email),
        ))
        .contains("already in use")
    );
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        before
    );
    login(
        &home,
        "photos",
        &alice_email,
        &["--host", &alias_origin, "--name", "other-server"],
    );
    success(home.run(&["account", "rename", &alice_email, "work"]));
    assert_eq!(home.read_vault()["accounts"][0]["storage_id"], first_id);

    login(&home, "auth", &bob_email, &["--host", &origin]);
    assert!(failure(&home.run(&["photos", "album", "list"])).contains("no photos session"));
    login(&home, "locker", &alice_email, &["--account", "work"]);
    let accounts = home.json(&["account", "list"]);
    assert!(
        accounts
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["name"] == bob_email && a["selected"] == true)
    );
    assert!(
        accounts
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["name"] == "work" && a["products"] == json!(["photos", "locker"]))
    );

    login(&home, "photos", &bob_email, &["--account", &bob_email]);
    let albums = home.json(&["photos", "album", "list"]);
    let mut ids: Vec<_> = albums
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["id"].as_str().unwrap().to_owned())
        .collect();
    ids.sort();
    let mut expected = vec![album.to_string(), bob_album.to_string()];
    expected.sort();
    assert_eq!(ids, expected);
    let shared = albums
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["id"] == monsoon["id"])
        .unwrap();
    assert_eq!(shared["name"], "Monsoon 🌧");
    assert_eq!(shared["ownerId"], alice_id);
    assert_eq!(shared["visibility"], "hidden");

    login(&home, "photos", &alice_email, &["--host", &origin]);
    let state = home.read_vault();
    assert_eq!(state["accounts"].as_array().unwrap().len(), 3);
    assert_eq!(state["selected"], first_id);
    assert_eq!(state["accounts"][0]["name"], "work");
    assert!(!serde_json::to_string(&state).unwrap().contains(PASSWORD));
    let before = fs::read(home.dir.path().join("vault.json")).unwrap();
    assert!(
        failure(&home.with_input(
            &["photos", "login", "--account", "work", "--input", "-"],
            &credentials(&bob_email),
        ))
        .contains("identity does not match")
    );
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        before
    );

    let token: Vec<u8> =
        serde_json::from_value(state["accounts"][0]["sessions"]["photos"]["token"].clone())
            .unwrap();
    success(home.run(&["photos", "logout"]));
    let response = reqwest::Client::new()
        .get(format!("{origin}/collections/v2"))
        .header("x-auth-token", b64::encode_url_safe(&token))
        .header("x-client-package", "io.ente.photos")
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
    failure(&home.run(&["photos", "album", "list"]));
    assert_eq!(
        home.json(&["account", "view", "work"])["products"],
        json!(["locker"])
    );

    for entry in fs::read_dir(home.dir.path()).unwrap() {
        let entry = entry.unwrap();
        let bytes = fs::read(entry.path()).unwrap();
        assert!(
            !bytes
                .windows(alice_email.len())
                .any(|b| b == alice_email.as_bytes())
        );
        assert!(
            !bytes
                .windows(PASSWORD.len())
                .any(|b| b == PASSWORD.as_bytes())
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(entry.metadata().unwrap().permissions().mode() & 0o077, 0);
        }
    }
    Ok(())
}

fn login(home: &TestHome, product: &str, email: &str, options: &[&str]) {
    let mut args = vec![product, "login", "--input", "-", "--json"];
    args.extend_from_slice(options);
    let output = success(home.with_input(&args, &credentials(email)));
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["product"], product);
}

fn credentials(email: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({"email": email, "password": PASSWORD, "otp": HARDCODED_OTT}))
        .unwrap()
}

async fn create_account(origin: &str, email: &str) -> AuthenticatedAccount {
    let client =
        AccountsClient::new(AccountsClientConfig::new("io.ente.photos").with_origin(origin))
            .unwrap();
    client.send_otp(email, "signup").await.unwrap();
    AuthFlow::new(&client, &mut NoPrompts)
        .create_account_with_otp(
            CreateAccountParams {
                email: email.into(),
                password: Zeroizing::new(PASSWORD.into()),
                source: Some("testAccount".into()),
            },
            HARDCODED_OTT,
        )
        .await
        .unwrap()
}

#[cfg(unix)]
async fn session_count(origin: &str, owner: &AuthenticatedAccount) -> usize {
    let body: Value = reqwest::Client::new()
        .get(format!("{origin}/users/sessions"))
        .header("x-auth-token", b64::encode_url_safe(&owner.secrets.token))
        .header("x-client-package", "io.ente.photos")
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    body["sessions"].as_array().unwrap().len()
}

async fn create_album(
    origin: &str,
    owner: &AuthenticatedAccount,
    name: &str,
    kind: &str,
) -> (i64, Key) {
    let key = Key::generate();
    let wrapped = secretbox::encrypt(
        key.as_bytes(),
        &Key::try_from_slice(&owner.secrets.master_key).unwrap(),
    );
    let encrypted_name = secretbox::encrypt(name.as_bytes(), &key);
    let response: Value = reqwest::Client::new().post(format!("{origin}/collections"))
        .header("x-auth-token", b64::encode_url_safe(&owner.secrets.token)).header("x-client-package", "io.ente.photos")
        .json(&json!({
            "encryptedKey": b64::encode(&wrapped.encrypted_data), "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
            "name": "", "encryptedName": b64::encode(&encrypted_name.encrypted_data),
            "nameDecryptionNonce": b64::encode(encrypted_name.nonce.as_bytes()), "type": kind, "attributes": {"version": 1}
        })).send().await.unwrap().error_for_status().unwrap().json().await.unwrap();
    (response["collection"]["id"].as_i64().unwrap(), key)
}

async fn set_album_metadata(
    origin: &str,
    user: &AuthenticatedAccount,
    album: i64,
    key: &Key,
    metadata_kind: &str,
    data: Value,
) {
    let metadata = blob::encrypt_json(&data, key).unwrap();
    reqwest::Client::new()
        .put(format!("{origin}/collections/{metadata_kind}"))
        .header("x-auth-token", b64::encode_url_safe(&user.secrets.token))
        .header("x-client-package", "io.ente.photos")
        .json(&json!({"id": album, "magicMetadata": {
            "version": 1, "count": data.as_object().unwrap().len(),
            "data": b64::encode(&metadata.encrypted_data),
            "header": b64::encode(metadata.decryption_header.as_bytes())
        }}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
}

struct NoPrompts;

impl AuthFlowUi for NoPrompts {
    fn read_email_otp(&mut self, _: &str, _: OtpPurpose, _: bool) -> ente_accounts::Result<String> {
        unreachable!()
    }
    fn read_totp_code(&mut self, _: TotpPurpose) -> ente_accounts::Result<String> {
        unreachable!()
    }
    fn report_retryable_error(&mut self, _: &str) -> ente_accounts::Result<()> {
        unreachable!()
    }
    fn choose_second_factor(
        &mut self,
        _: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        unreachable!()
    }
    fn present_passkey_verification(&mut self, _: &str) -> ente_accounts::Result<()> {
        unreachable!()
    }
    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        unreachable!()
    }
    fn present_totp_secret(&mut self, _: &str, _: &str) -> ente_accounts::Result<()> {
        unreachable!()
    }
}
