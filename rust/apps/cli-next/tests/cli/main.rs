#![cfg(test)]

use std::{
    fs,
    io::Write,
    process::{Command, Output, Stdio},
};

use ente_core::{
    b64,
    crypto::{Header, Key, blob},
};
use serde_json::{Value, json};
use tempfile::TempDir;

#[test]
fn completion_prints_scripts_without_storage() {
    let home = TestHome::new();
    let path = home.dir.path().join("unused");
    for shell in ["bash", "zsh", "fish", "powershell", "elvish"] {
        let output = success(
            home.command(&["completion", shell, "--json", "--offline", "--no-input"])
                .env("ENTE_CLI_HOME", &path)
                .env("ENTE_CLI_VAULT_KEY", "invalid")
                .output()
                .unwrap(),
        );
        assert!(output.stderr.is_empty(), "{shell}");
        let script = String::from_utf8(output.stdout).unwrap();
        assert!(serde_json::from_str::<Value>(&script).is_err(), "{shell}");
        for item in [
            "migration",
            "account",
            "paste",
            "hardlinks",
            "exclude-shared",
            "exclude-hidden",
            "completion",
            "admin",
            "update-subscription",
        ] {
            assert!(script.contains(item), "{shell}: {item}");
        }
        assert!(!path.exists(), "{shell} created the CLI home");
    }
}

#[test]
fn migration_hints_respect_command_and_argument_boundaries() {
    let binary = format!("ente-cli-next{}", std::env::consts::EXE_SUFFIX);
    let home = TestHome::new();
    let path = home.dir.path().join("unused");
    for (args, suggestion) in [
        ("export", "photos export DIR"),
        ("--offline account --json add", "account login --app"),
        ("accounts --no-input get-token", "account token --app"),
        (
            "auth decrypt in.json out.txt",
            "auth decrypt INPUT --output OUTPUT",
        ),
        (
            "admin disable-2fa --user person@example.org",
            "admin user disable-totp",
        ),
    ] {
        let output = home
            .command(&args.split_whitespace().collect::<Vec<_>>())
            .env("ENTE_CLI_HOME", &path)
            .env("ENTE_CLI_VAULT_KEY", "invalid")
            .output()
            .unwrap();
        let error = failure(&output);
        assert!(error.contains(suggestion), "{args}: {error}");
        assert!(
            error.contains(&format!("\n  {binary} help migration\n")),
            "{args}: {error}"
        );
        assert!(
            error.lines().all(|line| line == line.trim_end()),
            "{args}: {error}"
        );
        assert_eq!(output.status.code(), Some(2));
        assert!(output.stdout.is_empty());
    }
    for args in [
        "paste create export --unknown",
        "photos --account export album view version --unknown",
        "auth decrypt --output version in.json --unknown",
        "paste create -- version export",
    ] {
        let output = home
            .command(&args.split_whitespace().collect::<Vec<_>>())
            .env("ENTE_CLI_HOME", &path)
            .output()
            .unwrap();
        let error = failure(&output);
        assert!(!error.contains("help migration"), "{args}: {error}");
    }
    assert!(!path.exists());
}

