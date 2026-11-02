use super::*;
use ente_accounts::{AccountsClient, AccountsClientConfig, signup::Signup};
use mockito::Matcher;

#[test]
fn request_otp_is_independent_of_the_vault_and_reports_request_acceptance() {
    let mut server = mockito::Server::new();
    let request = server
        .mock("POST", "/users/ott")
        .match_header("x-client-package", "io.ente.auth")
        .match_body(Matcher::Json(
            json!({"email": "new@example.org", "purpose": "signup"}),
        ))
        .create();
    let home = TestHome::new();
    let output = success(
        home.command(&[
            "account",
            "request-otp",
            "--email",
            " New@Example.ORG ",
            "--host",
            &server.url(),
            "--app",
            "auth",
            "--json",
            "--no-input",
        ])
        .env("ENTE_CLI_VAULT_KEY", "invalid")
        .output()
        .unwrap(),
    );
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        value,
        json!({"email": "new@example.org", "host": server.url(), "app": "auth", "purpose": "create"})
    );
    assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 0);
    request.assert();
}

#[test]
fn email_input_conflicts_and_incomplete_creation_preserve_accounts() {
    let home = TestHome::new();
    home.seed("http://localhost:1");
    let before = home.read_encrypted_vault();
    for operation in ["login", "create"] {
        let mut args = vec![
            "account",
            operation,
            "--email",
            "flag@example.org",
            "--app",
            "photos",
            "--input",
            "-",
        ];
        if operation == "create" {
            args.push("--accept-terms");
        }
        assert!(
            failure(&home.with_input(
                &args,
                br#"{"email":"input@example.org","password":" secret "}"#
            ))
            .contains("--email differs")
        );
    }
    for (input, consent, expected) in [
        (
            br#"{"email":"new@example.org","password":" secret "}"#.as_slice(),
            true,
            "requires otp",
        ),
        (
            br#"{"email":"new@example.org","password":" secret ","otp":"123456"}"#.as_slice(),
            false,
            "requires --accept-terms",
        ),
        (
            br#"{"email":"new@example.org","otp":"123456"}"#.as_slice(),
            true,
            "nonempty password",
        ),
    ] {
        let mut args = vec![
            "account",
            "create",
            "--input",
            "-",
            "--host",
            "http://localhost:1",
        ];
        if consent {
            args.push("--accept-terms");
        }
        assert!(failure(&home.with_input(&args, input)).contains(expected));
    }
    assert_eq!(home.read_encrypted_vault(), before);
}

#[tokio::test]
async fn supplied_email_codes_complete_login_without_another_request() {
    let mut server = mockito::Server::new_async().await;
    let home = TestHome::new();
    let (saved, attrs, verify) = mock_email_login(&mut server).await;
    let args = [
        "account",
        "login",
        "--app",
        "photos",
        "--host",
        &server.url(),
        "--email",
        " NEW@example.org ",
        "--input",
        "-",
        "--json",
    ];
    let missing = home.with_input(&args, br#"{"password":" secret \ud83d\ude42 "}"#);
    let error = failure(&missing);
    assert!(
        error.contains("request-otp --email EMAIL --purpose login"),
        "{error}"
    );
    let output = success(home.with_input(
        &args,
        br#"{"email":"new@EXAMPLE.org","password":" secret \ud83d\ude42 ","otp":"654321"}"#,
    ));
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["account"]["id"], "42");
    assert_eq!(
        home.read_vault()["accounts"][0]["identity"]["master_key"],
        saved["keys"]["master_key"]
    );
    verify.assert_async().await;
    attrs.assert_async().await;
}

