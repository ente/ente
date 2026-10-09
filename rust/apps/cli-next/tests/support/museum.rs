use ente_accounts::{AccountsClient, AccountsClientConfig, AuthenticatedAccount, signup::Signup};
use ente_core::{
    crypto::{PublicKey, blob, sealed, secretbox, stream},
    io::Md5Writer,
};
use ente_test_support::{HARDCODED_OTT, Museum, TestResult};
use uuid::Uuid;

use super::*;

const PASSWORD: &str = "disposable-cli-integration-password";

#[test]
fn login_and_photos_across_processes() -> TestResult {
    Museum::run_async(exercise)
}

#[test]
fn auth_login_refresh_and_offline_export_across_processes() -> TestResult {
    Museum::run_async(|origin| async move {
        let email = format!("auth-export-{}@example.org", Uuid::new_v4());
        let owner = create_account(&origin, &email).await;
        let home = TestHome::new();
        login(&home, "auth", &email, &["--host", &origin, "--no-input"]);
        let export = ["auth", "export", "--output", "-", "--plaintext"];
        assert!(success(home.run(&export)).stdout.is_empty());
        let key = Key::generate();
        let wrapped = secretbox::encrypt(
            key.as_bytes(),
            &Key::try_from_slice(&owner.secrets.master_key).unwrap(),
        );
        let body = home.dir.path().join("request.json");
        fs::write(&body, serde_json::to_vec(&json!({"encryptedKey": b64::encode(&wrapped.encrypted_data), "header": b64::encode(wrapped.nonce.as_bytes())})).unwrap()).unwrap();
        success(home.run(&[
            "auth",
            "api",
            "/authenticator/key",
            "--method",
            "POST",
            "--body",
            body.to_str().unwrap(),
        ]));
        let uri = "otpauth://hotp/Museum?secret=JBSWY3DPEHPK3PXP&counter=17";
        let encrypted = blob::encrypt_json(&uri, &key).unwrap();
        fs::write(&body, serde_json::to_vec(&json!({"encryptedData": b64::encode(&encrypted.encrypted_data), "header": b64::encode(encrypted.decryption_header.as_bytes())})).unwrap()).unwrap();
        let created = home.json(&[
            "auth",
            "api",
            "/authenticator/entity",
            "--method",
            "POST",
            "--body",
            body.to_str().unwrap(),
        ]);
        assert_eq!(
            success(home.run(&export)).stdout,
            format!("{uri}\n").as_bytes()
        );
        let changed = format!("{uri}&codeDisplay=%7B%22trashed%22%3Atrue%7D");
        let encrypted = blob::encrypt_json(&changed, &key).unwrap();
        fs::write(&body, serde_json::to_vec(&json!({"id": created["id"], "encryptedData": b64::encode(&encrypted.encrypted_data), "header": b64::encode(encrypted.decryption_header.as_bytes())})).unwrap()).unwrap();
        success(home.run(&[
            "auth",
            "api",
            "/authenticator/entity",
            "--method",
            "PUT",
            "--body",
            body.to_str().unwrap(),
        ]));
        assert_eq!(
            success(home.run(&export)).stdout,
            format!("{changed}\n").as_bytes()
        );
        assert_eq!(
            success(home.command(&export).arg("--offline").output().unwrap()).stdout,
            format!("{changed}\n").as_bytes()
        );
        success(home.run(&[
            "auth",
            "api",
            "/authenticator/entity",
            "--method",
            "DELETE",
            "--query",
            &format!("id={}", created["id"].as_str().unwrap()),
        ]));
        assert!(success(home.run(&export)).stdout.is_empty());
        Ok(())
    })
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
    let original = b"original photo bytes from Museum";
    let file_id = upload_file(&origin, &alice, album, &key, original, Some(0))
        .await
        .to_string();

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
        ("Hidden", "hidden"),
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
    assert_eq!(monsoon["type"], "folder");
    assert_eq!(
        chrono::DateTime::parse_from_rfc3339(monsoon["updatedAt"].as_str().unwrap())
            .unwrap()
            .offset()
            .local_minus_utc(),
        0
    );
    for album in albums.as_array().unwrap() {
        for selector in [
            album["id"].as_str().unwrap(),
            album["name"].as_str().unwrap(),
        ] {
            assert_eq!(home.json(&["photos", "album", "view", selector]), *album);
        }
    }
    assert_eq!(
        String::from_utf8(success(home.run(&["photos", "album", "view", "Monsoon 🌧"])).stdout)
            .unwrap(),
        format!(
            "Name        Monsoon 🌧\nType        folder\nVisibility  visible\nOwner       {alice_id}\nUpdated     {}\nID          {album}\n",
            monsoon["updatedAt"].as_str().unwrap(),
        ),
    );
    for selector in ["missing", "Monsoon", "monsoon 🌧"] {
        let output = home.run(&["photos", "album", "view", selector, "--json"]);
        assert!(failure(&output).contains("no album matches"));
        assert!(output.stdout.is_empty());
    }
    let human = String::from_utf8(success(home.run(&["photos", "album", "list"])).stdout).unwrap();
    assert!(human.starts_with("ID  "));
    let raw: Value =
        serde_json::from_slice(&success(home.run(&["photos", "api", "/collections/v2"])).stdout)
            .unwrap();
    assert!(raw["collections"].as_array().unwrap().iter().any(|a| a["id"] == album && a["encryptedName"].as_str().is_some_and(|s| !s.is_empty())));
    let files = home.json(&["photos", "file", "list"]);
    assert_eq!(files.as_array().unwrap().len(), 1);
    assert_eq!(files[0]["id"], file_id);
    assert_eq!(files[0]["name"], "original.jpg");
    assert_eq!(files[0]["type"], "image");
    assert_eq!(files[0]["albumIds"], json!([album.to_string()]));
    let output_dir = tempfile::tempdir().unwrap();
    let output_path = output_dir.path().join("owned.jpg");
    success(home.run(&[
        "photos",
        "file",
        "download",
        &file_id,
        "--output",
        output_path.to_str().unwrap(),
    ]));
    assert_eq!(fs::read(output_path).unwrap(), original);

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
    assert_eq!(
        home.json(&["photos", "album", "view", "Monsoon 🌧"]),
        *shared
    );
    assert_eq!(
        home.json(&["photos", "album", "view", "Monsoon 🌧", "--account", "work"]),
        *monsoon,
    );
    let shared_file = home.json(&["photos", "file", "view", &file_id]);
    assert_eq!(shared_file["ownerId"], alice_id);
    let shared_export = output_dir.path().join("shared-export");
    home.json(&[
        "photos",
        "export",
        shared_export.to_str().unwrap(),
        "--album",
        "Monsoon 🌧",
    ]);
    let album_record: Value =
        serde_json::from_slice(&fs::read(shared_export.join("Monsoon 🌧/metadata.json")).unwrap())
            .unwrap();
    assert_eq!(album_record["ente"]["visibility"], "hidden");
    let shared_sidecar = shared_export.join("Monsoon 🌧/metadata/original.jpg.json");
    let file_record: Value = serde_json::from_slice(&fs::read(&shared_sidecar).unwrap()).unwrap();
    assert!(file_record["ente"].get("visibility").is_none());
    let adopted = TestHome::new();
    adopted.write_vault(&home.read_vault());
    let shared_original = shared_export.join("Monsoon 🌧/original.jpg");
    fs::write(&shared_original, vec![0; original.len()]).unwrap();
    let output = adopted.run(&[
        "photos",
        "export",
        shared_export.to_str().unwrap(),
        "--adopt",
    ]);
    assert!(failure(&output).contains("locally changed media"));
    assert_eq!(fs::read(&shared_original).unwrap(), vec![0; original.len()]);
    fs::remove_file(&shared_original).unwrap();
    adopted.json(&[
        "photos",
        "export",
        shared_export.to_str().unwrap(),
        "--adopt",
    ]);
    assert_eq!(
        fs::read(shared_export.join("Monsoon 🌧/original.jpg")).unwrap(),
        original
    );
    let output_path = output_dir.path().join("shared.jpg");
    success(home.run(&[
        "photos",
        "file",
        "download",
        &file_id,
        "--output",
        output_path.to_str().unwrap(),
    ]));
    assert_eq!(fs::read(output_path).unwrap(), original);

    reqwest::Client::new()
        .post(format!("{origin}/collections/unshare"))
        .header("x-auth-token", b64::encode_url_safe(&alice.secrets.token))
        .header("x-client-package", "io.ente.photos")
        .json(&json!({"collectionID":album,"email":bob_email}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    adopted.json(&[
        "photos",
        "export",
        shared_export.to_str().unwrap(),
        "--exclude-album",
        &album.to_string(),
    ]);
    assert_eq!(
        fs::read(shared_export.join("Monsoon 🌧/original.jpg")).unwrap(),
        original
    );
    let revoked = adopted.json(&[
        "photos",
        "export",
        shared_export.to_str().unwrap(),
        "--album",
        &album.to_string(),
    ]);
    assert_eq!(revoked["copies"]["expected"], 0);
    assert_eq!(revoked["changes"]["retained"], 1);
    assert!(!shared_export.join("Monsoon 🌧/original.jpg").exists());
    assert_eq!(
        fs::read(shared_export.join("Trash/Monsoon 🌧/original.jpg")).unwrap(),
        original
    );
    let retained_record: Value = serde_json::from_slice(
        &fs::read(shared_export.join("Trash/Monsoon 🌧/metadata/original.jpg.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(retained_record["ente"]["fileID"], file_id);
    assert_eq!(
        adopted.json(&[
            "photos",
            "export",
            shared_export.to_str().unwrap(),
            "--album",
            &album.to_string()
        ])["changes"]["retained"],
        0
    );

    login(&home, "photos", &alice_email, &["--host", &origin]);
    let added_original = b"added after the first sync";
    let added_file = upload_file(&origin, &alice, album, &key, added_original, None)
        .await
        .to_string();
    assert_eq!(home.json(&["photos", "file", "list", "--offline"]), files);
    let refreshed = home.json(&["photos", "file", "list", "--all"]);
    assert_eq!(refreshed.as_array().unwrap().len(), 2);
    let added = refreshed
        .as_array()
        .unwrap()
        .iter()
        .find(|file| file["id"] == added_file)
        .unwrap();
    assert_eq!(added["type"], "unknown");
    assert_eq!(home.json(&["photos", "file", "view", &added_file]), *added);
    assert_eq!(
        home.json(&["photos", "file", "list", "--offline", "--all"]),
        refreshed
    );
    assert_eq!(
        home.json(&["photos", "file", "list", "--offline", "--limit", "1"]),
        json!([refreshed[0]])
    );
    let output_path = output_dir.path().join("unknown-type");
    success(home.run(&[
        "photos",
        "file",
        "download",
        &added_file,
        "--output",
        output_path.to_str().unwrap(),
    ]));
    assert_eq!(fs::read(output_path).unwrap(), added_original);

    for selector in ["Monsoon 🌧", &album.to_string()] {
        let (conflict, _) = create_album(&origin, &alice, selector, "album").await;
        let output = home.run(&["photos", "album", "view", selector, "--json"]);
        let error = failure(&output);
        assert!(error.contains("is ambiguous"));
        assert!(error.contains(&format!("{album}  \"Monsoon 🌧\"")));
        assert!(error.contains(&format!("{conflict}  {selector:?}")));
        assert!(output.stdout.is_empty());
        let ambiguous_export = output_dir.path().join("ambiguous-export");
        let output = home.run(&[
            "photos",
            "export",
            ambiguous_export.to_str().unwrap(),
            "--album",
            selector,
            "--json",
        ]);
        assert!(failure(&output).contains("is ambiguous"));
        assert!(output.stdout.is_empty());
        assert!(!ambiguous_export.exists());
        assert_eq!(
            home.json(&["photos", "album", "view", &conflict.to_string()])["id"],
            conflict.to_string(),
        );
    }
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
    let account_dir = home
        .dir
        .path()
        .join("accounts")
        .join(first_id.as_str().unwrap());
    assert!(account_dir.join("data.db").is_file());
    success(home.run(&["account", "logout", "work", "--local"]));
    assert!(!account_dir.exists());
    assert!(!account_dir.with_extension("lock").exists());

    for entry in fs::read_dir(home.dir.path()).unwrap() {
        let entry = entry.unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(entry.metadata().unwrap().permissions().mode() & 0o077, 0);
        }
        if entry.file_type().unwrap().is_dir() {
            continue;
        }
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
    let response = client
        .verify_email(email, HARDCODED_OTT, Some("testAccount"))
        .await
        .unwrap();
    Signup::verified(email.into(), response)
        .unwrap()
        .prepare(&client, PASSWORD)
        .await
        .unwrap()
        .finish(&client)
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

async fn upload_file(
    origin: &str,
    owner: &AuthenticatedAccount,
    album: i64,
    collection_key: &Key,
    original: &[u8],
    file_type: Option<i32>,
) -> i64 {
    let mut metadata = json!({"title":"original.jpg","creationTime":1_700_000_000_000_000i64,"modificationTime":1_700_000_000_000_000i64});
    if let Some(kind) = file_type {
        metadata["fileType"] = json!(kind);
    }
    upload_fixture(origin, owner, album, collection_key, original, metadata)
        .await
        .0
}

async fn upload_fixture(
    origin: &str,
    owner: &AuthenticatedAccount,
    album: i64,
    collection_key: &Key,
    original: &[u8],
    metadata: Value,
) -> (i64, Key) {
    upload_reader(origin, owner, album, collection_key, original, metadata).await
}

async fn upload_reader(
    origin: &str,
    owner: &AuthenticatedAccount,
    album: i64,
    collection_key: &Key,
    mut original: impl std::io::Read,
    metadata: Value,
) -> (i64, Key) {
    let client = reqwest::Client::new();
    let token = b64::encode_url_safe(&owner.secrets.token);
    let key = Key::generate();
    let wrapped = secretbox::encrypt(key.as_bytes(), collection_key);
    let mut encrypted = Md5Writer::new(tempfile::tempfile().unwrap());
    let header = stream::encrypt_file(&mut original, &mut encrypted, &key).unwrap();
    let (mut encrypted, checksum) = encrypted.finalize();
    std::io::Seek::rewind(&mut encrypted).unwrap();
    let thumbnail = blob::encrypt(b"thumbnail", &key).unwrap();
    let mut object_keys = Vec::new();
    let mut thumbnail_checksum = Md5Writer::new(std::io::sink());
    thumbnail_checksum
        .write_all(&thumbnail.encrypted_data)
        .unwrap();
    let objects: [(Box<dyn std::io::Read + Send>, u64, String); 2] = [
        (
            Box::new(encrypted.try_clone().unwrap()),
            encrypted.metadata().unwrap().len(),
            b64::encode(&checksum),
        ),
        (
            Box::new(std::io::Cursor::new(thumbnail.encrypted_data.clone())),
            thumbnail.encrypted_data.len() as u64,
            b64::encode(&thumbnail_checksum.finalize().1),
        ),
    ];
    for (bytes, size, checksum) in objects {
        let upload: Value = client
            .post(format!("{origin}/files/upload-url"))
            .header("x-auth-token", &token)
            .header("x-client-package", "io.ente.photos")
            .json(&json!({"contentLength": size, "contentMD5": checksum}))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap()
            .json()
            .await
            .unwrap();
        let body = futures_util::stream::try_unfold(bytes, |mut input| async move {
            let mut chunk = vec![0; 64 * 1024];
            let count = input.read(&mut chunk)?;
            chunk.truncate(count);
            Ok::<_, std::io::Error>((count > 0).then_some((chunk, input)))
        });
        client
            .put(upload["url"].as_str().unwrap())
            .header("content-md5", checksum)
            .header("content-length", size)
            .body(reqwest::Body::wrap_stream(body))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
        object_keys.push(upload["objectKey"].as_str().unwrap().to_owned());
    }
    let metadata = blob::encrypt_json(&metadata, &key).unwrap();
    let result: Value = client.post(format!("{origin}/files"))
        .header("x-auth-token", &token).header("x-client-package", "io.ente.photos")
        .json(&json!({
            "collectionID": album, "encryptedKey": b64::encode(&wrapped.encrypted_data),
            "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
            "file": {"objectKey": object_keys[0], "decryptionHeader": b64::encode(header.as_bytes())},
            "thumbnail": {"objectKey": object_keys[1], "decryptionHeader": b64::encode(thumbnail.decryption_header.as_bytes())},
            "metadata": {"encryptedData": b64::encode(&metadata.encrypted_data),
                "decryptionHeader": b64::encode(metadata.decryption_header.as_bytes())}
        })).send().await.unwrap().error_for_status().unwrap().json().await.unwrap();
    (result["id"].as_i64().unwrap(), key)
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

#[path = "export.rs"]
mod export;