#[test]
fn reads_do_not_initialize_storage() {
    let binary = format!("ente-cli-next{}", std::env::consts::EXE_SUFFIX);
    for existing_home in [false, true] {
        let home = TestHome::new();
        let path = home.dir.path().join("unused");
        if existing_home {
            fs::create_dir(&path).unwrap();
        }
        let help = success(
            home.command(&["help", "--all"])
                .env("ENTE_CLI_HOME", &path)
                .env("ENTE_CLI_VAULT_KEY", "invalid")
                .output()
                .unwrap(),
        );
        assert!(help.stderr.is_empty());
        let help = String::from_utf8(help.stdout).unwrap();
        assert!(help.contains(&format!("=== {binary} ===")));
        assert!(help.contains(&format!("Usage: {binary} [OPTIONS] <COMMAND>")));
        assert!(help.contains(&format!("=== {binary} photos file download ===")));
        assert!(help.contains(&format!("=== {binary} vault key generate ===")));
        assert!(help.contains("--hardlinks"));
        assert!(help.contains("--exclude-shared"));
        assert!(help.contains("--exclude-hidden"));
        assert!(help.contains("Linked files share contents, timestamps and permissions."));
        assert!(help.contains(&format!("=== {binary} paste create ===")));
        assert!(help.contains(&format!("=== {binary} paste consume ===")));
        assert!(help.contains(&format!("=== {binary} account token ===")));
        let migration = success(
            home.command(&["help", "migration", "--json", "--offline", "--no-input"])
                .env("ENTE_CLI_HOME", &path)
                .env("ENTE_CLI_VAULT_KEY", "invalid")
                .output()
                .unwrap(),
        );
        assert!(migration.stderr.is_empty());
        let migration = String::from_utf8(migration.stdout).unwrap();
        assert!(migration.contains("account login --app"));
        assert!(migration.lines().all(|line| line == line.trim_end()));
        for commands in [
            vec![],
            vec!["help"],
            vec!["photos", "file", "view"],
            vec!["accounts", "login"],
        ] {
            let mut topic = vec!["help"];
            topic.extend(&commands);
            let mut flag = commands;
            flag.push("--help");
            let read_help = |args: &[&str]| {
                let output = success(
                    home.command(args)
                        .env("ENTE_CLI_HOME", &path)
                        .env("ENTE_CLI_VAULT_KEY", "invalid")
                        .output()
                        .unwrap(),
                );
                assert!(output.stderr.is_empty());
                String::from_utf8(output.stdout).unwrap()
            };
            let expected = read_help(&flag);
            assert_eq!(
                read_help(&topic).split_whitespace().collect::<Vec<_>>(),
                expected.split_whitespace().collect::<Vec<_>>()
            );
            if topic.len() > 2 {
                topic.swap(0, 1);
                assert_eq!(
                    read_help(&topic).split_whitespace().collect::<Vec<_>>(),
                    expected.split_whitespace().collect::<Vec<_>>()
                );
            }
        }
        for args in [
            vec!["help", "photos", "unknown"],
            vec!["help", "--all", "migration"],
        ] {
            let output = home
                .command(&args)
                .env("ENTE_CLI_HOME", &path)
                .output()
                .unwrap();
            assert_eq!(output.status.code(), Some(2));
            assert!(output.stdout.is_empty());
        }
        assert_eq!(path.exists(), existing_home);
        for command in ["login", "token"] {
            let missing_app = home
                .command(&["account", command])
                .env("ENTE_CLI_VAULT_KEY", "invalid")
                .output()
                .unwrap();
            assert!(failure(&missing_app).contains("--app <APP>"));
            assert!(missing_app.stdout.is_empty());
        }
        let output = home
            .command(&["accounts", "list"])
            .env("ENTE_CLI_HOME", &path)
            .output()
            .unwrap();
        assert_eq!(success(output).stdout, b"No accounts on this device.\n");
        for args in [
            vec!["accounts", "list", "--json"],
            vec!["accounts", "view", "--account", "missing"],
            vec!["account", "token", "--app", "photos"],
            vec!["photos", "album", "list"],
            vec!["photos", "album", "view", "missing"],
            vec!["photos", "file", "list"],
            vec!["photos", "file", "view", "missing"],
            vec!["photos", "api", "/users/details/v2"],
        ] {
            let output = home
                .command(&args)
                .env("ENTE_CLI_HOME", &path)
                .output()
                .unwrap();
            if args[1] == "list" {
                assert_eq!(success(output).stdout, b"[]\n");
            } else {
                assert!(failure(&output).contains("no account"));
            }
            assert_eq!(path.exists(), existing_home, "read created the CLI home");
            if existing_home {
                assert_eq!(fs::read_dir(&path).unwrap().count(), 0);
            }
            #[cfg(target_os = "linux")]
            {
                let output = home
                    .command(&args)
                    .env("ENTE_CLI_HOME", &path)
                    .env_remove("ENTE_CLI_VAULT_KEY")
                    .env(
                        "DBUS_SESSION_BUS_ADDRESS",
                        "unix:path=/nonexistent-ente-test-bus",
                    )
                    .output()
                    .unwrap();
                if args[1] == "list" {
                    assert_eq!(success(output).stdout, b"[]\n");
                } else {
                    assert!(failure(&output).contains("no account"));
                }
                assert_eq!(path.exists(), existing_home);
                if existing_home {
                    assert_eq!(fs::read_dir(&path).unwrap().count(), 0);
                }
            }
        }
    }
}

#[test]
fn invalid_login_host_does_not_initialize_storage() {
    let home = TestHome::new();
    let path = home.dir.path().join("unused");
    let output = home
        .command(&["account", "login", "--app", "photos", "--host", "https://["])
        .env("ENTE_CLI_HOME", &path)
        .output()
        .unwrap();
    assert!(failure(&output).contains("invalid API host"));
    assert!(!path.exists());
}

#[test]
fn login_requires_input_before_storage_or_network() {
    let home = TestHome::new();
    let mut server = mockito::Server::new();
    let ping = server
        .mock("GET", "/ping")
        .with_status(503)
        .expect(1)
        .create();
    let origin = server.url();
    let mut args = vec![
        "account",
        "login",
        "--app",
        "photos",
        "--host",
        &origin,
        "--no-input",
    ];
    assert!(failure(&home.run(&args)).contains("supply --input"));
    assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 0);
    args.extend(["--input", "-"]);
    let output = home.with_input(
        &args,
        br#"{"email":"fixture@example.org","password":"secret"}"#,
    );
    assert!(failure(&output).contains("cannot reach the selected Ente server"));
    ping.assert();
}

