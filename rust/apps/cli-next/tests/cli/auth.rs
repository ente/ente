use ente_core::crypto::secretbox;
use mockito::{Matcher, Mock, Server};
use uuid::Uuid;

use super::*;

const URI: &str = "otpauth://totp/Test:account?secret=JBSWY3DPEHPK3PXP&x=%252C&codeDisplay=%7B%22trashed%22%3Atrue%7D";
const EXPORT: &[&str] = &["auth", "export", "--plaintext", "--output", "-", "--json"];

fn seed(home: &TestHome, origin: &str) {
    home.seed(origin);
    let mut state = home.read_vault();
    state["accounts"][0]["sessions"]["auth"] = state["accounts"][0]["sessions"]["photos"].clone();
    home.write_vault(&state);
}

fn key_response(server: &mut Server, key: &Key) -> Mock {
    let wrapped = secretbox::encrypt(key.as_bytes(), &Key::from_bytes([0; 32]));
    server.mock("GET", "/authenticator/key")
        .match_header("x-client-package", "io.ente.auth")
        .match_header("x-auth-token", "--8=")
        .with_body(json!({"encryptedKey": b64::encode(&wrapped.encrypted_data), "header": b64::encode(wrapped.nonce.as_bytes())}).to_string())
        .expect_at_least(1).create()
}

fn entity(id: u128, updated_at: i64, value: &Value, key: &Key) -> Value {
    let encrypted = blob::encrypt(&serde_json::to_vec(value).unwrap(), key).unwrap();
    json!({"id": Uuid::from_u128(id), "updatedAt": updated_at, "isDeleted": false,
        "encryptedData": b64::encode(&encrypted.encrypted_data), "header": b64::encode(encrypted.decryption_header.as_bytes())})
}

fn deleted(id: u128, updated_at: i64) -> Value {
    json!({"id": Uuid::from_u128(id), "updatedAt": updated_at, "isDeleted": true, "encryptedData": null, "header": null})
}

fn page(server: &mut Server, since: i64, rows: Vec<Value>) -> Mock {
    server
        .mock("GET", "/authenticator/entity/diff")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("sinceTime".into(), since.to_string()),
            Matcher::UrlEncoded("limit".into(), "5000".into()),
        ]))
        .with_body(json!({"diff": rows, "timestamp": 9999999999_i64}).to_string())
        .create()
}

