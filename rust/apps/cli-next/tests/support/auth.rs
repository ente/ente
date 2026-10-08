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
fn refresh_keeps_progress_and_refuses_unreadable_records_until_updated() {
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
        "--keep",
        "1",
        "--json",
    ]);
    let stderr = failure(&failed);
    assert!(stderr.contains("2 unreadable Auth records"));
    assert!(stderr.contains(&Uuid::from_u128(1).to_string()));
    assert!(!stderr.contains("private-secret"));
    assert!(!stderr.contains("JBSWY3DPEHPK3PXP"));
    assert_eq!(
        serde_json::from_slice::<Value>(&failed.stdout).unwrap(),
        json!({"output": null, "records": 0, "failed": 2, "pruned": 0})
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
    assert!(failure(&failed).contains("boundary did not advance"));
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
            .env("ENTE_CLI_EXPORT_PASSWORD", "")
            .output()
            .unwrap(),
    )
    .stdout;
    initial.assert();
    initial.remove();
    let directory = tempfile::tempdir().unwrap();
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
    assert_eq!(plain_summary["records"], 1);
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
        .env("ENTE_CLI_EXPORT_PASSWORD", password)
        .output()
        .unwrap(),
    );
    let summary: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(summary["records"], 1);
    assert_eq!(summary["pruned"], 0);
    assert_eq!(summary["failed"], 0);
    let encoded = fs::read(&encrypted).unwrap();
    let stream = success(
        home.command(&["auth", "export", "--offline", "--output", "-", "--json"])
            .env("ENTE_CLI_EXPORT_PASSWORD", password)
            .output()
            .unwrap(),
    );
    let stream: Value = serde_json::from_slice(&stream.stdout).unwrap();
    assert_eq!(stream["version"], 1);
    assert!(stream.get("records").is_none());
    assert!(stream["encryptedData"].is_string());
    let restore = TestHome::new();
    let absent_home = restore.dir.path().join("absent");
    let command = || {
        let mut command =
            restore.command(&["auth", "decrypt", encrypted.to_str().unwrap(), "--json"]);
        command
            .env_remove("ENTE_CLI_VAULT_KEY")
            .env("ENTE_CLI_HOME", &absent_home)
            .env("ENTE_CLI_EXPORT_PASSWORD", password);
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
        .env("ENTE_CLI_EXPORT_PASSWORD", "wrong")
        .output()
        .unwrap();
    failure(&wrong);
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
        if let Some(value) = value {
            command.env("ENTE_CLI_EXPORT_PASSWORD", value);
        }
        let output = command.output().unwrap();
        assert!(failure(&output).contains("ENTE_CLI_EXPORT_PASSWORD"));
        assert!(output.stdout.is_empty());
        assert!(!path.exists());
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;
        let output = home
            .command(&["auth", "export", "--output", path.to_str().unwrap()])
            .env(
                "ENTE_CLI_EXPORT_PASSWORD",
                std::ffi::OsString::from_vec(vec![255]),
            )
            .output()
            .unwrap();
        assert!(failure(&output).contains("must be UTF-8"));
    }
    fs::write(&path, "existing").unwrap();
    let occupied = home.run(&["auth", "export", "--output", path.to_str().unwrap()]);
    assert!(failure(&occupied).contains("already exists"));
    assert_eq!(fs::read(&path).unwrap(), b"existing");
    for args in [
        vec!["auth", "export"],
        vec!["auth", "export", "dir", "--output", "-"],
        vec!["auth", "export", "--output", "-", "--keep", "1"],
        vec!["auth", "export", "dir", "--keep", "0"],
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
    success(home.run(&["accounts", "logout", "fixture", "--local", "--offline"]));
    let mut rest = Vec::new();
    stdout.read_to_end(&mut rest).unwrap();
    success(child.wait_with_output().unwrap());
    assert_eq!(first[0], b'o');
    assert_eq!(rest, format!("{}\n", &uri[1..]).as_bytes());
    initial.assert();
    key_request.assert();
}
