mod support;

use support::{Cli, Museum, TestResult};
use url::Url;
use uuid::Uuid;

const PASTE_PASSWORD_ENV: &str = "ENTE_PASTE_PASSWORD";
const PASTE_ORIGIN: &str = "http://127.0.0.1";

#[test]
fn paste() -> TestResult {
    Museum::run(|museum| {
        full_link_roundtrip(museum)?;
        token_and_key_roundtrip(museum)?;
        stdin_roundtrip(museum)?;
        password_protected_roundtrip(museum)?;
        wrong_password_consumes_password_protected_paste(museum)?;
        consumed_password_paste_checks_availability_before_password(museum)
    })
}

fn full_link_roundtrip(museum: &Museum) -> TestResult {
    let cli = support::cli_session(museum, "full-link")?;
    let text = unique_text("full-link");
    let link = create_paste(&cli, museum, &text)?;

    let consumed = cli.run_ok(&[
        "paste",
        "consume",
        "--endpoint",
        museum.endpoint(),
        &link.raw,
    ])?;
    assert_eq!(consumed, text);

    let second_consume = cli.run(&[
        "paste",
        "consume",
        "--endpoint",
        museum.endpoint(),
        &link.raw,
    ])?;
    assert!(
        !second_consume.status.success(),
        "second consume unexpectedly succeeded with stdout: {}",
        String::from_utf8_lossy(&second_consume.stdout),
    );
    assert!(
        String::from_utf8_lossy(&second_consume.stderr).contains("HTTP 410"),
        "second consume should fail with 410, got stderr: {}",
        String::from_utf8_lossy(&second_consume.stderr),
    );

    Ok(())
}

fn token_and_key_roundtrip(museum: &Museum) -> TestResult {
    let cli = support::cli_session(museum, "token-key")?;
    let text = unique_text("token-key");
    let link = create_paste(&cli, museum, &text)?;

    let consumed = cli.run_ok(&[
        "paste",
        "consume",
        "--endpoint",
        museum.endpoint(),
        "--key",
        &link.key,
        &link.token,
    ])?;
    assert_eq!(consumed, text);

    Ok(())
}

fn stdin_roundtrip(museum: &Museum) -> TestResult {
    let cli = support::cli_session(museum, "stdin")?;
    let text = format!(
        "paste stdin scenario {}\n\nsecond line stays intact\n",
        Uuid::new_v4()
    );
    let link = cli.run_ok_with_stdin(
        &[
            "paste",
            "create",
            "--endpoint",
            museum.endpoint(),
            "--paste-origin",
            PASTE_ORIGIN,
        ],
        &text,
    )?;
    let link = PasteLink::parse(link.trim(), PASTE_ORIGIN);

    let consumed = cli.run_ok(&[
        "paste",
        "consume",
        "--endpoint",
        museum.endpoint(),
        &link.raw,
    ])?;
    assert_eq!(consumed, text);

    Ok(())
}

fn password_protected_roundtrip(museum: &Museum) -> TestResult {
    let cli = support::cli_session(museum, "password-protected")?;
    let text = unique_text("password-protected");
    let password = format!("password {}", Uuid::new_v4());
    let link = create_password_paste(&cli, museum, &text, &password)?;
    let env = [(PASTE_PASSWORD_ENV, password.as_str())];
    assert!(link.password_required);

    let consumed = cli.run_ok_with_env(
        &[
            "paste",
            "consume",
            "--endpoint",
            museum.endpoint(),
            &link.raw,
        ],
        &env,
    )?;
    assert_eq!(consumed, text);

    Ok(())
}

fn wrong_password_consumes_password_protected_paste(museum: &Museum) -> TestResult {
    let cli = support::cli_session(museum, "wrong-password")?;
    let text = unique_text("wrong-password");
    let password = format!("password {}", Uuid::new_v4());
    let link = create_password_paste(&cli, museum, &text, &password)?;

    let wrong_env = [(PASTE_PASSWORD_ENV, "wrong password")];
    let wrong = cli.run_with_env(
        &[
            "paste",
            "consume",
            "--endpoint",
            museum.endpoint(),
            &link.raw,
        ],
        &wrong_env,
    )?;
    assert!(
        !wrong.status.success(),
        "wrong password unexpectedly succeeded"
    );
    assert!(
        String::from_utf8_lossy(&wrong.stderr).contains("Incorrect paste password"),
        "wrong password should fail locally, got stderr: {}",
        String::from_utf8_lossy(&wrong.stderr),
    );

    let correct_env = [(PASTE_PASSWORD_ENV, password.as_str())];
    let second = cli.run_with_env(
        &[
            "paste",
            "consume",
            "--endpoint",
            museum.endpoint(),
            &link.raw,
        ],
        &correct_env,
    )?;
    assert!(
        !second.status.success(),
        "second consume unexpectedly succeeded with stdout: {}",
        String::from_utf8_lossy(&second.stdout),
    );
    assert!(
        String::from_utf8_lossy(&second.stderr).contains("HTTP 410"),
        "second consume should fail with 410, got stderr: {}",
        String::from_utf8_lossy(&second.stderr),
    );

    Ok(())
}