#[test]
fn deleted_collections_are_filtered_before_decryption() {
    let mut server = mockito::Server::new();
    let request = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::UrlEncoded("sinceTime".into(), "0".into()))
        .with_header("content-type", "application/json")
        .with_body(
            json!({"collections": [{
                "id": 12, "owner": {"id": 9007199254740993i64},
                "encryptedKey": "", "name": "", "encryptedName": "",
                "nameDecryptionNonce": "", "type": "album",
                "updationTime": 1, "isDeleted": true
            }]})
            .to_string(),
        )
        .expect(1)
        .create();
    let subsequent = server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::UrlEncoded("sinceTime".into(), "1".into()))
        .with_body(json!({"collections": []}).to_string())
        .expect(2)
        .create();
    let home = TestHome::new();
    home.seed(&server.url());
    assert_eq!(home.json(&["photos", "album", "list"]), json!([]));
    assert_eq!(
        success(home.run(&["photos", "album", "list"])).stdout,
        b"No albums.\n"
    );
    assert!(failure(&home.run(&["photos", "album", "view", "12"])).contains("no album matches"));
    request.assert();
    subsequent.assert();
}

#[cfg(unix)]
#[test]
fn accessing_an_existing_vault_preserves_directory_permissions() {
    use std::os::unix::fs::PermissionsExt;

    let home = TestHome::new();
    home.seed("http://localhost:8080");
    fs::set_permissions(home.dir.path(), fs::Permissions::from_mode(0o500)).unwrap();
    let result = home.run(&["account", "token", "--app", "photos"]);
    let mode = fs::metadata(home.dir.path()).unwrap().permissions().mode() & 0o777;
    fs::set_permissions(home.dir.path(), fs::Permissions::from_mode(0o700)).unwrap();
    assert_eq!(success(result).stdout, b"--8=\n");
    assert_eq!(mode, 0o500, "read changed the CLI home permissions");
    assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 1);

    fs::set_permissions(home.dir.path(), fs::Permissions::from_mode(0o755)).unwrap();
    success(home.run(&["account", "switch", "fixture"]));
    assert_eq!(
        fs::metadata(home.dir.path()).unwrap().permissions().mode() & 0o777,
        0o755
    );
}

#[test]
fn invalid_vault_wrappers_do_not_require_decryption() {
    let home = TestHome::new();
    for bytes in [
        b"different layout".as_slice(),
        br#"{"data":"","version":2}"#,
        br#"{"data":"not base64"}"#,
    ] {
        fs::write(home.dir.path().join("vault.json"), bytes).unwrap();
        for key in [&home.key, &Key::generate()] {
            let output = home
                .command(&["account", "list"])
                .env("ENTE_CLI_VAULT_KEY", b64::encode(key.as_bytes()))
                .output()
                .unwrap();
            assert!(failure(&output).contains("unsupported or invalid CLI vault format"));
            assert_eq!(fs::read(home.dir.path().join("vault.json")).unwrap(), bytes);
        }
    }
}

#[test]
fn keys_and_invalid_vaults_have_no_destructive_fallback() {
    let home = TestHome::new();
    let generated = success(
        home.command(&["vault", "key", "generate"])
            .env("ENTE_CLI_VAULT_KEY", "invalid")
            .output()
            .unwrap(),
    );
    assert_eq!(
        b64::decode(std::str::from_utf8(&generated.stdout).unwrap().trim())
            .unwrap()
            .len(),
        32
    );
    assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 0);

    home.seed("http://localhost:8080");
    let original = fs::read(home.dir.path().join("vault.json")).unwrap();
    for key in [String::new(), "invalid".into(), b64::encode(&[0u8; 31])] {
        let output = home
            .command(&["account", "list"])
            .env("ENTE_CLI_VAULT_KEY", &key)
            .output()
            .unwrap();
        failure(&output);
        if !key.is_empty() {
            assert!(!String::from_utf8_lossy(&output.stderr).contains(&key));
        }
        assert_eq!(
            fs::read(home.dir.path().join("vault.json")).unwrap(),
            original
        );
    }
    let wrong_key = failure(
        &home
            .command(&["account", "token", "--app", "photos"])
            .env(
                "ENTE_CLI_VAULT_KEY",
                b64::encode(Key::generate().as_bytes()),
            )
            .output()
            .unwrap(),
    );
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        original
    );
    let encrypted = home.read_encrypted_vault();
    for index in [0, Header::BYTES - 1, Header::BYTES, encrypted.len() - 1] {
        let mut damaged = encrypted.clone();
        damaged[index] ^= 1;
        home.write_encrypted_vault(&damaged);
        assert_eq!(failure(&home.run(&["account", "list"])), wrong_key);
        assert_eq!(home.read_encrypted_vault(), damaged);
    }
    for length in [0, Header::BYTES - 1, Header::BYTES, encrypted.len() - 1] {
        home.write_encrypted_vault(&encrypted[..length]);
        assert_eq!(failure(&home.run(&["account", "list"])), wrong_key);
        assert_eq!(home.read_encrypted_vault(), encrypted[..length]);
    }
}

