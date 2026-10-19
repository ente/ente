use super::*;
use std::sync::{Arc, Mutex};

use ente_paste::{PasteLink, PastePayload};
use mockito::{Matcher, Server};

fn command(home: &TestHome, server: &Server, args: &[&str]) -> Command {
    let mut command = home.command(args);
    command
        .args(["--host", server.url().trim_start_matches("http://")])
        .env("ENTE_CLI_HOME", home.dir.path().join("unused"))
        .env("ENTE_CLI_VAULT_KEY", "invalid");
    command
}

#[test]
fn create_and_consume_preserve_each_input_without_account_storage() {
    let home = TestHome::new();
    let mut server = Server::new();
    let file = home.dir.path().join("text.txt");
    fs::write(&file, "file\r\n\t🔐\n").unwrap();
    for (args, stdin, expected, protected, as_json) in [
        (
            vec!["literal text"],
            "ignored",
            "literal text",
            false,
            false,
        ),
        (
            vec!["--input", file.to_str().unwrap()],
            "ignored",
            "file\r\n\t🔐\n",
            false,
            true,
        ),
        (
            vec!["--input", "-"],
            " pipe\r\n\t\x1b]52;c;AAA\x07\n\n",
            " pipe\r\n\t\x1b]52;c;AAA\x07\n\n",
            false,
            false,
        ),
        (vec![], "hello\n", "hello\n", false, false),
        (
            vec!["protected", "--password"],
            "ignored",
            "protected",
            true,
            true,
        ),
    ] {
        let captured = Arc::new(Mutex::new(None));
        let body = captured.clone();
        let create = server
            .mock("POST", "/paste/create")
            .match_header(
                "user-agent",
                concat!("ente-cli-next/", env!("CARGO_PKG_VERSION")),
            )
            .with_body_from_request(move |request| {
                *body.lock().unwrap() =
                    Some(serde_json::from_slice::<PastePayload>(request.body().unwrap()).unwrap());
                br#"{"accessToken":"ABC123"}"#.to_vec()
            })
            .expect(1)
            .create();
        let mut create_command = command(&home, &server, &["paste", "create"]);
        create_command
            .args(args)
            .args(["--paste-origin", "https://paste.example.test/?ignored=1"])
            .arg("--no-input")
            .env(
                "ENTE_CLI_PASSWORD",
                if protected { "  password  " } else { "" },
            );
        if as_json {
            create_command.arg("--json");
        }
        let mut child = create_command.stdin(Stdio::piped()).spawn().unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(stdin.as_bytes())
            .unwrap();
        let output = success(child.wait_with_output().unwrap());
        assert!(output.stderr.is_empty());
        let url = if as_json {
            let value: Value = serde_json::from_slice(&output.stdout).unwrap();
            assert_eq!(value.as_object().unwrap().len(), 1);
            value["url"].as_str().unwrap().to_owned()
        } else {
            String::from_utf8(output.stdout)
                .unwrap()
                .strip_suffix('\n')
                .unwrap()
                .to_owned()
        };
        assert!(url.starts_with("https://paste.example.test/ABC123#"));
        let link = PasteLink::parse(&url, None).unwrap();
        assert_eq!(link.password_required(), protected);
        create.assert();
        create.remove();
        let payload = captured.lock().unwrap().take().unwrap();
        let guard = server
            .mock("POST", "/paste/guard")
            .with_header("set-cookie", "paste_guard=fixture")
            .expect(if protected { 2 } else { 1 })
            .create();
        let consume = server
            .mock("POST", "/paste/consume")
            .with_body(serde_json::to_string(&payload).unwrap())
            .expect(1)
            .create();
        let mut consume_command = command(&home, &server, &["paste", "consume"]);
        if as_json {
            consume_command
                .arg(&link.access_token)
                .args(["--key", &link.key.link_fragment()]);
        } else {
            consume_command.arg(&url);
        }
        consume_command.arg("--no-input").env(
            "ENTE_CLI_PASSWORD",
            if protected { "  password  " } else { "" },
        );
        if as_json {
            consume_command.args(["--json", "--raw"]);
        }
        let output = success(consume_command.output().unwrap());
        assert!(output.stderr.is_empty());
        if as_json {
            assert_eq!(
                serde_json::from_slice::<Value>(&output.stdout).unwrap(),
                json!({"text": expected})
            );
        } else {
            assert_eq!(output.stdout, expected.as_bytes());
        }
        guard.assert();
        consume.assert();
        guard.remove();
        consume.remove();
        assert!(!home.dir.path().join("unused").exists());
    }
}

