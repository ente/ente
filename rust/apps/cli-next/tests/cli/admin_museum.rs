use std::{
    io::{BufRead, BufReader},
    net::{TcpListener, TcpStream},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::Duration,
};

use chrono::{Months, Utc};
use ente_accounts::{AccountsClient, AccountsClientConfig, TwoFactorSetup};
use ente_test_support::{Museum, TestResult, account_fixture::current_totp};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use super::{
    museum::{create_account, login},
    *,
};

#[test]
fn admin_user_lifecycle() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let admin_email = format!("admin-{}@example.org", Uuid::new_v4());
            let email = format!("managed-{}@example.org", Uuid::new_v4());
            let admin = create_account(origin, &admin_email).await;
            let user = create_account(origin, &email).await;
            let home = TestHome::new();
            login(
                &home,
                "photos",
                &admin_email,
                &["--host", origin, "--no-input"],
            );
            let id = user.user_id.to_string();
            let users = home.json(&["admin", "user", "list", "--all", "--no-input"]);
            assert!(
                users
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|item| item["id"] == id)
            );
            let view = ["admin", "user", "view", id.as_str()];
            let before = home.json(&view);
            assert_eq!(before["email"], email);
            let admin_token = b64::encode_url_safe(&admin.secrets.token);
            let original = api_json(origin, &admin_token, "GET", &format!("/admin/user?id={id}"), None).await;
            api_json(origin, &admin_token, "PUT", "/admin/user/subscription", Some(json!({
                "userID": user.user_id, "productID": "free", "storage": original["subscription"]["storage"],
                "expiryTime": original["subscription"]["expiryTime"], "transactionID": "fixture",
                "paymentProvider": "", "attributes": {"isCancelled": true}
            }))).await;
            assert_eq!(home.json(&["admin", "user", "view", &email]), before);
            assert_eq!(
                home.json(&["admin", "user", "list", "--limit", "1"])
                    .as_array()
                    .unwrap()
                    .len(),
                1
            );
            assert_eq!(
                home.json(&[
                    "admin",
                    "user",
                    "list",
                    "--since",
                    before["createdAt"].as_str().unwrap()
                ]),
                json!([])
            );
            let update = [
                "admin",
                "user",
                "update-subscription",
                email.as_str(),
                "--yes",
                "--no-input",
            ];
            let sized = home.json(&[update.as_slice(), &["--storage", "500GB"]].concat());
            assert_eq!(sized["subscription"]["storageBytes"], 500 * 1024_i64.pow(3));
            assert_eq!(
                sized["subscription"]["expiresAt"],
                before["subscription"]["expiresAt"]
            );
            assert_eq!(home.json(&view), sized);
            let dated = home.json(&[update.as_slice(), &["--expires", "2035-01-01"]].concat());
            assert_eq!(
                dated["subscription"]["storageBytes"],
                sized["subscription"]["storageBytes"]
            );
            assert_eq!(
                dated["subscription"]["expiresAt"],
                "2035-01-01T00:00:00.000000Z"
            );
            assert_eq!(home.json(&view), dated);
            let persisted = api_json(origin, &admin_token, "GET", &format!("/admin/user?id={id}"), None).await;
            assert_eq!(persisted["subscription"]["originalTransactionID"], "fixture");
            assert_eq!(persisted["subscription"]["paymentProvider"], "");
            assert_eq!(persisted["subscription"]["attributes"]["isCancelled"], true);
            let lower = Utc::now().checked_add_months(Months::new(1200)).unwrap();
            let unlimited = home.json(&[update.as_slice(), &["--no-limit"]].concat());
            let upper = Utc::now().checked_add_months(Months::new(1200)).unwrap();
            let expires = chrono::DateTime::parse_from_rfc3339(
                unlimited["subscription"]["expiresAt"].as_str().unwrap(),
            )
            .unwrap();
            assert!(
                (lower.timestamp_micros()..=upper.timestamp_micros())
                    .contains(&expires.timestamp_micros())
            );
            assert_eq!(
                unlimited["subscription"]["storageBytes"],
                100 * 1024_i64.pow(4)
            );
            assert_eq!(home.json(&view), unlimited);
            let changed = success(
                home.run(
                    &[
                        update.as_slice(),
                        &[
                            "--storage",
                            "1.5GB",
                            "--expires",
                            "2035-01-01T05:30:00+05:30",
                        ],
                    ]
                    .concat(),
                ),
            );
            let preview = String::from_utf8(changed.stderr).unwrap();
            assert!(
                preview.contains("100 TB (109951162777600 bytes) -> 1.5 GB (1610612736 bytes)"),
                "{preview}"
            );
            let rendered = String::from_utf8(changed.stdout).unwrap();
            assert!(rendered.contains("1.5 GB (1610612736 bytes)"), "{rendered}");
            assert_eq!(
                home.json(&view)["subscription"]["expiresAt"],
                "2035-01-01T00:00:00.000000Z"
            );

            for command in ["delete", "disable-totp", "remove-passkeys"] {
                let output = home.run(&["admin", "user", command, &email, "--no-input"]);
                assert!(failure(&output).contains("supply --yes"));
                assert!(output.stdout.is_empty());
            }
            assert!(
                failure(&home.run(&["admin", "user", "list", "--offline"]))
                    .contains("require network")
            );

            let client = AccountsClient::new(
                AccountsClientConfig::new("io.ente.photos").with_origin(origin),
            )?;
            client.set_auth_token(Some(b64::encode_url_safe(&admin.secrets.token)));
            let mut subscription = client.admin_user(&id).await?.subscription.unwrap();
            subscription.product_id = "paid".into();
            client
                .admin_update_subscription(user.user_id, &subscription)
                .await?;
            assert!(
                failure(&home.run(&[update.as_slice(), &["--storage", "2GB"]].concat()))
                    .contains("not on a free plan")
            );
            assert_eq!(home.json(&view)["subscription"]["productId"], "paid");
            subscription.product_id = "free".into();
            client
                .admin_update_subscription(user.user_id, &subscription)
                .await?;

            let missing = create_account(origin, &format!("missing-{}@example.org", Uuid::new_v4())).await;
            let missing_id = missing.user_id.to_string();
            museum.execute_sql(&format!("DELETE FROM subscriptions WHERE user_id = {missing_id}"))?;
            assert_eq!(home.json(&["admin", "user", "view", &missing_id])["subscription"], Value::Null);
            assert!(failure(&home.run(&["admin", "user", "update-subscription", &missing_id, "--no-limit", "--yes", "--no-input"])).contains("did not return a subscription"));

            for app in ["auth", "locker"] {
                login(&home, app, &admin_email, &["--host", origin, "--no-input"]);
            }
            let saved = home.read_vault();
            for (apps, expected, explicit) in [
                (vec!["auth"], "auth", None),
                (vec!["locker"], "locker", None),
                (vec!["photos", "auth", "locker"], "photos", None),
                (vec!["auth", "locker"], "auth", Some("auth")),
            ] {
                let mut state = saved.clone();
                let sessions = state["accounts"][0]["sessions"].as_object_mut().unwrap();
                sessions.retain(|app, _| apps.contains(&app.as_str()));
                for (app, session) in sessions {
                    if app != expected {
                        session["token"] = json!(vec![0; 32]);
                    }
                }
                home.write_vault(&state);
                let mut args = vec!["admin", "user", "view", &id];
                if let Some(app) = explicit {
                    args.extend(["--app", app]);
                }
                assert_eq!(home.json(&args)["id"], id);
            }
            assert!(failure(&home.run(&view)).contains("select one with --app"));
            home.write_vault(&saved);
            let ordinary = TestHome::new();
            login(
                &ordinary,
                "photos",
                &email,
                &["--host", origin, "--no-input"],
            );
            let error = failure(&ordinary.run(&["admin", "user", "list", "--no-input"]));
            assert!(error.contains("HTTP 401"));
            assert!(!error.contains("account login"));
            museum.execute_sql(&format!(
                "UPDATE tokens SET creation_time = creation_time - 660000000 WHERE user_id = {}",
                admin.user_id
            ))?;
            for args in [
                vec!["list"],
                vec!["delete", &email, "--yes"],
                vec!["disable-totp", &id, "--yes"],
            ] {
                let output =
                    home.run(&[&["admin", "user"][..], args.as_slice(), &["--no-input"]].concat());
                let error = failure(&output);
                assert!(
                    error.contains("HTTP 400") && error.contains("account login"),
                    "{error}"
                );
                assert!(output.stdout.is_empty());
            }
            assert_eq!(
                home.json(&["admin", "user", "view", &admin_email])["id"],
                admin.user_id.to_string()
            );
            login(&home, "photos", &admin_email, &["--host", origin, "--no-input"]);
            let deleted = home.json(&["admin", "user", "delete", &email, "--yes", "--no-input"]);
            assert_eq!(deleted["user"]["id"], id);
            assert_eq!(deleted["user"]["email"], email);
            assert_eq!(deleted["cleanupScheduled"], true);
            assert_eq!(deleted["subscriptionCancelled"], true);
            assert!(failure(&home.run(&view)).contains("HTTP 404"));
            assert!(
                !home
                    .json(&["admin", "user", "list", "--all"])
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|item| item["id"] == id)
            );
            Ok(())
        })
    })
}