#[test]
fn code_reads_refresh_select_and_render_without_a_backup() {
    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let uri = |name: &str| json!(format!("otpauth://totp/{name}?secret=MY"));
    let initial = page(
        &mut server,
        0,
        vec![
            entity(1, 10, &uri("GitHub:alice@example.com"), &key),
            entity(2, 10, &uri("GitHub:bob@example.com"), &key),
            entity(3, 10, &json!(format!("{URI}#suffix")), &key),
            entity(4, 10, &json!("otpauth://totp/Steam:alice?secret=MY"), &key),
            entity(
                5,
                10,
                &json!({"rawData": "otpauth://hotp/Work:a%2B%252C#tag?secret=MY&counter=7"}),
                &key,
            ),
        ],
    );
    let listed = success(home.run(&["auth", "code", "list", "--limit", "1", "--json"]));
    let rows: Value = serde_json::from_slice(&listed.stdout).unwrap();
    assert_eq!(
        rows,
        json!([{"id": Uuid::from_u128(1), "name": "GitHub (alice@example.com)",
        "issuer": "GitHub", "accountName": "alice@example.com", "type": "totp"}])
    );
    assert!(String::from_utf8_lossy(&listed.stderr).contains("Showing first 1"));
    initial.assert();
    initial.remove();
    let view = |query: &str| {
        home.json(&[
            "auth",
            "code",
            "view",
            query,
            "--offline",
            "--account",
            "fixture",
        ])
    };
    for query in [
        "BOB gitHUB",
        "GitHub (bob@example.com)",
        &Uuid::from_u128(2).to_string(),
    ] {
        let result = view(query);
        assert_eq!(result["id"], Uuid::from_u128(2).to_string());
        assert_eq!(result["otp"].as_str().unwrap().len(), 6);
        let expiry =
            chrono::DateTime::parse_from_rfc3339(result["validUntil"].as_str().unwrap()).unwrap();
        assert_eq!(expiry.timestamp() % 30, 0);
        assert!(result["validUntil"].as_str().unwrap().ends_with('Z'));
    }
    let ambiguous = home.run(&["auth", "code", "view", "github", "--offline"]);
    let error = failure(&ambiguous);
    assert!(
        error.contains("code \"github\" is ambiguous")
            && error.contains("GitHub (alice@example.com)")
            && error.contains(&Uuid::from_u128(2).to_string())
    );
    assert!(ambiguous.stdout.is_empty());
    let missing = home.run(&["auth", "code", "view", "missing", "--offline"]);
    assert!(failure(&missing).contains("no code matches \"missing\""));
    assert!(missing.stdout.is_empty());
    let all = home.json(&["auth", "code", "list", "--all", "--offline"]);
    assert_eq!(all.as_array().unwrap().len(), 4);
    assert_eq!(all[2]["type"], "steam");
    assert_eq!(all[3]["name"], "Work (a+%2C#tag)");
    assert_eq!(view("steam")["otp"].as_str().unwrap().len(), 5);
    assert!(
        failure(&home.run(&["auth", "code", "view", "Work", "--offline"]))
            .contains("HOTP code generation is not supported")
    );
    assert!(
        failure(&home.run(&[
            "auth",
            "code",
            "view",
            &Uuid::from_u128(3).to_string(),
            "--offline"
        ]))
        .contains("in Trash")
    );
    let text = success(home.run(&["auth", "code", "view", "alice github", "--offline"]));
    let text = String::from_utf8(text.stdout).unwrap();
    assert!(text.starts_with("GitHub (alice@example.com)\n"));
    assert!(text.contains("\nValid until "));

    let changed = page(
        &mut server,
        9,
        vec![
            entity(2, 20, &uri("Work:bob@example.com"), &key),
            entity(6, 20, &uri("GitHub:(alice@example.com)"), &key),
        ],
    );
    assert_eq!(
        home.json(&["auth", "code", "view", "bob work"])["name"],
        "Work (bob@example.com)"
    );
    changed.assert();
    changed.remove();
    let copied = home.run(&[
        "auth",
        "code",
        "view",
        "GitHub (alice@example.com)",
        "--offline",
    ]);
    assert!(failure(&copied).contains("code \"GitHub (alice@example.com)\" is ambiguous"));
    assert_eq!(
        home.json(&[
            "auth",
            "code",
            "list",
            "--search",
            "GitHub (alice@example.com)",
            "--offline"
        ])
        .as_array()
        .unwrap()
        .len(),
        2
    );
    assert_eq!(
        home.json(&[
            "auth",
            "code",
            "list",
            "--search",
            "BOB work",
            "--limit",
            "1",
            "--offline"
        ])[0]["id"],
        Uuid::from_u128(2).to_string()
    );
    let unavailable = server
        .mock("GET", "/authenticator/entity/diff")
        .match_query(Matcher::Any)
        .with_status(400)
        .create();
    let failed = home.run(&["auth", "code", "view", "bob"]);
    failure(&failed);
    assert!(failed.stdout.is_empty());
    unavailable.assert();
    key_request.assert();
    drop(server);
    assert_eq!(view("bob")["name"], "Work (bob@example.com)");
}

