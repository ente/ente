use super::*;

use mockito::{Matcher, Server};
use uuid::Uuid;

fn command(home: &TestHome, server: &Server, args: &[&str]) -> Command {
    let mut command = home.command(&["feedback", "--no-input"]);
    command
        .args(args)
        .args(["--host", &server.url()])
        .env("ENTE_CLI_HOME", home.dir.path().join("unused"))
        .env("ENTE_CLI_VAULT_KEY", "invalid");
    command
}

#[test]
fn submits_each_input_without_accounts_and_prints_the_receipt() {
    let home = TestHome::new();
    let mut server = Server::new();
    let file = home.dir.path().join("feedback.txt");
    let file_text = "File feedback\r\n\t🔐\n";
    fs::write(&file, file_text).unwrap();
    let unicode = "🔐".repeat(2_000);
    for (args, stdin, message, as_json) in [
        (
            vec!["literal feedback"],
            "ignored",
            "literal feedback",
            false,
        ),
        (
            vec!["--input", file.to_str().unwrap()],
            "ignored",
            file_text,
            true,
        ),
        (vec!["--input", "-"], " piped\n", " piped\n", true),
        (vec![], unicode.as_str(), unicode.as_str(), false),
    ] {
        let id = Uuid::new_v4();
        let submission = server
            .mock("POST", "/")
            .match_header("authorization", Matcher::Missing)
            .match_body(Matcher::PartialJson(json!({
                "message": message,
            })))
            .with_status(201)
            .with_body(json!({"id": id}).to_string())
            .expect(1)
            .create();
        let mut command = command(&home, &server, &args);
        if as_json {
            command.arg("--json");
        }
        let mut child = command.stdin(Stdio::piped()).spawn().unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(stdin.as_bytes())
            .unwrap();
        let output = success(child.wait_with_output().unwrap());
        assert!(output.stderr.is_empty());
        if as_json {
            assert_eq!(
                serde_json::from_slice::<Value>(&output.stdout).unwrap(),
                json!({"id": id})
            );
        } else {
            assert_eq!(
                String::from_utf8(output.stdout).unwrap(),
                format!("Feedback submitted. Receipt: {id}\n")
            );
        }
        submission.assert();
        submission.remove();
        assert!(!home.dir.path().join("unused").exists());
    }
}

#[test]
fn invalid_input_and_offline_mode_do_not_submit() {
    let home = TestHome::new();
    let mut server = Server::new();
    let requests = server.mock("POST", "/").expect(0).create();
    for (args, expected) in [
        (vec![" \n"], "blank"),
        (vec!["hello", "--input", "-"], "cannot be used"),
        (vec!["hello", "--offline"], "network access"),
    ] {
        let output = command(&home, &server, &args).output().unwrap();
        assert!(failure(&output).contains(expected));
        assert!(output.stdout.is_empty());
    }
    let file = home.dir.path().join("feedback.txt");
    for (input, expected) in [
        ("x".repeat(2_001).into_bytes(), "2,000 characters"),
        ("🔐".repeat(2_001).into_bytes(), "2,000 characters"),
        (vec![0xff], "UTF-8"),
        (b"clear\x1b[2Jscreen".to_vec(), "control characters"),
        (
            b"\x1b]8;;https://example.test\x07link".to_vec(),
            "control characters",
        ),
        (
            "C1\u{9b}2Jcontrol".as_bytes().to_vec(),
            "control characters",
        ),
        (b"nul\0byte".to_vec(), "control characters"),
    ] {
        fs::write(&file, input).unwrap();
        let output = command(&home, &server, &["--input", file.to_str().unwrap()])
            .output()
            .unwrap();
        assert!(failure(&output).contains(expected));
        assert!(output.stdout.is_empty());
    }
    requests.assert();
    assert!(!home.dir.path().join("unused").exists());
}

#[test]
fn failures_and_invalid_receipts_never_report_success_or_retry() {
    let home = TestHome::new();
    let mut server = Server::new();
    for (status, body, expected) in [
        (429, "{}", "wait a minute"),
        (502, "{}", "HTTP 502"),
        (201, "{}", "invalid receipt"),
        (201, r#"{"id":"not-a-uuid"}"#, "invalid receipt"),
        (302, "{}", "HTTP 302"),
    ] {
        let request = server
            .mock("POST", "/")
            .with_status(status)
            .with_header("location", &format!("{}/redirected", server.url()))
            .with_body(body)
            .expect(1)
            .create();
        let output = command(&home, &server, &["feedback", "--json"])
            .output()
            .unwrap();
        assert!(failure(&output).contains(expected));
        assert!(output.stdout.is_empty());
        request.assert();
        request.remove();
    }
}