#[test]
fn vault_schema_version_is_checked_after_decryption() {
    let home = TestHome::new();
    home.seed("http://localhost:8080");
    home.write_vault_document(&json!({"schema_version": 2, "state": Value::Null}));
    let original = fs::read(home.dir.path().join("vault.json")).unwrap();
    let error = failure(&home.run(&["account", "list"]));
    assert!(error.contains("cannot read CLI vault format 2; this CLI supports 1."));
    assert!(error.contains(&format!(
        "To start fresh, move {} aside, then log in again.",
        home.dir.path().canonicalize().unwrap().join("vault.json").display(),
    )));
    let output = home
        .command(&["account", "list"])
        .env(
            "ENTE_CLI_VAULT_KEY",
            b64::encode(Key::generate().as_bytes()),
        )
        .output()
        .unwrap();
    assert!(failure(&output).contains("cannot unlock CLI vault"));
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        original
    );
}

#[tokio::test]
async fn raw_api_preserves_requests_and_responses() {
    let mut origin = mockito::Server::new_async().await;
    let home = TestHome::new();
    home.seed(&origin.url());
    let secret = "--8=";
    let headers = home.dir.path().join("headers.json");
    fs::write(&headers, br#"{"Host":"different.example.org"}"#).unwrap();
    let mismatched_host = origin.mock("GET", "/host").expect(0).create_async().await;
    let output = home.run(&[
        "photos",
        "api",
        "/host",
        "--headers",
        headers.to_str().unwrap(),
    ]);
    assert!(failure(&output).contains("Host cannot redirect stored account credentials"));
    assert!(output.stdout.is_empty());
    mismatched_host.assert_async().await;

    let local_redirect = origin
        .mock("GET", "/local")
        .with_status(307)
        .with_header("location", "/bytes")
        .create_async()
        .await;
    let body = b"raw\0bytes\n";
    let response = origin
        .mock("GET", "/bytes")
        .match_header("x-auth-token", secret)
        .match_header("x-client-package", "io.ente.photos")
        .with_body(body)
        .expect(1)
        .create_async()
        .await;
    let output = home.run(&["photos", "api", "/local"]);
    assert!(failure(&output).contains("HTTP 307 Temporary Redirect"));
    assert!(output.stdout.is_empty());
    assert_eq!(
        success(home.run(&["photos", "api", &format!("{}/bytes", origin.url())])).stdout,
        body
    );
    local_redirect.assert_async().await;
    response.assert_async().await;

    fs::write(&headers, br#"{"content-type":"application/octet-stream","x-client-package":"explicit.package","x-auth-token":"explicit-token"}"#).unwrap();
    let request = origin
        .mock("PATCH", "/request")
        .match_query(mockito::Matcher::UrlEncoded("label".into(), "a & b".into()))
        .match_header("x-client-package", "explicit.package")
        .match_header("x-auth-token", "explicit-token")
        .match_header("content-type", "application/octet-stream")
        .match_body(body.to_vec())
        .with_status(422)
        .with_body(body)
        .create_async()
        .await;
    let output = home.with_input(
        &[
            "photos",
            "api",
            "/request",
            "--method",
            "patch",
            "--query",
            "label=a & b",
            "--headers",
            headers.to_str().unwrap(),
            "--body",
            "-",
        ],
        body,
    );
    failure(&output);
    assert_eq!(output.stdout, body);
    request.assert_async().await;
}

#[test]
fn private_json_errors_do_not_echo_values() {
    let mut server = mockito::Server::new();
    let ping = server
        .mock("GET", "/ping")
        .with_body(r#"{"message":"pong","id":"fixture"}"#)
        .expect(0)
        .create();
    let authentication = server
        .mock("GET", "/users/srp/attributes")
        .match_query(mockito::Matcher::Any)
        .expect(0)
        .create();
    let request = server.mock("GET", "/request").expect(0).create();
    let home = TestHome::new();
    let mut errors = Vec::new();
    for input in [
        json!({"email": "fixture@example.org", "password": 987654321}),
        json!({"email": "fixture@example.org", "password": "secret", "otp": 987654321}),
        json!({"email": "fixture@example.org", "password": "secret", "totp": 987654321}),
        json!({"email": "fixture@example.org", "password": "secret", "private-987654321": "secret"}),
        json!("private-987654321"),
    ] {
        let output = home.with_input(
            &[
                "account",
                "login",
                "--app",
                "photos",
                "--host",
                &server.url(),
                "--input",
                "-",
            ],
            &serde_json::to_vec(&input).unwrap(),
        );
        assert!(output.stdout.is_empty());
        let error = failure(&output);
        assert!(error.contains("input must contain"), "{error}");
        errors.push(error);
    }
    assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 0);
    home.seed(&server.url());
    let original = fs::read(home.dir.path().join("vault.json")).unwrap();
    for input in [
        json!({"x-auth-token": 987654321}),
        json!("private-987654321"),
    ] {
        let output = home.with_input(
            &["photos", "api", "/request", "--headers", "-"],
            &serde_json::to_vec(&input).unwrap(),
        );
        assert!(output.stdout.is_empty());
        let error = failure(&output);
        assert!(error.contains("headers must be a JSON object"), "{error}");
        errors.push(error);
    }
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        original
    );
    let mut state = home.read_vault();
    state["accounts"][0]["sessions"]["photos"]["token"] = json!("private-987654321");
    home.write_vault(&state);
    let invalid = fs::read(home.dir.path().join("vault.json")).unwrap();
    let output = home.run(&["account", "list"]);
    assert!(output.stdout.is_empty());
    errors.push(failure(&output));
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        invalid
    );
    ping.assert();
    authentication.assert();
    request.assert();
    for error in errors {
        assert!(
            !error.contains("987654321"),
            "private JSON value leaked: {error}"
        );
        assert!(
            error.contains("line ") && error.contains("column "),
            "{error}"
        );
    }
}

