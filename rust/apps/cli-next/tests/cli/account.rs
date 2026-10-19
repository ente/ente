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
    let signup = prepared(&mut server).await;
    let saved = serde_json::to_value(&signup).unwrap();
    let attributes = &saved["keys"]["attributes"];
    server
        .mock("GET", "/ping")
        .with_body(r#"{"message":"pong","id":"fixture"}"#)
        .create_async()
        .await;
    let attrs = srp_attributes(&mut server, &saved, true).await;
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
    attrs.assert_async().await;
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
    Museum::run_async(|origin| async move {
        let home = TestHome::new();
        let email = format!("cli-create-{}@example.org", uuid::Uuid::new_v4());
        home.json(&[
            "account",
            "request-otp",
            "--email",
            &email,
            "--host",
            &origin,
            "--app",
            "auth",
        ]);
        let input = json!({"password": " secret 🙂 ", "otp": "123456"});
        let output = success(home.with_input(
            &[
                "account",
                "create",
                "--email",
                &email,
                "--host",
                &origin,
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
        let second = TestHome::new();
        let login =
            json!({"password": " secret 🙂 ", "otp": "123456", "totp": current_totp(secret)?});
        success(second.with_input(
            &[
                "account",
                "login",
                "--email",
                &email,
                "--account",
                "personal",
                "--app",
                "auth",
                "--host",
                &origin,
                "--input",
                "-",
            ],
            &serde_json::to_vec(&login)?,
        ));
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
    ente_test_support::Museum::run_async(|origin| async move {
        let home = TestHome::new();
        let email = format!("cli-interactive-{}@example.org", uuid::Uuid::new_v4());
        success(
            Command::new("python3")
                .args([
                    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/cli/account_prompt.py"),
                    env!("CARGO_BIN_EXE_ente-cli-next"),
                    &origin,
                    &email,
                ])
                .env("ENTE_CLI_HOME", home.dir.path())
                .env("ENTE_CLI_VAULT_KEY", b64::encode(home.key.as_bytes()))
                .output()?,
        );
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