#[cfg(unix)]
#[test]
fn admin_interactive_subscription() -> TestResult {
    Museum::run_async(|origin| async move {
        let admin_email = format!("admin-{}@example.org", Uuid::new_v4());
        let email = format!("interactive-{}@example.org", Uuid::new_v4());
        create_account(&origin, &admin_email).await;
        create_account(&origin, &email).await;
        let home = TestHome::new();
        login(
            &home,
            "photos",
            &admin_email,
            &["--host", &origin, "--no-input"],
        );
        for mode in ["decline", "preset", "storage", "expiry", "empty"] {
            let before = home.json(&["admin", "user", "view", &email]);
            let output = Command::new("python3")
                .env_clear()
                .args([
                    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/cli/admin_prompt.py"),
                    env!("CARGO_BIN_EXE_ente-cli-next"),
                    &email,
                    mode,
                ])
                .env("ENTE_CLI_HOME", home.dir.path())
                .env("ENTE_CLI_VAULT_KEY", b64::encode(home.key.as_bytes()))
                .output()?;
            assert!(
                output.status.success(),
                "{mode}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            let after = home.json(&["admin", "user", "view", &email]);
            match mode {
                "decline" | "empty" => assert_eq!(after, before),
                "preset" => {
                    assert_eq!(after["subscription"]["storageBytes"], 100 * 1024_i64.pow(4))
                }
                "storage" => {
                    assert_eq!(after["subscription"]["storageBytes"], 1572864);
                    assert_eq!(
                        after["subscription"]["expiresAt"],
                        before["subscription"]["expiresAt"]
                    );
                }
                "expiry" => {
                    assert_eq!(
                        after["subscription"]["storageBytes"],
                        before["subscription"]["storageBytes"]
                    );
                    assert_eq!(
                        after["subscription"]["expiresAt"],
                        "2035-01-01T00:00:00.000000Z"
                    );
                }
                _ => unreachable!(),
            }
        }
        Ok(())
    })
}

#[test]
fn admin_security_resets() -> TestResult {
    Museum::run_async(|origin| async move {
        let admin_email = format!("admin-{}@example.org", Uuid::new_v4());
        let email = format!("security-{}@example.org", Uuid::new_v4());
        create_account(&origin, &admin_email).await;
        let user = create_account(&origin, &email).await;
        let home = TestHome::new();
        login(
            &home,
            "photos",
            &admin_email,
            &["--host", &origin, "--no-input"],
        );
        let client =
            AccountsClient::new(AccountsClientConfig::new("io.ente.photos").with_origin(&origin))?;
        client.set_auth_token(Some(b64::encode_url_safe(&user.secrets.token)));
        let setup =
            TwoFactorSetup::start(&client, &user.secrets.master_key, &user.key_attributes).await?;
        setup
            .enable(&client, &current_totp(&setup.secret_code)?)
            .await?;
        assert!(client.get_two_factor_status().await?);
        let token = api_json(
            &origin,
            &b64::encode_url_safe(&user.secrets.token),
            "GET",
            "/users/accounts-token",
            None,
        )
        .await;
        let token = token["accountsToken"].as_str().unwrap();
        for _ in 0..2 {
            register_passkey(&origin, token).await;
        }
        assert_eq!(
            api_json(&origin, token, "GET", "/passkeys", None).await["passkeys"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        home.json(&[
            "admin",
            "user",
            "remove-passkeys",
            &email,
            "--yes",
            "--no-input",
        ]);
        assert!(api_json(&origin, token, "GET", "/passkeys", None).await["passkeys"].is_null());
        assert!(client.get_two_factor_status().await?);
        register_passkey(&origin, token).await;
        assert_eq!(
            home.json(&[
                "admin",
                "user",
                "disable-totp",
                &email,
                "--yes",
                "--no-input"
            ])["totpEnabled"],
            false
        );
        assert!(!client.get_two_factor_status().await?);
        assert_eq!(
            api_json(&origin, token, "GET", "/passkeys", None).await["passkeys"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        home.json(&[
            "admin",
            "user",
            "remove-passkeys",
            &email,
            "--yes",
            "--no-input",
        ]);
        let cleared = TestHome::new();
        login(
            &cleared,
            "photos",
            &email,
            &["--host", &origin, "--no-input"],
        );
        Ok(())
    })
}

#[test]
fn admin_email_reaches_smtp() -> TestResult {
    for override_sender in [false, true] {
        let inbox = MailInbox::new();
        let port = inbox.port.to_string();
        Museum::run_with_env(
            &[
                ("ENTE_SMTP_HOST", "127.0.0.1"),
                ("ENTE_SMTP_PORT", &port),
                ("ENTE_SMTP_USERNAME", ""),
                ("ENTE_SMTP_PASSWORD", ""),
                ("ENTE_SMTP_ENCRYPTION", ""),
                (
                    "ENTE_SMTP_EMAIL",
                    if override_sender {
                        "override@example.org"
                    } else {
                        ""
                    },
                ),
                (
                    "ENTE_SMTP_SENDER_NAME",
                    if override_sender { "Server sender" } else { "" },
                ),
            ],
            |museum| {
                tokio::runtime::Runtime::new()?.block_on(async {
                    let email = format!("admin-{}@example.org", Uuid::new_v4());
                    create_account(museum.endpoint(), &email).await;
                    let home = TestHome::new();
                    login(
                        &home,
                        "photos",
                        &email,
                        &["--host", museum.endpoint(), "--no-input"],
                    );
                    for from_name in [None, Some("CLI sender")] {
                        let mut args = vec![
                            "admin",
                            "email",
                            "test",
                            "--to",
                            "delivery@example.org",
                            "--from",
                            "sender@example.org",
                            "--no-input",
                        ];
                        if let Some(name) = from_name {
                            args.extend(["--from-name", name]);
                        }
                        assert_eq!(
                            home.json(&args),
                            json!({"to": "delivery@example.org", "accepted": true})
                        );
                        let message = inbox.receive_test();
                        let sender = if override_sender {
                            "override@example.org"
                        } else {
                            "sender@example.org"
                        };
                        let name = if override_sender {
                            "Server sender"
                        } else {
                            from_name.unwrap_or("Ente")
                        };
                        assert!(
                            message.contains(&format!("MAIL FROM:<{sender}>")),
                            "{message}"
                        );
                        assert!(
                            message.contains(&format!("From: \"{name}\" <{sender}>")),
                            "{message}"
                        );
                        assert!(
                            message.contains("RCPT TO:<delivery@example.org>"),
                            "{message}"
                        );
                        assert_eq!(message.matches("RCPT TO:").count(), 1);
                        assert!(
                            message.contains("This is a test mail from Ente"),
                            "{message}"
                        );
                    }
                    Ok(())
                })
            },
        )?;
    }
    Ok(())
}

async fn api_json(
    origin: &str,
    token: &str,
    method: &str,
    path: &str,
    body: Option<Value>,
) -> Value {
    let request = reqwest::Client::new()
        .request(method.parse().unwrap(), format!("{origin}{path}"))
        .header("x-auth-token", token)
        .header("x-client-package", "io.ente.photos");
    let response = if let Some(body) = body {
        request.json(&body)
    } else {
        request
    }
    .send()
    .await
    .unwrap();
    let status = response.status();
    let text = response.text().await.unwrap();
    assert!(status.is_success(), "{method} {path}: {status}: {text}");
    serde_json::from_str(&text).unwrap()
}

async fn register_passkey(origin: &str, token: &str) {
    let begin = api_json(origin, token, "POST", "/passkeys/registration/begin", None).await;
    let id = Uuid::new_v4();
    let id_string = b64::encode_url_safe_no_padding(id.as_bytes());
    let options = &begin["options"]["publicKey"];
    let data = json!({"type": "webauthn.create", "challenge": options["challenge"], "origin": "http://localhost:3001"});
    let mut auth_data = Sha256::digest(options["rp"]["id"].as_str().unwrap().as_bytes()).to_vec();
    auth_data.extend_from_slice(&[0x45, 0, 0, 0, 0]);
    auth_data.extend_from_slice(&[0; 16]);
    auth_data.extend_from_slice(&[0, 16]);
    auth_data.extend_from_slice(id.as_bytes());
    // COSE P-256 public key; registration uses no attestation signature.
    auth_data.extend(b64::decode("pQECAyYgASFYIGsX0fLhLEJH+Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWIlggT+NC4v4af5uO5+tKfA+eFivOM1drMV7Oy7ZAaDe/UfU=").unwrap());
    let mut attestation = b"\xa3\x63fmt\x64none\x67attStmt\xa0\x68authData\x58".to_vec();
    attestation.push(u8::try_from(auth_data.len()).unwrap());
    attestation.extend(auth_data);
    api_json(origin, token, "POST", &format!("/passkeys/registration/finish?sessionID={}&friendlyName=Test", begin["sessionID"].as_str().unwrap()), Some(json!({
        "id": id_string, "rawId": id_string, "type": "public-key",
        "response": {"clientDataJSON": b64::encode_url_safe_no_padding(&serde_json::to_vec(&data).unwrap()),
            "attestationObject": b64::encode_url_safe_no_padding(&attestation), "transports": ["internal"]}
    }))).await;
}

struct MailInbox {
    port: u16,
    messages: mpsc::Receiver<String>,
    stop: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<()>>,
}

impl MailInbox {
    fn new() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        listener.set_nonblocking(true).unwrap();
        let (send, messages) = mpsc::channel();
        let stop = Arc::new(AtomicBool::new(false));
        let done = stop.clone();
        let worker = thread::spawn(move || {
            while !done.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => receive_mail(stream, &send),
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10))
                    }
                    Err(error) => panic!("SMTP listener: {error}"),
                }
            }
        });
        Self {
            port,
            messages,
            stop,
            worker: Some(worker),
        }
    }

    fn receive_test(&self) -> String {
        loop {
            let message = self.messages.recv_timeout(Duration::from_secs(5)).unwrap();
            if message.contains("Subject: Test mail from Ente") {
                return message;
            }
        }
    }
}

impl Drop for MailInbox {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        let _ = self.worker.take().unwrap().join();
    }
}

fn receive_mail(mut stream: TcpStream, messages: &mpsc::Sender<String>) {
    stream.set_nonblocking(false).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    stream.write_all(b"220 localhost\r\n").unwrap();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut message = String::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap() == 0 {
            break;
        }
        message.push_str(&line);
        if line == "DATA\r\n" {
            stream.write_all(b"354 Send data\r\n").unwrap();
            loop {
                line.clear();
                assert_ne!(reader.read_line(&mut line).unwrap(), 0);
                if line == ".\r\n" {
                    break;
                }
                message.push_str(&line);
            }
            messages.send(std::mem::take(&mut message)).unwrap();
        } else if line == "QUIT\r\n" {
            stream.write_all(b"221 Bye\r\n").unwrap();
            break;
        }
        stream.write_all(b"250 OK\r\n").unwrap();
    }
}