#[test]
fn logout_reconciles_remote_and_local_session_state() {
    let mut server = mockito::Server::new();
    let revoked = server
        .mock("POST", "/users/logout")
        .match_header("x-auth-token", "--8=")
        .match_header("x-client-package", "io.ente.photos")
        .with_status(401)
        .expect(3)
        .create();
    let home = TestHome::new();
    home.seed(&server.url());
    let mut state = home.read_vault();
    let mut account = home.json(&["account", "view", "--account", "fixture"]);
    assert_eq!(
        success(home.run(&["account", "logout", "--app", "photos"])).stdout,
        b"Logged out of Ente Photos. Removed account \"fixture\" from this device.\n"
    );
    assert_eq!(home.json(&["account", "list"]), json!([]));
    assert_eq!(home.read_vault(), json!({"accounts": [], "selected": null}));
    assert_eq!(
        fs::read_dir(home.dir.path().join("accounts"))
            .unwrap()
            .count(),
        0
    );
    state["accounts"][0]["sessions"]["auth"] = json!({"token": [2]});
    home.write_vault(&state);
    account["apps"] = json!(["auth"]);
    assert_eq!(
        home.json(&["account", "logout", "--app", "photos"]),
        json!({"account": account, "app": "photos", "remoteLogout": true})
    );
    assert_eq!(
        home.json(&["account", "view", "--account", "fixture"]),
        account
    );
    state["accounts"][0]["sessions"]
        .as_object_mut()
        .unwrap()
        .remove("auth");
    home.write_vault(&state);
    account["apps"] = json!([]);
    account["selected"] = json!(false);
    assert_eq!(
        home.json(&["account", "logout", "--app", "photos"]),
        json!({"account": account, "app": "photos", "remoteLogout": true})
    );
    assert_eq!(home.read_vault(), json!({"accounts": [], "selected": null}));
    revoked.assert();

    let unavailable = server
        .mock("POST", "/users/logout")
        .match_header("x-auth-token", "--8=")
        .with_status(403)
        .create();
    let home = TestHome::new();
    home.seed(&server.url());
    let before = fs::read(home.dir.path().join("vault.json")).unwrap();
    failure(&home.run(&["account", "logout", "--app", "photos"]));
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        before
    );
    unavailable.assert();
}

