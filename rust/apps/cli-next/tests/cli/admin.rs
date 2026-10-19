use chrono::Datelike;
use mockito::{Matcher, Server};

use super::*;

const USER_ID: i64 = 9007199254740993;
const EMAIL: &str = "alice+admin@example.org";

fn details() -> Value {
    json!({"user": {"ID": USER_ID, "email": EMAIL, "creationTime": 1},
        "subscription": {"productID": "free", "storage": 1024, "expiryTime": 1893456000000000i64,
            "originalTransactionID": "existing", "paymentProvider": "", "attributes": {"isCancelled": true}}})
}

fn lookup(server: &mut Server, response: Value) -> mockito::Mock {
    server
        .mock("GET", "/admin/user")
        .match_query(Matcher::UrlEncoded("email".into(), EMAIL.into()))
        .with_body(response.to_string())
        .expect(1)
        .create()
}

#[test]
fn admin_list_and_app_selection() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let mut users = vec![details()["user"].clone(); 101];
    users[0]["email"] = json!("alice\n@example.org");
    let list = server
        .mock("GET", "/admin/users")
        .match_query(Matcher::UrlEncoded("sinceTime".into(), "0".into()))
        .match_header("x-client-package", "io.ente.photos")
        .match_header("x-auth-token", b64::encode_url_safe(&[0xfb, 0xef]).as_str())
        .with_body(json!({"users": users}).to_string())
        .expect(3)
        .create();
    let output = success(home.run(&["admin", "user", "list", "--json"]));
    let rows: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(rows.as_array().unwrap().len(), 100);
    assert_eq!(rows[0]["id"], USER_ID.to_string());
    assert_eq!(rows[0]["createdAt"], "1970-01-01T00:00:00.000001Z");
    assert!(String::from_utf8(output.stderr).unwrap().contains("--all"));
    let human = success(home.run(&["admin", "user", "list", "--limit", "1"]));
    assert!(
        String::from_utf8(human.stdout)
            .unwrap()
            .contains("alice\\n@example.org")
    );
    assert_eq!(
        home.json(&["admin", "user", "list", "--all"])
            .as_array()
            .unwrap()
            .len(),
        101
    );
    list.assert();
    let since = server
        .mock("GET", "/admin/users")
        .match_query(Matcher::UrlEncoded(
            "sinceTime".into(),
            "1893456000000000".into(),
        ))
        .with_body(r#"{"users":[]}"#)
        .create();
    assert_eq!(
        home.json(&["admin", "user", "list", "--since", "2030-01-01"]),
        json!([])
    );
    since.assert();
    for (apps, explicit, expected) in [
        (vec!["auth"], None, "auth"),
        (vec!["locker"], None, "locker"),
        (vec!["auth", "photos"], None, "photos"),
        (vec!["auth", "locker"], Some("auth"), "auth"),
    ] {
        let mut state = home.read_vault();
        state["accounts"][0]["sessions"] = apps
            .into_iter()
            .map(|app| (app.to_owned(), json!({"token": [251, 239]})))
            .collect();
        home.write_vault(&state);
        let request = server
            .mock("GET", "/admin/user")
            .match_query(Matcher::UrlEncoded("email".into(), EMAIL.into()))
            .match_header("x-client-package", format!("io.ente.{expected}").as_str())
            .with_body(details().to_string())
            .create();
        let mut args = vec!["admin", "--account", "fixture", "user", "view", EMAIL];
        if let Some(app) = explicit {
            args.extend(["--app", app]);
        }
        assert_eq!(home.json(&args)["id"], USER_ID.to_string());
        request.assert();
    }
    assert!(
        failure(&home.run(&["admin", "user", "view", EMAIL])).contains("select one with --app")
    );
    assert!(
        failure(&home.run(&["admin", "--account", "missing", "user", "list"]))
            .contains("no account named")
    );
}

#[test]
fn admin_deletion_uses_email_and_reports_deleted_id() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let delete = server
        .mock("DELETE", "/admin/user/delete")
        .match_query(Matcher::UrlEncoded("email".into(), EMAIL.into()))
        .with_body(json!({"userID": USER_ID, "isSubscriptionCancelled": false}).to_string())
        .expect(1)
        .create();
    let mut args = vec!["admin", "user", "delete", EMAIL, "--no-input"];
    assert!(failure(&home.run(&args)).contains("supply --yes"));
    args.push("--yes");
    assert_eq!(
        home.json(&args),
        json!({"user": {"id": USER_ID.to_string(), "email": EMAIL},
            "cleanupScheduled": true, "subscriptionCancelled": false})
    );
    delete.assert();
}

#[test]
fn admin_security_mutations_require_confirmation_and_use_resolved_target() {
    for (command, path) in [
        ("disable-totp", "/admin/user/disable-2fa"),
        ("remove-passkeys", "/admin/user/disable-passkeys"),
    ] {
        let mut server = Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let id = USER_ID.to_string();
        let get = server
            .mock("GET", "/admin/user")
            .match_query(Matcher::UrlEncoded("id".into(), id.clone()))
            .with_body(details().to_string())
            .expect(1)
            .create();
        let change = server
            .mock("POST", path)
            .match_body(Matcher::Json(json!({"userID": USER_ID})))
            .with_body("{}")
            .expect(1)
            .create();
        let mut args = vec!["admin", "user", command, &id, "--no-input"];
        assert!(failure(&home.run(&args)).contains("supply --yes"));
        args.push("--yes");
        let result = home.json(&args);
        assert_eq!(result["user"]["email"], EMAIL);
        get.assert();
        change.assert();
    }
}