#[test]
fn unreadable_codes_block_text_selection_but_not_ids_or_list_limits() {
    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let initial = page(
        &mut server,
        0,
        vec![
            entity(1, 10, &json!("private-secret"), &key),
            entity(2, 10, &json!("otpauth://totp/GitHub:alice?secret=MY"), &key),
            entity(3, 10, &json!("otpauth://totp/Work:bob?secret=MY"), &key),
        ],
    );
    let listed = home.run(&["auth", "code", "list", "--limit", "1", "--json"]);
    let error = failure(&listed);
    assert!(
        error.contains("Auth code list is incomplete")
            && error.contains("1 unreadable Auth code")
            && error.contains(&Uuid::from_u128(1).to_string())
    );
    assert!(!error.contains("private-secret"));
    assert_eq!(
        serde_json::from_slice::<Value>(&listed.stdout).unwrap()[0]["id"],
        Uuid::from_u128(2).to_string()
    );
    for query in ["GitHub (alice)", "github", "missing"] {
        let output = home.run(&["auth", "code", "view", query, "--offline"]);
        let error = failure(&output);
        assert!(error.contains("unreadable Auth code"));
        assert!(error.contains(&format!(
            "cannot resolve code {query:?}; select a known code ID"
        )));
        assert!(output.stdout.is_empty());
    }
    let id = Uuid::from_u128(1).to_string();
    let unreadable = home.run(&["auth", "code", "view", &id, "--offline"]);
    assert!(
        failure(&unreadable).contains(&format!("cannot read code {id:?}: 1 unreadable Auth code"))
    );
    assert!(unreadable.stdout.is_empty());
    let result = home.json(&[
        "auth",
        "code",
        "view",
        &Uuid::from_u128(2).to_string(),
        "--offline",
    ]);
    assert_eq!(result["name"], "GitHub (alice)");
    assert_eq!(
        home.json(&[
            "auth",
            "code",
            "list",
            "--search",
            &Uuid::from_u128(2).to_string(),
            "--offline"
        ])[0]["name"],
        "GitHub (alice)"
    );
    assert!(
        failure(&home.run(&["auth", "code", "view", "  ", "--offline"]))
            .contains("supply a code ID or search text")
    );
    initial.assert();
    key_request.assert();
}

#[test]
fn refresh_keeps_progress_and_refuses_unreadable_codes_until_updated() {
    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    assert!(
        failure(&home.command(EXPORT).arg("--offline").output().unwrap()).contains("no local data")
    );
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let initial = page(
        &mut server,
        0,
        vec![
            entity(2, 10, &json!(URI), &key),
            entity(1, 10, &json!(URI), &key),
        ],
    );
    let first = success(home.run(EXPORT));
    assert_eq!(first.stdout, format!("{URI}\n{URI}\n").as_bytes());
    initial.assert();
    initial.remove();

    let mut unreadable = entity(1, 30, &json!(URI), &key);
    unreadable["encryptedData"] = json!("broken");
    let malformed = entity(
        3,
        30,
        &json!({"rawData": "private-secret", "display": false}),
        &key,
    );
    let changed_uri = "otpauth://hotp/Updated?secret=JBSWY3DPEHPK3PXP&counter=42";
    let changed = page(
        &mut server,
        9,
        vec![
            entity(2, 20, &json!(changed_uri), &key),
            unreadable,
            malformed,
        ],
    );
    let output_dir = tempfile::tempdir().unwrap();
    fs::write(
        output_dir.path().join("ente-auth-2026-01-01.txt"),
        &first.stdout,
    )
    .unwrap();
    let failed = home.run(&[
        "auth",
        "export",
        output_dir.path().to_str().unwrap(),
        "--plaintext",
        "--json",
    ]);
    let stderr = failure(&failed);
    assert!(stderr.contains("2 unreadable Auth codes"));
    assert!(stderr.contains(&Uuid::from_u128(1).to_string()));
    assert!(!stderr.contains("private-secret"));
    assert!(!stderr.contains("JBSWY3DPEHPK3PXP"));
    assert_eq!(
        serde_json::from_slice::<Value>(&failed.stdout).unwrap(),
        json!({"output": null, "codes": 0, "failures": {"total": 2}})
    );
    assert_eq!(fs::read_dir(output_dir.path()).unwrap().count(), 1);
    changed.assert();
    changed.remove();
    let offline = home.command(EXPORT).arg("--offline").output().unwrap();
    assert!(failure(&offline).contains("2 unreadable"));
    assert!(offline.stdout.is_empty());

    let recovered = page(
        &mut server,
        29,
        vec![entity(1, 40, &json!(URI), &key), deleted(3, 40)],
    );
    let result = success(home.run(EXPORT));
    assert_eq!(result.stdout, format!("{URI}\n{changed_uri}\n").as_bytes());
    recovered.assert();
    recovered.remove();
    let failed_refresh = server
        .mock("GET", "/authenticator/entity/diff")
        .match_query(Matcher::Any)
        .with_status(400)
        .create();
    let failed = home.run(EXPORT);
    failure(&failed);
    assert!(failed.stdout.is_empty());
    failed_refresh.assert();
    key_request.assert();
    drop(server);
    assert_eq!(
        success(
            home.command(EXPORT)
                .args(["--offline", "--account", "fixture"])
                .output()
                .unwrap()
        )
        .stdout,
        result.stdout
    );
}

