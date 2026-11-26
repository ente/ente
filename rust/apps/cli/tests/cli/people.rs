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

fn failing_page(server: &mut Server, since: i64) -> Mock {
    server
        .mock("GET", "/user-entity/entity/diff")
        .match_query(Matcher::UrlEncoded("sinceTime".into(), since.to_string()))
        .with_status(400)
        .expect(1)
        .create()
}

fn tombstones(updated_at: std::ops::RangeInclusive<i64>) -> Vec<Value> {
    updated_at
        .map(|n| json!({"id": format!("gone-{n}"), "isDeleted": true, "updatedAt": n}))
        .collect()
}

#[test]
fn people_sync_restarts_an_unfinished_first_sync_and_then_resumes_from_its_cursor() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let albums = albums(&mut server, 4);
    let consent = consent(&mut server, true, 6);
    let key = Key::generate();
    let key_request = people_key(&mut server, &key);
    let deleted = tombstones(1..=500);
    let ada = person(&key, "ada", 600, &json!({"name": "Ada"}));
    let unnamed = person(&key, "unnamed", 600, &json!({"name": ""}));
    let not_synced = "no local people data; run the command online first";
    let full = page(&mut server, 0, &deleted, 2);
    let cut_off = failing_page(&mut server, 499);

    failure(&home.run(&["photos", "person", "list"]));
    assert!(failure(&home.run(&["--offline", "photos", "person", "list"])).contains(not_synced));
    cut_off.assert();
    cut_off.remove();
    let rest = page(&mut server, 499, &[deleted[499].clone(), ada, unnamed], 1);
    let caught_up = page(&mut server, 600, &[], 2);

    for selector in ["Ada", "ada"] {
        assert_eq!(
            home.json(&["photos", "file", "list", "--person", selector]),
            json!([])
        );
    }
    assert_eq!(home.json(&["photos", "person", "list"]), json!([]));
    for selector in ["Ada", ""] {
        assert_eq!(
            home.json(&["--offline", "photos", "file", "list", "--person", selector]),
            json!([])
        );
    }
    assert!(
        failure(&home.run(&["--offline", "photos", "file", "list", "--person", "gone-1"]))
            .contains("no person matches \"gone-1\"")
    );
    caught_up.assert();
    caught_up.remove();

    let later = page(&mut server, 600, &tombstones(601..=1100), 1);
    let later_cut_off = failing_page(&mut server, 1099);
    failure(&home.run(&["photos", "person", "list"]));
    assert_eq!(
        home.json(&["--offline", "photos", "person", "list"]),
        json!([])
    );
    later_cut_off.assert();
    later_cut_off.remove();
    let resumed = page(&mut server, 1099, &[], 1);
    assert_eq!(home.json(&["photos", "person", "list"]), json!([]));

    albums.assert();
    consent.assert();
    key_request.assert();
    full.assert();
    rest.assert();
    later.assert();
    resumed.assert();
}

#[test]
fn person_selection_prefers_ids_and_matches_names_of_unreadable_records() {
    let mut server = Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let albums = albums(&mut server, 1);
    let consent = consent(&mut server, true, 1);
    let key = Key::generate();
    let key_request = people_key(&mut server, &key);
    let rows = [
        person(&key, "ada", 1, &json!({"name": "Ada"})),
        person(
            &key,
            "ada-unreadable",
            2,
            &json!({"name": "Ada", "isHidden": "yes"}),
        ),
        person(&key, "named-like-an-id", 3, &json!({"name": "ada"})),
        person(&key, "nameless-unreadable", 4, &json!({"isHidden": "yes"})),
        person(&key, "numbered", 5, &json!({"name": 5})),
    ];
    let diff = page(&mut server, 0, &rows, 1);

    assert_eq!(
        home.json(&["photos", "file", "list", "--person", "ada"]),
        json!([])
    );
    let offline = |selector: &str| {
        failure(&home.run(&["--offline", "photos", "file", "list", "--person", selector]))
    };
    let error = offline("Ada");
    assert!(error.contains("person \"Ada\" is ambiguous"), "{error}");
    assert!(error.contains("  ada  \"Ada\""), "{error}");
    assert!(error.contains("  ada-unreadable  \"Ada\""), "{error}");
    for (selector, id) in [
        ("ada-unreadable", "ada-unreadable"),
        ("", "nameless-unreadable"),
    ] {
        let error = offline(selector);
        assert!(error.contains(&format!("person {id}:")), "{error}");
    }
    let error = offline("5");
    assert!(error.contains("no person matches \"5\""), "{error}");
    albums.assert();
    consent.assert();
    key_request.assert();
    diff.assert();
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