#[test]
fn account_logout_revokes_every_app_before_removing_the_account() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let mut state = home.read_vault();
    state["accounts"][0]["sessions"]["locker"] = json!({"token": [1]});
    state["accounts"][0]["sessions"]["auth"] = json!({"token": [2]});
    home.write_vault(&state);
    let mut account = home.json(&["account", "view", "--account", "fixture"]);
    account["apps"] = json!([]);
    account["selected"] = json!(false);
    let photos = server
        .mock("POST", "/users/logout")
        .match_header("x-auth-token", "--8=")
        .match_header("x-client-package", "io.ente.photos")
        .expect(2)
        .create();
    let locker_token = b64::encode_url_safe(&[1]);
    let locker = server
        .mock("POST", "/users/logout")
        .match_header("x-auth-token", locker_token.as_str())
        .match_header("x-client-package", "io.ente.locker")
        .expect(2)
        .create();
    let auth_token = b64::encode_url_safe(&[2]);
    let auth = server
        .mock("POST", "/users/logout")
        .match_header("x-auth-token", auth_token.as_str())
        .match_header("x-client-package", "io.ente.auth")
        .expect(2)
        .create();

    assert_eq!(
        success(home.run(&["account", "logout", "--account", "fixture"])).stdout,
        b"Logged out of Ente Photos, Ente Locker, and Ente Auth. Removed account \"fixture\" from this device.\n"
    );
    assert_eq!(home.read_vault(), json!({"accounts": [], "selected": null}));
    home.write_vault(&state);
    assert_eq!(
        home.json(&["account", "logout", "--account", "fixture"]),
        json!({"account": account, "apps": ["photos", "locker", "auth"], "remoteLogout": true})
    );
    home.write_vault(&state);
    assert_eq!(
        home.json(&[
            "account",
            "logout",
            "--account",
            "fixture",
            "--local",
            "--offline"
        ]),
        json!({"account": account, "apps": ["photos", "locker", "auth"], "remoteLogout": false})
    );
    state["accounts"][0]["sessions"] = json!({});
    home.write_vault(&state);
    assert_eq!(
        home.json(&["account", "logout", "--account", "fixture"]),
        json!({"account": account, "apps": [], "remoteLogout": true})
    );
    home.write_vault(&state);
    assert_eq!(
        success(home.run(&["account", "logout", "--account", "fixture", "--local"])).stdout,
        b"Removed account \"fixture\" from this device.\n"
    );
    assert_eq!(home.read_vault(), json!({"accounts": [], "selected": null}));
    photos.assert();
    locker.assert();
    auth.assert();
}

#[test]
fn account_logout_preserves_sessions_that_it_could_not_revoke() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let mut state = home.read_vault();
    state["accounts"][0]["sessions"]["locker"] = json!({"token": [1]});
    state["accounts"][0]["sessions"]["auth"] = json!({"token": [2]});
    home.write_vault(&state);
    let photos = server
        .mock("POST", "/users/logout")
        .match_header("x-client-package", "io.ente.photos")
        .create();
    let locker = server
        .mock("POST", "/users/logout")
        .match_header("x-client-package", "io.ente.locker")
        .with_status(403)
        .create();
    let auth = server
        .mock("POST", "/users/logout")
        .match_header("x-client-package", "io.ente.auth")
        .expect(0)
        .create();

    let output = home.run(&["account", "logout", "--account", "fixture"]);
    assert!(output.stdout.is_empty());
    let error = failure(&output);
    assert!(error.contains("cannot log out of Ente Locker for \"fixture\": HTTP 403"));
    assert!(error.contains("Still logged in: Ente Locker and Ente Auth."));
    let state = home.read_vault();
    let sessions = &state["accounts"][0]["sessions"];
    assert!(sessions.get("photos").is_none());
    assert!(sessions.get("locker").is_some());
    assert!(sessions.get("auth").is_some());

    assert_eq!(
        success(home.run(&["account", "logout", "--account", "fixture", "--local"])).stdout,
        b"Removed account \"fixture\" from this device. Server logout was skipped.\n"
    );
    assert_eq!(home.read_vault(), json!({"accounts": [], "selected": null}));
    photos.assert();
    locker.assert();
    auth.assert();
}

#[test]
fn account_updates_preserve_identity_and_selection() {
    let home = TestHome::new();
    home.seed("http://localhost:8080");
    assert_eq!(
        success(home.run(&["account", "view", "--account", "fixture"])).stdout,
        b"Name       fixture\nEmail      fixture@example.org\nHost       http://localhost:8080\nLogged in  photos\nSelected   yes\nID         9007199254740993\n"
    );
    let account = json!({
        "id": "9007199254740993", "name": "fixture", "email": "fixture@example.org",
        "host": "http://localhost:8080", "apps": ["photos"], "selected": true
    });
    assert_eq!(home.json(&["account", "list"]), json!([account]));
    assert_eq!(
        home.json(&["accounts", "view", "--account", "fixture"]),
        account
    );
    assert_eq!(home.json(&["account", "view"]), account);
    let mut state = home.read_vault();
    let mut second = state["accounts"][0].clone();
    second["storage_id"] = json!("f6579aae-83ef-4f28-965e-8d34883d3fe5");
    second["name"] = json!("second");
    second["sessions"] = json!({"locker": {"token": [1]}});
    state["accounts"].as_array_mut().unwrap().push(second);
    home.write_vault(&state);

    success(home.run(&["account", "rename", "renamed"]));
    success(home.run(&["account", "rename", "second", "other"]));
    state["accounts"][0]["name"] = json!("renamed");
    state["accounts"][1]["name"] = json!("other");
    assert_eq!(home.read_vault(), state);
    failure(&home.run(&["photos", "album", "list", "--account", "other"]));
    let original = fs::read(home.dir.path().join("vault.json")).unwrap();
    failure(&home.run(&["account", "rename", "other", "renamed"]));
    assert_eq!(
        fs::read(home.dir.path().join("vault.json")).unwrap(),
        original
    );
    let before = home.read_encrypted_vault();
    success(home.run(&["account", "switch", "other"]));
    state["selected"] = state["accounts"][1]["storage_id"].clone();
    assert_eq!(home.read_vault(), state);
    let after = home.read_encrypted_vault();
    assert_ne!(
        before[..Header::BYTES],
        after[..Header::BYTES],
        "vault rewrite reused its nonce"
    );
    success(home.run(&["account", "switch", "other"]));
    assert_eq!(home.read_encrypted_vault(), after);
    state["selected"] = Value::Null;
    home.write_vault(&state);
    let before = home.read_encrypted_vault();
    let output = home.with_input(
        &["account", "login", "--app", "auth", "--input", "-"],
        br#"{"email":"fixture@example.org","password":"password"}"#,
    );
    assert!(failure(&output).contains("no account selected"));
    assert_eq!(home.read_encrypted_vault(), before);
}