#[test]
fn admin_subscription_uses_one_snapshot_and_preserves_other_fields() {
    for flags in [
        vec!["--storage", "1.5gb"],
        vec!["--expires", "2031-01-01"],
        vec!["--no-limit"],
    ] {
        let mut server = Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let get = lookup(&mut server, details());
        let storage = if flags[0] == "--storage" {
            1610612736i64
        } else if flags[0] == "--no-limit" {
            100 * 1024_i64.pow(4)
        } else {
            1024
        };
        let expiry = (flags[0] != "--no-limit").then_some(if flags[0] == "--expires" {
            1924992000000000i64
        } else {
            1893456000000000i64
        });
        let preset_year = chrono::Utc::now().year() + 100;
        let change = server.mock("PUT", "/admin/user/subscription")
            .match_body(Matcher::PartialJson(json!({"userID": USER_ID, "storage": storage,
                "productID": "free", "transactionID": "existing", "paymentProvider": "", "attributes": {"isCancelled": true}})))
            .match_request(move |request| {
                let body: Value = serde_json::from_str(&request.utf8_lossy_body().unwrap()).unwrap();
                let actual = body["expiryTime"].as_i64().unwrap();
                expiry.map_or_else(|| chrono::DateTime::from_timestamp_micros(actual).unwrap().year() == preset_year, |value| actual == value)
            }).with_body("{}").expect(1).create();
        let mut args = vec![
            "admin",
            "user",
            "update-subscription",
            EMAIL,
            "--yes",
            "--no-input",
        ];
        args.extend(flags);
        let result = home.json(&args);
        assert_eq!(result["subscription"]["storageBytes"], storage);
        if let Some(expiry) = expiry {
            assert_eq!(
                result["subscription"]["expiresAt"],
                chrono::DateTime::from_timestamp_micros(expiry)
                    .unwrap()
                    .to_rfc3339_opts(chrono::SecondsFormat::Micros, true)
            );
        }
        get.assert();
        change.assert();
    }
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let put = server
        .mock("PUT", "/admin/user/subscription")
        .expect(0)
        .create();
    let mut paid = details()["subscription"].clone();
    paid["productID"] = json!("paid");
    for (subscription, expected) in [
        (paid, "not on a free plan"),
        (Value::Null, "did not return a subscription"),
    ] {
        let mut user = details();
        user["subscription"] = subscription;
        let get = lookup(&mut server, user);
        let error = failure(&home.run(&[
            "admin",
            "user",
            "update-subscription",
            EMAIL,
            "--no-limit",
            "--yes",
        ]));
        assert!(error.contains(expected));
        get.assert();
        get.remove();
    }
    put.assert();
}

#[test]
fn admin_failures_do_not_all_recommend_login() {
    for (status, body, stale) in [
        (
            400,
            json!({"code": "BAD_REQUEST", "message": "Token is too old"}),
            true,
        ),
        (401, json!({"error": "insufficient permissions"}), false),
        (404, json!({}), false),
        (
            400,
            json!({"code": "BAD_REQUEST", "message": "Other failure"}),
            false,
        ),
    ] {
        let mut server = Server::new();
        let home = TestHome::new();
        home.seed(&server.url());
        let request = server
            .mock("GET", "/admin/users")
            .match_query(Matcher::UrlEncoded("sinceTime".into(), "0".into()))
            .with_status(status)
            .with_body(body.to_string())
            .expect(1)
            .create();
        let output = home.run(&["admin", "user", "list", "--json", "--no-input"]);
        let error = failure(&output);
        assert_eq!(
            error.contains("account login --account \"fixture\" --app photos"),
            stale,
            "{error}"
        );
        assert!(error.contains(&format!("HTTP {status}")));
        assert!(output.stdout.is_empty());
        request.assert();
    }
}

#[test]
fn admin_email_and_input_contract() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let email = server
        .mock("POST", "/admin/mail")
        .match_body(Matcher::Json(
            json!({"to": [EMAIL], "fromEmail": "admin@example.org", "fromName": "Ente",
            "subject": "Test mail from Ente", "body": "This is a test mail from Ente"}),
        ))
        .with_body("{}")
        .create();
    assert_eq!(
        home.json(&[
            "admin",
            "email",
            "test",
            "--to",
            EMAIL,
            "--from",
            "admin@example.org",
            "--no-input"
        ]),
        json!({"to": EMAIL, "accepted": true})
    );
    email.assert();
    for (flags, expected) in [
        (
            vec!["--yes", "--no-input"],
            "supply --no-limit, --storage or --expires",
        ),
        (
            vec!["--no-limit", "--storage", "2GB"],
            "cannot be used with '--storage <SIZE>'",
        ),
        (
            vec!["--no-limit", "--expires", "2030-01-01"],
            "cannot be used with '--expires <WHEN>'",
        ),
        (vec!["--storage", "2GiB"], "use a size such as"),
        (vec!["--expires", "2030-01-01 12:00:00"], "use YYYY-MM-DD"),
    ] {
        let mut args = vec!["admin", "user", "update-subscription", EMAIL];
        args.extend(flags);
        let output = home.run(&args);
        let error = failure(&output);
        assert!(error.contains(expected), "{error}");
        assert!(output.stdout.is_empty());
    }
    assert!(
        failure(&home.run(&["admin", "user", "list", "--offline"])).contains("require network")
    );
}