#[test]
fn overlapping_pages_resume_and_read_only_the_final_current_set() {
    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let template = entity(1, 10, &json!(URI), &key);
    let mut rows: Vec<_> = (1..=4999)
        .map(|id| {
            let mut row = template.clone();
            row["id"] = json!(Uuid::from_u128(id));
            row
        })
        .collect();
    rows[0]["encryptedData"] = json!("unreadable until permanently deleted");
    rows[4998]["encryptedData"] = json!("unreadable until replaced");
    rows.push(deleted(5000, 20));
    let first = page(&mut server, 0, rows);
    let interrupted = server
        .mock("GET", "/authenticator/entity/diff")
        .match_query(Matcher::UrlEncoded("sinceTime".into(), "19".into()))
        .with_status(400)
        .create();
    let failed = home.run(EXPORT);
    failure(&failed);
    assert!(failed.stdout.is_empty());
    first.assert();
    interrupted.assert();
    first.remove();
    interrupted.remove();
    let offline = home.command(EXPORT).arg("--offline").output().unwrap();
    assert!(failure(&offline).contains("incomplete"));
    let second = page(
        &mut server,
        19,
        vec![
            deleted(5000, 20),
            entity(5001, 20, &json!(URI), &key),
            deleted(1, 21),
            entity(4999, 21, &json!(URI), &key),
        ],
    );
    let result = success(home.run(EXPORT));
    assert_eq!(result.stdout, format!("{URI}\n").repeat(4999).as_bytes());
    second.assert();
    key_request.assert();
}

#[test]
fn key_resets_and_unadvanceable_pages_cannot_publish_stale_data() {
    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let initial = page(&mut server, 0, vec![entity(1, 10, &json!(URI), &key)]);
    success(home.run(EXPORT));
    initial.assert();
    initial.remove();
    key_request.remove();
    let missing = server
        .mock("GET", "/authenticator/key")
        .with_status(404)
        .create();
    assert!(success(home.run(EXPORT)).stdout.is_empty());
    assert!(
        success(home.command(EXPORT).arg("--offline").output().unwrap())
            .stdout
            .is_empty()
    );
    missing.assert();
    missing.remove();

    let next_key = Key::generate();
    let next = key_response(&mut server, &next_key);
    let template = entity(1, 10, &json!(URI), &next_key);
    let rows: Vec<_> = (1..=5000)
        .map(|id| {
            let mut row = template.clone();
            row["id"] = json!(Uuid::from_u128(id));
            row
        })
        .collect();
    let first = page(&mut server, 0, rows.clone());
    let stuck = page(&mut server, 9, rows);
    let failed = home.run(EXPORT);
    assert!(failure(&failed).contains("the server's next page did not advance"));
    assert!(failed.stdout.is_empty());
    assert!(
        failure(&home.command(EXPORT).arg("--offline").output().unwrap()).contains("incomplete")
    );
    first.assert();
    stuck.assert();
    first.remove();
    stuck.remove();
    next.remove();
    let reset = key_response(&mut server, &Key::generate());
    let interrupted = server
        .mock("GET", "/authenticator/entity/diff")
        .match_query(Matcher::UrlEncoded("sinceTime".into(), "0".into()))
        .with_status(400)
        .create();
    failure(&home.run(EXPORT));
    assert!(
        failure(&home.command(EXPORT).arg("--offline").output().unwrap()).contains("incomplete")
    );
    interrupted.assert();
    interrupted.remove();
    let empty = page(&mut server, 0, vec![]);
    assert!(success(home.run(EXPORT)).stdout.is_empty());
    empty.assert();
    reset.assert();
}