#[test]
fn account_token_reads_the_requested_saved_login() {
    let home = TestHome::new();
    let args = [
        "account",
        "token",
        "--app",
        "photos",
        "--offline",
        "--no-input",
    ];
    home.seed("http://127.0.0.1:1");
    let mut state = home.read_vault();
    state["selected"] = Value::Null;
    home.write_vault(&state);
    let vault = home.dir.path().join("vault.json");
    let before = fs::read(&vault).unwrap();
    let output = success(home.run(&args));
    assert_eq!(output.stdout, b"--8=\n");
    assert!(output.stderr.is_empty());
    assert_eq!(home.json(&args), json!({"token": "--8="}));
    assert_eq!(fs::read(&vault).unwrap(), before);

    let mut other = state["accounts"][0].clone();
    other["storage_id"] = json!("f6579aae-83ef-4f28-965e-8d34883d3fe5");
    other["name"] = json!("other");
    other["sessions"] = json!({"locker": {"token": [1]}});
    state["selected"] = other["storage_id"].clone();
    state["accounts"][0]["sessions"]["auth"] = json!({"token": [255]});
    state["accounts"].as_array_mut().unwrap().push(other);
    home.write_vault(&state);
    let before = fs::read(&vault).unwrap();
    assert_eq!(
        home.json(&["account", "token", "--app", "locker"]),
        json!({"token": "AQ=="})
    );
    assert_eq!(
        home.json(&["account", "token", "--account", "fixture", "--app", "auth"]),
        json!({"token": "_w=="})
    );
    let missing_login = home.run(&args);
    assert!(failure(&missing_login).contains(
        "account \"other\" is not logged into Ente Photos; use account login --account \"other\" --app photos"
    ));
    assert!(missing_login.stdout.is_empty());
    let explicit_login = home.run(&[
        "account",
        "token",
        "--app",
        "locker",
        "--account",
        "fixture",
    ]);
    assert!(failure(&explicit_login).contains(
        "account \"fixture\" is not logged into Ente Locker; use account login --account \"fixture\" --app locker"
    ));
    assert!(explicit_login.stdout.is_empty());
    let missing_account = home
        .command(&args)
        .args(["--account", "missing"])
        .output()
        .unwrap();
    assert!(failure(&missing_account).contains("no account named \"missing\"; use account list"));
    assert!(missing_account.stdout.is_empty());
    assert_eq!(fs::read(&vault).unwrap(), before);

    state["selected"] = Value::Null;
    home.write_vault(&state);
    let before = fs::read(&vault).unwrap();
    let ambiguous = home.run(&args);
    assert!(
        failure(&ambiguous).contains(
            "no account selected; use account switch <NAME> or name an account explicitly"
        )
    );
    assert!(ambiguous.stdout.is_empty());
    let (reader, writer) = std::io::pipe().unwrap();
    drop(reader);
    let write_failure = home
        .command(&args)
        .args(["--account", "fixture"])
        .stdout(writer)
        .output()
        .unwrap();
    let error = failure(&write_failure);
    assert!(!error.contains("--8="));
    assert_eq!(fs::read(&vault).unwrap(), before);
}

struct TestHome {
    dir: TempDir,
    key: Key,
}