fn consumed_password_paste_checks_availability_before_password(museum: &Museum) -> TestResult {
    let cli = support::cli_session(museum, "consumed-password")?;
    let text = unique_text("consumed-password");
    let password = format!("password {}", Uuid::new_v4());
    let link = create_password_paste(&cli, museum, &text, &password)?;
    let env = [(PASTE_PASSWORD_ENV, password.as_str())];

    let consumed = cli.run_ok_with_env(
        &[
            "paste",
            "consume",
            "--endpoint",
            museum.endpoint(),
            &link.raw,
        ],
        &env,
    )?;
    assert_eq!(consumed, text);

    let invalid_env = [(PASTE_PASSWORD_ENV, "")];
    let second = cli.run_with_env(
        &[
            "paste",
            "consume",
            "--endpoint",
            museum.endpoint(),
            &link.raw,
        ],
        &invalid_env,
    )?;
    assert!(
        !second.status.success(),
        "second consume unexpectedly succeeded"
    );
    assert!(
        String::from_utf8_lossy(&second.stderr).contains("HTTP 410"),
        "consumed paste should fail before password validation, got stderr: {}",
        String::from_utf8_lossy(&second.stderr),
    );
    assert!(
        !String::from_utf8_lossy(&second.stderr).contains("Paste password cannot be empty"),
        "consumed paste validated password before guard: {}",
        String::from_utf8_lossy(&second.stderr),
    );

    Ok(())
}

fn create_paste(cli: &Cli, museum: &Museum, text: &str) -> TestResult<PasteLink> {
    let link = cli.run_ok(&[
        "paste",
        "create",
        "--endpoint",
        museum.endpoint(),
        "--paste-origin",
        PASTE_ORIGIN,
        text,
    ])?;
    Ok(PasteLink::parse(link.trim(), PASTE_ORIGIN))
}

fn create_password_paste(
    cli: &Cli,
    museum: &Museum,
    text: &str,
    password: &str,
) -> TestResult<PasteLink> {
    let env = [(PASTE_PASSWORD_ENV, password)];
    let link = cli.run_ok_with_env(
        &[
            "paste",
            "create",
            "--endpoint",
            museum.endpoint(),
            "--paste-origin",
            PASTE_ORIGIN,
            "--password",
            text,
        ],
        &env,
    )?;
    Ok(PasteLink::parse(link.trim(), PASTE_ORIGIN))
}

fn unique_text(scope: &str) -> String {
    format!("paste cli {scope} scenario {}", Uuid::new_v4())
}

struct PasteLink {
    raw: String,
    token: String,
    key: String,
    password_required: bool,
}

impl PasteLink {
    fn parse(raw: &str, expected_origin: &str) -> Self {
        let url = Url::parse(raw).unwrap_or_else(|error| {
            panic!("invalid paste link {raw}: {error}");
        });
        let actual_origin = url.origin().ascii_serialization();
        let expected_origin = Url::parse(expected_origin)
            .expect("expected paste origin should be a URL")
            .origin()
            .ascii_serialization();
        let token = url
            .path_segments()
            .and_then(|mut segments| segments.rfind(|segment| !segment.is_empty()))
            .expect("paste link should include an access token")
            .to_string();
        let key = url
            .fragment()
            .expect("paste link should include a decryption key fragment")
            .to_string();
        let (password_required, fragment_secret) = match key.strip_prefix("p-") {
            Some(fragment_secret) => (true, fragment_secret),
            None => (false, key.as_str()),
        };

        assert_eq!(
            actual_origin, expected_origin,
            "paste link used unexpected origin: {raw}",
        );
        assert!(
            fragment_secret.len() == 12
                && fragment_secret
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric()),
            "paste link key has unexpected format: {key}",
        );
        assert!(!token.is_empty(), "paste link token is empty: {raw}");

        Self {
            raw: raw.to_string(),
            token,
            key,
            password_required,
        }
    }
}