#[test]
fn encrypted_export_and_independent_decrypt_keep_artifacts_separate_from_summaries() {
    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let initial = page(&mut server, 0, vec![entity(1, 10, &json!(URI), &key)]);
    let plain = success(
        home.command(EXPORT)
            .arg("--no-input")
            .env("ENTE_CLI_PASSWORD", "")
            .output()
            .unwrap(),
    )
    .stdout;
    initial.assert();
    initial.remove();
    let directory = tempfile::tempdir().unwrap();
    let nested = success(
        home.command(&[
            "auth",
            "export",
            "nested/backups",
            "--offline",
            "--plaintext",
            "--json",
        ])
        .current_dir(directory.path())
        .output()
        .unwrap(),
    );
    let nested: Value = serde_json::from_slice(&nested.stdout).unwrap();
    assert_eq!(
        fs::read(directory.path().join(nested["output"].as_str().unwrap())).unwrap(),
        plain
    );
    let encrypted = directory.path().join("backup.json");
    let plaintext_file = directory.path().join("backup.txt");
    let plain_summary = home.json(&[
        "auth",
        "export",
        "--offline",
        "--plaintext",
        "--output",
        plaintext_file.to_str().unwrap(),
    ]);
    assert_eq!(plain_summary["codes"], 1);
    assert_eq!(fs::read(plaintext_file).unwrap(), plain);
    let password = "  independent export password  ";
    let result = success(
        home.command(&[
            "auth",
            "export",
            "--offline",
            "--output",
            encrypted.to_str().unwrap(),
            "--json",
        ])
        .arg("--no-input")
        .env("ENTE_CLI_PASSWORD", password)
        .output()
        .unwrap(),
    );
    let summary: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(summary["codes"], 1);
    assert_eq!(summary["failures"]["total"], 0);
    let encoded = fs::read(&encrypted).unwrap();
    let stream = success(
        home.command(&["auth", "export", "--offline", "--output", "-", "--json"])
            .env("ENTE_CLI_PASSWORD", password)
            .output()
            .unwrap(),
    );
    let stream: Value = serde_json::from_slice(&stream.stdout).unwrap();
    assert_eq!(stream["version"], 1);
    assert!(stream.get("codes").is_none());
    assert!(stream["encryptedData"].is_string());
    let restore = TestHome::new();
    let absent_home = restore.dir.path().join("absent");
    let command = || {
        let mut command =
            restore.command(&["auth", "decrypt", encrypted.to_str().unwrap(), "--json"]);
        command
            .arg("--no-input")
            .env_remove("ENTE_CLI_VAULT_KEY")
            .env("ENTE_CLI_HOME", &absent_home)
            .env("ENTE_CLI_PASSWORD", password);
        command
    };
    assert_eq!(success(command().output().unwrap()).stdout, plain);
    assert!(!absent_home.exists());
    let output = directory.path().join("restored.txt");
    let summary = success(
        command()
            .args(["--output", output.to_str().unwrap()])
            .output()
            .unwrap(),
    );
    assert_eq!(
        serde_json::from_slice::<Value>(&summary.stdout).unwrap()["output"],
        output.to_string_lossy().as_ref()
    );
    assert_eq!(fs::read(&output).unwrap(), plain);
    failure(
        &command()
            .args(["--output", output.to_str().unwrap()])
            .output()
            .unwrap(),
    );
    assert_eq!(fs::read(&output).unwrap(), plain);
    failure(
        &command()
            .args(["--output", encrypted.to_str().unwrap()])
            .output()
            .unwrap(),
    );
    assert_eq!(fs::read(&encrypted).unwrap(), encoded);
    let wrong = command()
        .env("ENTE_CLI_PASSWORD", "wrong")
        .output()
        .unwrap();
    assert!(failure(&wrong).contains(&format!("cannot decrypt {}: ", encrypted.display())));
    assert!(wrong.stdout.is_empty());
    let mut damaged: Value = serde_json::from_slice(&encoded).unwrap();
    let mut ciphertext = b64::decode(damaged["encryptedData"].as_str().unwrap()).unwrap();
    ciphertext[0] ^= 1;
    damaged["encryptedData"] = json!(b64::encode(&ciphertext));
    fs::write(&encrypted, serde_json::to_vec(&damaged).unwrap()).unwrap();
    let damaged = command().output().unwrap();
    failure(&damaged);
    assert!(damaged.stdout.is_empty());
    key_request.assert();
}