#[test]
#[ignore = "requires accessible native secret storage; creates and removes a disposable keyring entry"]
fn native_keyring_survives_separate_processes() {
    let mut home = TestHome::new();
    let path = fs::canonicalize(home.dir.path()).unwrap();
    let entry = keyring::Entry::new("io.ente.cli", &path.to_string_lossy()).unwrap();
    assert!(matches!(entry.get_secret(), Err(keyring::Error::NoEntry)));
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        success(
            home.command(&["account", "list"])
                .env_remove("ENTE_CLI_VAULT_KEY")
                .output()
                .unwrap(),
        );
        assert!(matches!(entry.get_secret(), Err(keyring::Error::NoEntry)));
        assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 0);
        let mut server = mockito::Server::new();
        let ping = server.mock("GET", "/ping").with_status(503).create();
        let input = home.dir.path().join("login.json");
        fs::write(
            &input,
            br#"{"email":"fixture@example.org","password":"secret"}"#,
        )
        .unwrap();
        let output = home
            .command(&[
                "account",
                "login",
                "--app",
                "photos",
                "--host",
                &server.url(),
            ])
            .args(["--input", input.to_str().unwrap()])
            .env_remove("ENTE_CLI_VAULT_KEY")
            .output()
            .unwrap();
        assert!(failure(&output).contains("cannot reach the selected Ente server"));
        ping.assert();
        home.key = Key::try_from_slice(&entry.get_secret().unwrap()).unwrap();
        home.seed("http://localhost:8080");
        success(
            home.command(&["account", "rename", "fixture", "native"])
                .env_remove("ENTE_CLI_VAULT_KEY")
                .output()
                .unwrap(),
        );
        let output = success(
            home.command(&["account", "view", "--account", "native", "--json"])
                .env_remove("ENTE_CLI_VAULT_KEY")
                .output()
                .unwrap(),
        );
        assert_eq!(
            serde_json::from_slice::<Value>(&output.stdout).unwrap()["name"],
            "native"
        );
    }));
    let cleanup = entry.delete_credential();
    if let Err(panic) = result {
        std::panic::resume_unwind(panic);
    }
    cleanup.unwrap();
}

impl TestHome {
    fn new() -> Self {
        Self {
            dir: tempfile::tempdir().unwrap(),
            key: Key::generate(),
        }
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_ente-cli-next"));
        command
            .env_clear()
            .env("ENTE_CLI_HOME", self.dir.path())
            .env("ENTE_CLI_VAULT_KEY", b64::encode(self.key.as_bytes()))
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(target_os = "linux")]
        if let Some(address) = std::env::var_os("DBUS_SESSION_BUS_ADDRESS") {
            command.env("DBUS_SESSION_BUS_ADDRESS", address);
        }
        #[cfg(windows)]
        if let Some(root) = std::env::var_os("SystemRoot") {
            command.env("SystemRoot", root);
        }
        command
    }

    fn run(&self, args: &[&str]) -> Output {
        self.command(args).output().unwrap()
    }

    fn with_input(&self, args: &[&str], input: &[u8]) -> Output {
        let mut child = self.command(args).stdin(Stdio::piped()).spawn().unwrap();
        child.stdin.take().unwrap().write_all(input).unwrap();
        child.wait_with_output().unwrap()
    }

    fn json(&self, args: &[&str]) -> Value {
        let output = success(self.command(args).arg("--json").output().unwrap());
        serde_json::from_slice(&output.stdout).unwrap()
    }

    fn seed(&self, origin: &str) {
        let id = "e6b355f0-5d4d-4fc3-b32c-a6c8f52b8210";
        self.write_vault(&json!({
            "selected": id,
            "accounts": [{
                "storage_id": id, "db_key": vec![42u8; 32], "name": "fixture", "email": "fixture@example.org",
                "origin": origin, "user_id": 9007199254740993i64,
                "identity": {
                    "master_key": vec![0u8; 32], "recovery_key": vec![0u8; 32],
                    "secret_key": vec![0u8; 32]
                },
                "sessions": {"photos": {"token": [0xfb, 0xef]}}
            }]
        }));
    }

    fn write_vault(&self, state: &Value) {
        self.write_vault_document(&json!({"schema_version": 1, "state": state}));
    }

    fn write_vault_document(&self, document: &Value) {
        let plaintext = serde_json::to_vec(document).unwrap();
        self.write_encrypted_vault(&blob::encrypt_combined(&plaintext, &self.key).unwrap());
    }

    fn write_encrypted_vault(&self, encrypted: &[u8]) {
        fs::write(
            self.dir.path().join("vault.json"),
            serde_json::to_vec(&json!({"data": b64::encode(encrypted)})).unwrap(),
        )
        .unwrap();
    }

    fn read_encrypted_vault(&self) -> Vec<u8> {
        let stored: Value =
            serde_json::from_slice(&fs::read(self.dir.path().join("vault.json")).unwrap()).unwrap();
        b64::decode(stored["data"].as_str().unwrap()).unwrap()
    }

    fn read_vault(&self) -> Value {
        let plaintext = blob::decrypt_combined(&self.read_encrypted_vault(), &self.key).unwrap();
        let stored: Value = serde_json::from_slice(&plaintext).unwrap();
        assert_eq!(stored["schema_version"], 1);
        stored["state"].clone()
    }
}

fn success(output: Output) -> Output {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

fn failure(output: &Output) -> String {
    assert!(!output.status.success(), "command unexpectedly succeeded");
    String::from_utf8_lossy(&output.stderr).into_owned()
}

mod account;

mod admin;

#[cfg(feature = "museum")]
mod admin_museum;

mod auth;

mod export_process;

mod export_sources;

mod files;

#[cfg(feature = "museum")]
mod museum;

mod paste;