#[test]
fn invalid_input_and_unattended_passwords_fail_before_requests() {
    let home = TestHome::new();
    let mut server = Server::new();
    let requests = server.mock("POST", Matcher::Any).expect(0).create();
    let protected = "https://paste.example.test/ABC123#p-AbCd1234EfGh";
    for (args, error) in [
        (vec!["paste", "create"], "empty"),
        (vec!["paste", "consume", "ABC123"], "key is missing"),
        (
            vec!["paste", "consume", protected, "--key", "AbCd1234EfGh"],
            "keys do not match",
        ),
        (
            vec!["paste", "create", "text", "--input", "-"],
            "cannot be used",
        ),
        (vec!["paste", "create", " \n"], "empty"),
        (
            vec!["paste", "create", "hello", "--offline"],
            "network access",
        ),
        (
            vec!["paste", "consume", protected, "--offline"],
            "network access",
        ),
        (
            vec!["paste", "create", "text", "--password", "--no-input"],
            "ENTE_CLI_PASSWORD",
        ),
        (
            vec!["paste", "consume", protected, "--no-input"],
            "ENTE_CLI_PASSWORD",
        ),
    ] {
        let output = command(&home, &server, &args).output().unwrap();
        assert!(failure(&output).contains(error));
        assert!(output.stdout.is_empty());
    }
    for password in [std::ffi::OsString::from("")].into_iter().chain({
        #[cfg(unix)]
        {
            use std::os::unix::ffi::OsStringExt;
            vec![std::ffi::OsString::from_vec(vec![255])]
        }
        #[cfg(not(unix))]
        {
            vec![]
        }
    }) {
        let output = command(&home, &server, &["paste", "consume", protected])
            .env("ENTE_CLI_PASSWORD", password)
            .output()
            .unwrap();
        assert!(failure(&output).contains("ENTE_CLI_PASSWORD"));
        assert!(output.stdout.is_empty());
    }
    let missing = home.dir.path().join("missing.txt");
    let output = command(
        &home,
        &server,
        &[
            "paste",
            "create",
            "--input",
            missing.to_str().unwrap(),
            "--password",
        ],
    )
    .output()
    .unwrap();
    assert!(failure(&output).contains(missing.to_str().unwrap()));
    fs::write(&missing, [255]).unwrap();
    let output = command(
        &home,
        &server,
        &["paste", "create", "--input", missing.to_str().unwrap()],
    )
    .output()
    .unwrap();
    assert!(failure(&output).contains("UTF-8"));
    requests.assert();
    assert!(!home.dir.path().join("unused").exists());
}

#[test]
fn consume_failures_report_whether_payload_was_retrieved() {
    let home = TestHome::new();
    let mut server = Server::new();
    for protected in [false, true] {
        let (key, payload) = ente_paste::encrypt("text", protected.then_some("correct")).unwrap();
        let link = PasteLink {
            access_token: "ABC123".into(),
            key,
        };
        let mut url = link.url("https://paste.example.test");
        if !protected {
            let last = url.pop().unwrap();
            url.push(if last == 'A' { 'B' } else { 'A' });
        }
        let unavailable = server
            .mock("POST", "/paste/guard")
            .with_status(410)
            .create();
        let output = command(&home, &server, &["paste", "consume", &url])
            .env("ENTE_CLI_PASSWORD", "correct")
            .output()
            .unwrap();
        assert!(failure(&output).contains("paste is unavailable"));
        assert!(!failure(&output).contains("paste has been consumed"));
        assert!(output.stdout.is_empty());
        unavailable.assert();
        unavailable.remove();
        let guard = server
            .mock("POST", "/paste/guard")
            .with_header("set-cookie", "paste_guard=fixture")
            .expect(if protected { 2 } else { 1 })
            .create();
        let consume = server
            .mock("POST", "/paste/consume")
            .with_body(serde_json::to_string(&payload).unwrap())
            .expect(1)
            .create();
        let output = command(&home, &server, &["paste", "consume", &url, "--json"])
            .env("ENTE_CLI_PASSWORD", "wrong")
            .output()
            .unwrap();
        assert!(failure(&output).contains(if protected {
            "incorrect paste password"
        } else {
            "Decryption failed"
        }));
        assert!(failure(&output).contains("paste has been consumed and cannot be read again"));
        assert!(output.stdout.is_empty());
        guard.assert();
        consume.assert();
        guard.remove();
        consume.remove();
    }
    assert!(!home.dir.path().join("unused").exists());
}