#[test]
fn password_and_destination_errors_are_resolved_before_account_access() {
    let home = TestHome::new();
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("exact");
    for value in [None, Some("")] {
        let mut command = home.command(&["auth", "export", "--output", path.to_str().unwrap()]);
        command.arg("--no-input");
        if let Some(value) = value {
            command.env("ENTE_CLI_PASSWORD", value);
        }
        let output = command.output().unwrap();
        assert!(failure(&output).contains("ENTE_CLI_PASSWORD"));
        assert!(output.stdout.is_empty());
        assert!(!path.exists());
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;
        let output = home
            .command(&["auth", "export", "--output", path.to_str().unwrap()])
            .env("ENTE_CLI_PASSWORD", std::ffi::OsString::from_vec(vec![255]))
            .output()
            .unwrap();
        assert!(failure(&output).contains("must be UTF-8"));
    }
    let missing = home.run(&["auth", "decrypt", path.to_str().unwrap()]);
    assert!(failure(&missing).contains(&format!("cannot read {}", path.display())));
    assert!(!failure(&missing).contains("ENTE_CLI_PASSWORD"));
    assert!(missing.stdout.is_empty());
    fs::write(&path, "existing").unwrap();
    let occupied = home.run(&["auth", "export", "--output", path.to_str().unwrap()]);
    assert!(failure(&occupied).contains("already exists"));
    assert_eq!(fs::read(&path).unwrap(), b"existing");
    for args in [
        vec!["auth", "export"],
        vec!["auth", "export", "dir", "--output", "-"],
    ] {
        failure(&home.run(&args));
    }
    assert!(!home.dir.path().join("accounts").exists());
}

#[test]
fn slow_stdout_releases_account_storage_before_publication() {
    use std::io::Read;

    let mut server = Server::new();
    let home = TestHome::new();
    seed(&home, &server.url());
    let key = Key::generate();
    let key_request = key_response(&mut server, &key);
    let uri = format!("{URI}&note={}", "x".repeat(1024 * 1024));
    let initial = page(&mut server, 0, vec![entity(1, 10, &json!(uri), &key)]);
    let mut child = home.command(EXPORT).spawn().unwrap();
    let mut stdout = child.stdout.take().unwrap();
    let mut first = [0];
    stdout.read_exact(&mut first).unwrap();
    success(home.run(&[
        "accounts",
        "logout",
        "--account",
        "fixture",
        "--local",
        "--offline",
    ]));
    let mut rest = Vec::new();
    stdout.read_to_end(&mut rest).unwrap();
    success(child.wait_with_output().unwrap());
    assert_eq!(first[0], b'o');
    assert_eq!(rest, format!("{}\n", &uri[1..]).as_bytes());
    initial.assert();
    key_request.assert();
}