#[tokio::test]
async fn creation_retry_preserves_keys_and_recovers_after_an_accepted_upload() {
    let mut server = mockito::Server::new_async().await;
    let home = TestHome::new();
    let verify = server
        .mock("POST", "/users/verify-email")
        .with_body(json!({"id": 42, "token": b64::encode_url_safe(b"token")}).to_string())
        .create_async()
        .await;
    let empty = server
        .mock("GET", "/users/session-validity/v2")
        .with_body(r#"{"hasSetKeys":false}"#)
        .create_async()
        .await;
    let upload = server
        .mock("PUT", "/users/attributes")
        .with_status(403)
        .create_async()
        .await;
    let args = [
        "account",
        "create",
        "--host",
        &server.url(),
        "--input",
        "-",
        "--accept-terms",
        "--json",
    ];
    failure(&home.with_input(
        &args,
        br#"{"email":" New@Example.ORG ","password":" secret \ud83d\ude42 ","otp":"123456"}"#,
    ));
    let state = home.read_vault();
    let signup = &state["creations"][0]["signup"];
    assert!(state["accounts"].as_array().unwrap().is_empty());
    assert!(!state.to_string().contains(" secret 🙂 "));
    let bytes = home.read_encrypted_vault();
    assert!(
        failure(&home.with_input(&args, br#"{"email":"new@example.org","password":"wrong"}"#))
            .contains("Incorrect password")
    );
    assert_eq!(home.read_encrypted_vault(), bytes);
    empty.remove_async().await;
    upload.remove_async().await;
    server
        .mock("GET", "/users/session-validity/v2")
        .with_body(
            json!({"hasSetKeys": true, "keyAttributes": signup["keys"]["attributes"]}).to_string(),
        )
        .create_async()
        .await;
    server
        .mock("POST", "/users/srp/setup")
        .with_status(400)
        .create_async()
        .await;
    let attrs = srp_attributes(&mut server, signup, false).await;
    let details = server
        .mock("GET", "/users/details/v2?memoryCount=false")
        .with_status(403)
        .create_async()
        .await;
    let interrupted = home.with_input(
        &args,
        br#"{"email":"new@example.org","password":" secret \ud83d\ude42 "}"#,
    );
    assert!(failure(&interrupted).contains("HTTP 403"));
    assert_eq!(home.read_vault(), state);
    details.assert_async().await;
    details.remove_async().await;
    server
        .mock("GET", "/users/details/v2?memoryCount=false")
        .with_body(r#"{"email":"new@example.org"}"#)
        .create_async()
        .await;
    let mut retry = args.to_vec();
    retry.extend(["--account", "personal"]);
    let output = success(home.with_input(
        &retry,
        br#"{"email":"new@example.org","password":" secret \ud83d\ude42 "}"#,
    ));
    let result: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(result["account"]["name"], "personal");
    let complete = home.read_vault();
    assert_eq!(
        complete["accounts"][0]["identity"]["master_key"],
        signup["keys"]["master_key"]
    );
    assert_eq!(
        complete["accounts"][0]["identity"]["secret_key"],
        signup["keys"]["secret_key"]
    );
    assert!(complete.get("creations").is_none());
    let recovery = home.json(&["account", "recovery-key", "--offline"]);
    let recovery = ente_accounts::auth::recovery_key_from_mnemonic_or_hex(
        recovery["recoveryKey"].as_str().unwrap(),
    )
    .unwrap();
    assert_eq!(
        serde_json::to_value(recovery.to_vec()).unwrap(),
        complete["accounts"][0]["identity"]["recovery_key"]
    );
    verify.assert_async().await;
    verify.remove_async().await;
    attrs.assert_async().await;
    attrs.remove_async().await;

    let mut pending = complete.clone();
    pending["creations"] = state["creations"].clone();
    pending["accounts"][0]["sessions"] = json!({"auth": {"token": b"previous"}});
    home.write_vault(&pending);
    server
        .mock("GET", "/ping")
        .with_body(r#"{"message":"pong","id":"fixture"}"#)
        .create_async()
        .await;
    let attrs = srp_attributes(&mut server, signup, true).await;
    let verify = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(json!({"ott": "654321"})))
        .with_body(
            json!({"id": 42, "keyAttributes": signup["keys"]["attributes"],
                "token": b64::encode_url_safe(b"recovered")})
            .to_string(),
        )
        .create_async()
        .await;
    let old_signup = server
        .mock("POST", "/users/logout")
        .match_header("x-client-package", "io.ente.photos")
        .match_header("x-auth-token", b64::encode_url_safe(b"token").as_str())
        .create_async()
        .await;
    let old_login = server
        .mock("POST", "/users/logout")
        .match_header("x-client-package", "io.ente.auth")
        .match_header("x-auth-token", b64::encode_url_safe(b"previous").as_str())
        .with_status(403)
        .create_async()
        .await;
    let output = success(home.with_input(
        &[
            "account",
            "login",
            "--app",
            "auth",
            "--account",
            "personal",
            "--host",
            &server.url(),
            "--input",
            "-",
        ],
        br#"{"email":"new@example.org","password":" secret \ud83d\ude42 ","otp":"654321"}"#,
    ));
    assert!(
        String::from_utf8(output.stderr)
            .unwrap()
            .contains("Could not end the previous login")
    );
    let recovered = home.read_vault();
    assert!(recovered.get("creations").is_none());
    assert_eq!(
        recovered["accounts"][0]["identity"],
        complete["accounts"][0]["identity"]
    );
    assert_eq!(
        recovered["accounts"][0]["sessions"],
        json!({"auth": {"token": b"recovered"}})
    );
    verify.assert_async().await;
    old_signup.assert_async().await;
    old_login.assert_async().await;
    attrs.assert_async().await;
    let logout = server
        .mock("POST", "/users/logout")
        .match_header("x-client-package", "io.ente.auth")
        .match_header("x-auth-token", b64::encode_url_safe(b"recovered").as_str())
        .create_async()
        .await;
    success(home.run(&["account", "logout"]));
    assert_eq!(home.read_vault(), json!({"accounts": [], "selected": null}));
    logout.assert_async().await;
}

#[cfg(unix)]
#[tokio::test]
async fn interactive_passkey_completion_saves_the_verified_account() {
    let mut server = mockito::Server::new_async().await;
    let home = TestHome::new();
    let signup = serde_json::to_value(prepared(&mut server).await).unwrap();
    let attrs = srp_attributes(&mut server, &signup, true).await;
    server
        .mock("GET", "/ping")
        .with_body(r#"{"message":"pong","id":"fixture"}"#)
        .create_async()
        .await;
    let request = server
        .mock("POST", "/users/ott")
        .match_body(Matcher::Json(
            json!({"email": "new@example.org", "purpose": "login"}),
        ))
        .create_async()
        .await;
    let verify = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(
            json!({"email": "new@example.org", "ott": "123456"}),
        ))
        .with_body(
            json!({"id": 42, "passkeySessionID": "passkey-session", "accountsUrl": "ente-cli-test://accounts"}).to_string(),
        )
        .create_async()
        .await;
    let mut polls = Vec::new();
    for (status, response) in [
        (400, json!({})),
        (
            200,
            json!({"id": 42, "keyAttributes": signup["keys"]["attributes"], "token": b64::encode_url_safe(b"passkey-token")}),
        ),
    ] {
        polls.push(
            server
                .mock(
                    "GET",
                    "/users/two-factor/passkeys/get-token?sessionID=passkey-session",
                )
                .match_header("x-client-package", "io.ente.auth")
                .with_status(status)
                .with_body(response.to_string())
                .expect(1)
                .create_async()
                .await,
        );
    }
    let details = server
        .mock("GET", "/users/details/v2?memoryCount=false")
        .match_header(
            "x-auth-token",
            b64::encode_url_safe(b"passkey-token").as_str(),
        )
        .with_body(r#"{"email":"new@example.org"}"#)
        .create_async()
        .await;
    success(
        Command::new("python3")
            .arg(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/tests/cli/account_prompt.py"
            ))
            .arg(cli_binary())
            .args([server.url().as_str(), "new@example.org", "passkey"])
            .env("ENTE_CLI_HOME", home.dir.path())
            .env("ENTE_CLI_VAULT_KEY", b64::encode(home.key.as_bytes()))
            .output()
            .unwrap(),
    );
    let account = home.json(&["account", "view"]);
    assert_eq!(account["id"], "42");
    assert_eq!(account["apps"], json!(["auth"]));
    assert_eq!(account["selected"], true);
    assert_eq!(
        home.json(&["account", "token", "--app", "auth"]),
        json!({"token": b64::encode_url_safe(b"passkey-token")})
    );
    assert_eq!(
        home.read_vault()["accounts"][0]["identity"]["master_key"],
        signup["keys"]["master_key"]
    );
    attrs.assert_async().await;
    request.assert_async().await;
    verify.assert_async().await;
    details.assert_async().await;
    for poll in polls {
        poll.assert_async().await;
    }
}

pub(super) async fn mock_email_login(
    server: &mut mockito::ServerGuard,
) -> (Value, mockito::Mock, mockito::Mock) {
    let saved = serde_json::to_value(prepared(server).await).unwrap();
    let attributes = &saved["keys"]["attributes"];
    server
        .mock("GET", "/ping")
        .with_body(r#"{"message":"pong","id":"fixture"}"#)
        .create_async()
        .await;
    let attrs = srp_attributes(server, &saved, true).await;
    let verify = server
        .mock("POST", "/users/verify-email")
        .match_body(Matcher::PartialJson(
            json!({"email": "new@example.org", "ott": "654321"}),
        ))
        .with_body(
            json!({"id": 42, "keyAttributes": attributes, "token": b64::encode_url_safe(b"token")})
                .to_string(),
        )
        .create_async()
        .await;
    server
        .mock("GET", "/users/details/v2?memoryCount=false")
        .with_body(r#"{"email":"new@example.org"}"#)
        .create_async()
        .await;
    (saved, attrs, verify)
}

async fn prepared(server: &mut mockito::ServerGuard) -> Signup {
    let client =
        AccountsClient::new(AccountsClientConfig::new("io.ente.photos").with_origin(server.url()))
            .unwrap();
    let empty = server
        .mock("GET", "/users/session-validity/v2")
        .with_body(r#"{"hasSetKeys":false}"#)
        .create_async()
        .await;
    let signup = Signup::verified(
        "new@example.org".into(),
        serde_json::from_value(json!({"id":42,"token": b64::encode_url_safe(b"token")})).unwrap(),
    )
    .unwrap()
    .prepare(&client, " secret 🙂 ")
    .await
    .unwrap();
    empty.remove_async().await;
    signup
}

async fn srp_attributes(
    server: &mut mockito::ServerGuard,
    signup: &Value,
    email_mfa: bool,
) -> mockito::Mock {
    let keys = &signup["keys"];
    let salt: Vec<u8> = serde_json::from_value(keys["srp_salt"].clone()).unwrap();
    server.mock("GET", "/users/srp/attributes?email=new%40example.org").with_body(json!({"attributes": {
        "srpUserID": keys["srp_user_id"], "srpSalt": b64::encode(&salt), "kekSalt": keys["attributes"]["kekSalt"],
        "memLimit": keys["attributes"]["memLimit"], "opsLimit": keys["attributes"]["opsLimit"], "isEmailMFAEnabled": email_mfa
    }}).to_string()).expect_at_least(1).create_async().await
}

#[cfg(feature = "museum")]
#[test]
fn creation_enrollment_and_login_across_processes() -> ente_test_support::TestResult {
    use ente_test_support::{Museum, account_fixture::current_totp};
    let inbox = super::mail::MailInbox::new();
    let port = inbox.port.to_string();
    let env = [
        ("ENTE_SMTP_HOST", "127.0.0.1"),
        ("ENTE_SMTP_PORT", &port),
        ("ENTE_SMTP_USERNAME", ""),
        ("ENTE_SMTP_PASSWORD", ""),
        ("ENTE_SMTP_ENCRYPTION", ""),
    ];
    Museum::run_with_env(&env, |museum| {
        let origin = museum.endpoint();
        let home = TestHome::new();
        let email = format!("cli-create-{}@example.com", uuid::Uuid::new_v4());
        home.json(&[
            "account",
            "request-otp",
            "--email",
            &email,
            "--host",
            origin,
            "--app",
            "auth",
        ]);
        let read_code = || {
            let message = inbox.receive("Subject: Verification code:");
            assert!(message.contains(&format!("RCPT TO:<{email}>")));
            message
                .lines()
                .find_map(|line| line.strip_prefix("Subject: Verification code: "))
                .unwrap()
                .trim()
                .to_owned()
        };
        let input = json!({"password": " secret 🙂 ", "otp": read_code()});
        let output = success(home.with_input(
            &[
                "account",
                "create",
                "--email",
                &email,
                "--host",
                origin,
                "--app",
                "auth",
                "--input",
                "-",
                "--accept-terms",
                "--json",
            ],
            &serde_json::to_vec(&input)?,
        ));
        let created: Value = serde_json::from_slice(&output.stdout)?;
        assert_eq!(created["account"]["name"], email);
        assert_eq!(created["account"]["apps"], json!(["auth"]));
        assert_eq!(created["account"]["selected"], true);
        assert_eq!(
            home.json(&["auth", "api", "/users/details/v2"])["email"],
            email
        );
        let setup = home.json(&["account", "totp", "setup"]);
        let secret = setup["secret"].as_str().unwrap();
        assert_eq!(
            home.json(&["account", "totp", "status"]),
            json!({"totpEnabled": false})
        );
        let error = failure(&home.with_input(
            &["account", "totp", "enable", "--input", "-"],
            &serde_json::to_vec(&json!({"secret": secret, "totp": "invalid"}))?,
        ));
        assert!(error.contains("Code not accepted."));
        let output = success(home.with_input(
            &["account", "totp", "enable", "--input", "-", "--json"],
            &serde_json::to_vec(&json!({"secret": secret, "totp": current_totp(secret)?}))?,
        ));
        assert_eq!(
            serde_json::from_slice::<Value>(&output.stdout)?,
            json!({"totpEnabled": true})
        );
        assert_eq!(
            home.json(&["account", "totp", "status"]),
            json!({"totpEnabled": true})
        );
        assert!(failure(&home.run(&["account", "totp", "setup"])).contains("already enabled"));
        success(home.with_input(
            &[
                "auth",
                "api",
                "/users/email-mfa",
                "--method",
                "PUT",
                "--body",
                "-",
            ],
            br#"{"isEnabled":true}"#,
        ));
        let second = TestHome::new();
        second.json(&[
            "account",
            "request-otp",
            "--email",
            &email,
            "--host",
            origin,
            "--app",
            "auth",
            "--purpose",
            "login",
        ]);
        let code = read_code();
        let wrong_code = format!("{:06}", (code.parse::<u32>()? + 1) % 1_000_000);
        let login = [
            "account",
            "login",
            "--email",
            &email,
            "--account",
            "personal",
            "--app",
            "auth",
            "--host",
            origin,
            "--input",
            "-",
        ];
        let mut input = json!({"password": " secret 🙂 ", "otp": wrong_code});
        let error = failure(&second.with_input(&login, &serde_json::to_vec(&input)?));
        assert!(
            error.contains("Incorrect email verification code"),
            "{error}"
        );
        input["otp"] = code.into();
        input["totp"] = current_totp(secret)?.into();
        success(second.with_input(&login, &serde_json::to_vec(&input)?));
        assert_eq!(
            home.json(&["account", "recovery-key"]),
            second.json(&["account", "recovery-key", "--account", "personal"])
        );
        assert_eq!(
            second.json(&["auth", "api", "/users/details/v2"])["email"],
            email
        );
        Ok(())
    })
}

#[cfg(all(unix, feature = "museum"))]
#[test]
fn interactive_creation_password_retry_and_enrollment() -> ente_test_support::TestResult {
    use std::io::{BufRead, BufReader};

    ente_test_support::Museum::run(|museum| {
        let home = TestHome::new();
        let email = format!("cli-interactive-{}@example.org", uuid::Uuid::new_v4());
        success({
            let mut child = Command::new("python3")
                .arg(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/tests/cli/account_prompt.py"
                ))
                .arg(cli_binary())
                .args([museum.endpoint(), &email])
                .env("ENTE_CLI_HOME", home.dir.path())
                .env("ENTE_CLI_VAULT_KEY", b64::encode(home.key.as_bytes()))
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()?;
            let mut ready = String::new();
            BufReader::new(child.stdout.take().unwrap()).read_line(&mut ready)?;
            assert_eq!(ready.trim(), "expire");
            museum.execute_sql("UPDATE temp_two_factor SET expiration_time = 1")?;
            writeln!(child.stdin.take().unwrap(), "expired")?;
            child.wait_with_output()?
        });
        assert_eq!(home.json(&["account", "view"])["name"], email);
        assert_eq!(
            home.json(&["account", "totp", "status"]),
            json!({"totpEnabled": true})
        );
        assert_eq!(
            home.json(&["photos", "api", "/users/details/v2"])["email"],
            email
        );
        Ok(())
    })
}

const GB: i64 = 1 << 30;

fn seed_sessions(home: &TestHome, origin: &str, sessions: Value) {
    let id = "e6b355f0-5d4d-4fc3-b32c-a6c8f52b8210";
    home.write_vault(&json!({
        "selected": id,
        "accounts": [{
            "storage_id": id, "db_key": vec![42u8; 32], "name": "fixture", "email": "fixture@example.org",
            "origin": origin, "user_id": 9007199254740993i64,
            "identity": {"master_key": vec![0u8; 32], "recovery_key": vec![0u8; 32], "secret_key": vec![0u8; 32]},
            "sessions": sessions
        }]
    }));
}

fn details_body(family: Value) -> String {
    json!({
        "email": "fixture@example.org", "usage": 3 * GB, "fileCount": 339, "sharedCollectionsCount": 2,
        "storageBonus": 10 * GB,
        "subscription": {"productID": "free", "storage": 10 * GB, "expiryTime": 4942020944746699i64,
            "originalTransactionID": "none", "paymentProvider": "", "attributes": {}},
        "familyData": family,
    })
    .to_string()
}

#[test]
fn usage_reads_account_details_with_the_saved_login() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let details = server
        .mock("GET", "/users/details/v2")
        .match_query(Matcher::UrlEncoded("memoryCount".into(), "true".into()))
        .match_header("x-client-package", "io.ente.photos")
        .match_header("x-auth-token", b64::encode_url_safe(&[0xfb, 0xef]).as_str())
        .with_body(details_body(Value::Null))
        .expect(2)
        .create();
    assert_eq!(
        home.json(&["photos", "usage"]),
        json!({"email": "fixture@example.org", "usedBytes": 3 * GB, "totalBytes": 20 * GB,
            "planBytes": 10 * GB, "bonusBytes": 10 * GB, "freeBytes": 17 * GB, "files": 339,
            "planExpiresAt": "2126-08-10T07:35:44.746699Z", "planActive": true, "family": null})
    );
    let plain = success(home.run(&["photos", "usage"]));
    assert_eq!(
        String::from_utf8_lossy(&plain.stdout),
        "Email   fixture@example.org\nTotal   20 GB\n\
         Used    3 GB\nFree    17 GB\n\
         Plan    10 GB\nStatus  active\n\
         Bonus   10 GB\nFiles   339\nFamily  none\n"
    );
    details.assert();
}

#[test]
fn family_usage_reports_the_admin_plan_and_the_member_limit() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let family = json!({"storage": 200 * GB, "expiryTime": 4942020944746699i64, "adminBonus": 0, "members": [
        {"id": "a", "email": "admin@example.org", "status": "ACCEPTED", "usage": 50 * GB, "isAdmin": true},
        {"id": "b", "email": "fixture@example.org", "status": "ACCEPTED", "usage": 3 * GB, "storageLimit": 5 * GB},
        {"id": "c", "email": "new@example.org", "status": "INVITED"}
    ]});
    // A member's own subscription is a lapsed plan; the family plan is what counts.
    let mut body: Value = serde_json::from_str(&details_body(family)).unwrap();
    body["subscription"]["expiryTime"] = json!(1);
    let details = server
        .mock("GET", "/users/details/v2")
        .match_query(Matcher::Any)
        .with_body(body.to_string())
        .expect(2)
        .create();
    let usage = home.json(&["photos", "usage"]);
    assert_eq!(usage["planBytes"], 200 * GB);
    assert_eq!(usage["planActive"], true);
    assert_eq!(usage["planExpiresAt"], "2126-08-10T07:35:44.746699Z");
    assert_eq!(usage["totalBytes"], 210 * GB);
    assert_eq!(usage["freeBytes"], 2 * GB);
    assert_eq!(usage["family"]["usedBytes"], 53 * GB);
    assert_eq!(usage["family"]["storageBytes"], 210 * GB);
    assert_eq!(
        usage["family"]["members"][2],
        json!({"email": "new@example.org", "status": "INVITED", "admin": false, "usedBytes": 0, "storageLimitBytes": null})
    );
    let plain = String::from_utf8(success(home.run(&["photos", "usage"])).stdout).unwrap();
    assert!(
        plain.contains("Plan            200 GB\nStatus          active\n"),
        "{plain}"
    );
    assert!(plain.contains(
        "Family          admin@example.org (admin), fixture@example.org, new@example.org (invited)\n\
         Family used     53 GB\nFamily storage  210 GB\n\
         Your limit      5 GB\n"
    ));
    details.assert();
}

#[test]
fn family_usage_free_space_respects_both_quotas() {
    for (family_used, member_limit, free, free_text) in [
        (53, Some(5), 2, "2 GB"),
        (209, Some(5), 1, "1 GB"),
        (210, Some(5), 0, "0 bytes"),
        (211, Some(5), 0, "0 bytes"),
        (53, Some(3), 0, "0 bytes"),
        (53, Some(2), 0, "0 bytes"),
        (209, None, 1, "1 GB"),
    ] {
        let mut server = mockito::Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let family = json!({"storage": 200 * GB, "expiryTime": 4942020944746699i64, "members": [
            {"email": "admin@example.org", "status": "ACCEPTED", "usage": (family_used - 3) * GB, "isAdmin": true},
            {"email": "fixture@example.org", "status": "ACCEPTED", "usage": 3 * GB,
                "storageLimit": member_limit.map(|limit| limit * GB)}
        ]});
        let details = server
            .mock("GET", "/users/details/v2")
            .match_query(Matcher::Any)
            .with_body(details_body(family))
            .expect(2)
            .create();
        let usage = home.json(&["photos", "usage"]);
        assert_eq!(
            usage["freeBytes"],
            free * GB,
            "family used: {family_used} GB; member limit: {member_limit:?} GB"
        );
        let plain = String::from_utf8(success(home.run(&["photos", "usage"])).stdout).unwrap();
        let free_line = plain
            .lines()
            .find(|line| line.starts_with("Free "))
            .unwrap();
        assert_eq!(free_line.strip_prefix("Free").unwrap().trim(), free_text);
        details.assert();
    }
}

#[test]
fn usage_counts_photos_files_and_needs_a_photos_login() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    let details = server
        .mock("GET", "/users/details/v2")
        .match_query(Matcher::Any)
        .match_header("x-client-package", "io.ente.photos")
        .match_header("x-auth-token", b64::encode_url_safe(&[0xfb, 0xef]).as_str())
        .with_body(details_body(Value::Null))
        .expect(2)
        .create();
    for (app, token) in [("locker", [1u8, 2]), ("auth", [3, 4])] {
        seed_sessions(&home, &server.url(), json!({app: {"token": token}}));
        let error = failure(&home.run(&["photos", "usage"]));
        assert!(error.contains("not logged into Ente Photos"), "{error}");
        assert!(
            error.contains("account login --account \"fixture\" --app photos"),
            "{error}"
        );
    }
    seed_sessions(
        &home,
        &server.url(),
        json!({"locker": {"token": [1, 2]}, "photos": {"token": [0xfb, 0xef]}}),
    );
    let with_locker = home.json(&["photos", "usage"]);
    assert_eq!(with_locker["files"], 339);
    seed_sessions(
        &home,
        &server.url(),
        json!({"photos": {"token": [0xfb, 0xef]}}),
    );
    assert_eq!(home.json(&["photos", "usage"]), with_locker);
    details.assert();
}

#[test]
fn usage_reports_server_errors_and_refuses_offline_or_missing_accounts() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    assert!(failure(&home.run(&["photos", "usage"])).contains("no accounts"));
    home.seed(&server.url());
    assert!(
        failure(&home.run(&["photos", "usage", "--offline"])).contains("requires network access")
    );
    assert!(failure(&home.run(&["photos", "usage", "--account", "nobody"])).contains("nobody"));
    let details = server
        .mock("GET", "/users/details/v2")
        .match_query(Matcher::Any)
        .with_status(503)
        .with_body("maintenance")
        .expect(1)
        .create();
    let photos = home.run(&["photos", "usage", "--json"]);
    assert!(failure(&photos).contains("HTTP 503"));
    assert!(photos.stdout.is_empty());
    details.assert();
}

#[test]
fn usage_marks_an_expired_plan() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let mut body: Value = serde_json::from_str(&details_body(Value::Null)).unwrap();
    body["subscription"]["storage"] = json!(50 * GB);
    body["subscription"]["expiryTime"] = json!(1_767_225_600_000_000i64);
    let details = server
        .mock("GET", "/users/details/v2")
        .match_query(Matcher::Any)
        .with_body(body.to_string())
        .expect(2)
        .create();
    let usage = home.json(&["photos", "usage"]);
    assert_eq!(usage["planBytes"], 50 * GB);
    assert_eq!(usage["planExpiresAt"], "2026-01-01T00:00:00.000000Z");
    assert_eq!(usage["planActive"], false);
    assert_eq!(usage["totalBytes"], 60 * GB);
    let plain = String::from_utf8(success(home.run(&["photos", "usage"])).stdout).unwrap();
    assert!(
        plain.contains("Plan    50 GB\nStatus  expired\n"),
        "{plain}"
    );
    details.assert();
}
