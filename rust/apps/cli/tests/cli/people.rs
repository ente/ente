use ente_core::crypto::secretbox;
use flate2::{Compression, write::GzEncoder};
use mockito::{Matcher, Mock, Server};

use super::*;

fn page(server: &mut Server, since: i64, rows: &[Value], hits: usize) -> Mock {
    server
        .mock("GET", "/user-entity/entity/diff")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("sinceTime".into(), since.to_string()),
            Matcher::UrlEncoded("limit".into(), "500".into()),
            Matcher::UrlEncoded("type".into(), "cgroup".into()),
        ]))
        .with_body(json!({"diff": rows}).to_string())
        .expect(hits)
        .create()
}

fn albums(server: &mut Server, hits: usize) -> Mock {
    server
        .mock("GET", "/collections/v2")
        .match_query(Matcher::Any)
        .with_body(json!({"collections": []}).to_string())
        .expect(hits)
        .create()
}

fn consent(server: &mut Server, granted: bool, hits: usize) -> Mock {
    server
        .mock("GET", "/remote-store/feature-flags")
        .with_body(json!({"faceSearchEnabled": granted}).to_string())
        .expect(hits)
        .create()
}

fn people_key(server: &mut Server, key: &Key) -> Mock {
    let wrapped = secretbox::encrypt(key.as_bytes(), &Key::from_bytes([0; 32]));
    server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "cgroup".into()))
        .with_body(json!({"encryptedKey": b64::encode(&wrapped.encrypted_data), "header": b64::encode(wrapped.nonce.as_bytes())}).to_string())
        .expect(1)
        .create()
}

fn person(key: &Key, id: &str, updated_at: i64, data: &Value) -> Value {
    let mut compressed = GzEncoder::new(Vec::new(), Compression::default());
    compressed.write_all(data.to_string().as_bytes()).unwrap();
    let encrypted = blob::encrypt(&compressed.finish().unwrap(), key).unwrap();
    json!({"id": id, "isDeleted": false, "updatedAt": updated_at,
        "encryptedData": b64::encode(&encrypted.encrypted_data),
        "header": b64::encode(encrypted.decryption_header.as_bytes())})
}

#[test]
fn people_sync_follows_full_pages_and_resumes_from_the_saved_cursor() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let albums = albums(&mut server, 3);
    let consent = consent(&mut server, true, 3);
    let key = Key::generate();
    let key_request = people_key(&mut server, &key);
    let deleted = (1..=500)
        .map(|n| json!({"id": format!("gone-{n}"), "isDeleted": true, "updatedAt": n}))
        .collect::<Vec<_>>();
    let ada = person(&key, "ada", 600, &json!({"name": "Ada"}));
    let full = page(&mut server, 0, &deleted, 1);
    let rest = page(&mut server, 499, &[deleted[499].clone(), ada], 1);
    let caught_up = page(&mut server, 600, &[], 2);

    for selector in ["Ada", "ada"] {
        assert_eq!(
            home.json(&["photos", "file", "list", "--person", selector]),
            json!([])
        );
    }
    assert_eq!(home.json(&["photos", "person", "list"]), json!([]));
    assert_eq!(
        home.json(&["--offline", "photos", "file", "list", "--person", "Ada"]),
        json!([])
    );
    assert!(
        failure(&home.run(&["--offline", "photos", "file", "list", "--person", "gone-1"]))
            .contains("no person matches \"gone-1\"")
    );
    albums.assert();
    consent.assert();
    key_request.assert();
    full.assert();
    rest.assert();
    caught_up.assert();
}

#[test]
fn revoked_consent_purges_people_before_refreshing_albums() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let first_albums = albums(&mut server, 1);
    let granted = consent(&mut server, true, 1);
    let key = Key::generate();
    let key_request = people_key(&mut server, &key);
    let rows = [
        person(&key, "ada", 1, &json!({"name": "Ada"})),
        person(&key, "ada\nbis", 2, &json!({"name": "Ada"})),
        person(&key, "bad\u{1b}[31m", 3, &json!({"name": 5})),
    ];
    let diff = page(&mut server, 0, &rows, 1);

    let error = failure(&home.run(&["photos", "person", "list"]));
    assert!(error.contains("person bad\\u{1b}[31m:"), "{error}");
    assert!(!error.contains('\u{1b}'), "{error}");
    assert!(error.contains("person list is incomplete"), "{error}");
    let error = failure(&home.run(&["--offline", "photos", "file", "list", "--person", "Ada"]));
    assert!(error.contains("  ada\\nbis  \"Ada\""), "{error}");
    let error = failure(&home.run(&[
        "--offline",
        "photos",
        "file",
        "list",
        "--person",
        "bad\u{1b}[31m",
    ]));
    assert!(error.contains("person bad\\u{1b}[31m"), "{error}");
    assert!(!error.contains("bad\u{1b}"), "{error}");
    first_albums.assert();
    granted.assert();
    key_request.assert();
    diff.assert();

    first_albums.remove();
    granted.remove();
    let failing_albums = server
        .mock("GET", "/collections/v2")
        .match_query(Matcher::Any)
        .with_status(500)
        .expect(0)
        .create();
    let revoked = consent(&mut server, false, 2);
    for command in [
        &["photos", "person", "list"][..],
        &["photos", "file", "list", "--person", "ada"],
    ] {
        assert!(
            failure(&home.run(command)).contains("machine learning is off for this account"),
            "{command:?}"
        );
    }
    assert!(
        failure(&home.run(&["--offline", "photos", "person", "list"]))
            .contains("no local people data; run the command online first")
    );
    failing_albums.assert();
    revoked.assert();
    key_request.assert();
    diff.assert();
}
