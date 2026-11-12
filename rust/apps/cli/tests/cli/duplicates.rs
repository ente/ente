use super::{files::*, *};

fn fixture(id: i64, key: &Key, hash: &str, public: Value) -> Value {
    let (mut file, _) = remote_file_with(
        id,
        key,
        b"duplicate original",
        &json!({"title": format!("photo-{id}.jpg"), "fileType": 0, "creationTime": 1_700_000_000_000_000i64, "hash": hash}),
        &public,
    );
    file["info"] = json!({"fileSize": 100});
    file
}

#[test]
fn duplicates_list_and_preview_use_owned_visible_memberships_and_shared_retention_rules() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    let mut hidden = collection(3, "Hidden", &key);
    let metadata = blob::encrypt_json(&json!({"visibility": 2}), &key).unwrap();
    hidden["magicMetadata"] = json!({"data": b64::encode(&metadata.encrypted_data), "header": b64::encode(metadata.decryption_header.as_bytes())});
    let mut favorites = collection(4, "Favorites", &key);
    favorites["type"] = json!("favorites");
    server.mock("GET", "/collections/v2").match_query(mockito::Matcher::Any)
        .with_body(json!({"collections": [collection(1, "Zeta", &key), collection(2, "Alpha", &key), hidden, favorites]}).to_string())
        .expect_at_least(1).create();
    let first = fixture(10, &key, "one", json!({"editedName": "renamed.jpg"}));
    let caption = fixture(11, &key, "one", json!({"caption": 0}));
    let mut foreign = fixture(50, &key, "one", json!({}));
    foreign["ownerID"] = json!(123);
    let mut unknown = fixture(40, &key, "unknown", json!({}));
    unknown.as_object_mut().unwrap().remove("info");
    let mut unknown_copy = unknown.clone();
    unknown_copy["id"] = json!(41);
    let mut live = remote_file_with(30, &key, b"live photo", &json!({"title":"live.heic", "fileType":2, "creationTime":1, "imageHash":"image", "videoHash":"video"}), &json!({})).0;
    live["info"] = json!({"fileSize": 200});
    let mut live_copy = live.clone();
    live_copy["id"] = json!(31);
    page(
        &mut server,
        1,
        0,
        json!([
            first,
            fixture(20, &key, "two", json!({})),
            fixture(21, &key, "two", json!({"editedTime":123})),
            foreign,
            unknown,
            unknown_copy,
            live,
            live_copy,
            fixture(60, &key, "mixed", json!({})),
            fixture(61, &key, "mixed", json!({}))
        ]),
        false,
    )
    .create();
    page(&mut server, 2, 0, json!([caption]), false).create();
    page(&mut server, 4, 0, json!([first]), false).create();
    let hidden_request = page(
        &mut server,
        3,
        0,
        json!([fixture(60, &key, "mixed", json!({}))]),
        false,
    )
    .create();
    let add = server
        .mock("POST", "/collections/add-files")
        .expect(0)
        .create();
    let trash = server.mock("POST", "/files/trash").expect(0).create();
    let groups = home.json(&["photos", "duplicate", "list", "--all"]);
    assert_eq!(groups.as_array().unwrap().len(), 3);
    assert_eq!(
        home.json(&["photos", "duplicates", "list", "--all", "--offline"]),
        groups
    );
    assert_eq!(groups[0]["id"], "30");
    let one = groups
        .as_array()
        .unwrap()
        .iter()
        .find(|g| g["id"] == "10")
        .unwrap();
    assert_eq!(one["retainedId"], "11");
    assert_eq!(one["reclaimableBytes"], 100);
    assert_eq!(one["files"].as_array().unwrap().len(), 2);
    assert_eq!(
        one["files"][1]["albums"],
        json!([{"id":"4", "name":"Favorites"}, {"id":"1", "name":"Zeta"}])
    );
    assert_eq!(
        home.json(&["photos", "duplicate", "list", "--offline", "--all"]),
        groups
    );
    let limited = success(home.run(&["photos", "duplicate", "list", "--offline", "--limit", "1"]));
    let table = String::from_utf8_lossy(&limited.stdout);
    assert!(table.lines().any(|line| {
        line.split_whitespace().collect::<Vec<_>>() == ["ACTION", "ID", "NAME", "ALBUMS"]
    }));
    assert!(
        table
            .lines()
            .any(|line| { line.split_whitespace().take(2).collect::<Vec<_>>() == ["keep", "30"] })
    );
    assert!(String::from_utf8_lossy(&limited.stderr).contains("Showing first 1"));
    let preview = home.json(&[
        "photos",
        "duplicate",
        "remove",
        "10",
        "10",
        "--dry-run",
        "--no-input",
    ]);
    assert_eq!(
        preview,
        json!({"dryRun":true, "groupIds":["10"], "retainedIds":["11"], "trashIds":["10"], "reclaimableBytes":100})
    );
    let all = home.json(&["photos", "duplicate", "remove", "--all", "--dry-run"]);
    assert_eq!(all["trashIds"].as_array().unwrap().len(), 3);
    assert!(
        all["retainedIds"]
            .as_array()
            .unwrap()
            .contains(&json!("21"))
    );
    assert!(
        failure(&home.run(&["photos", "duplicate", "remove", "10", "99", "--yes"]))
            .contains("no duplicate group matches 99")
    );
    hidden_request.assert();
    add.assert();
    trash.assert();
    add.remove();
    let denied = server
        .mock("POST", "/collections/add-files")
        .with_status(403)
        .create();
    let result = home.run(&["photos", "duplicate", "remove", "10", "--yes", "--json"]);
    assert!(failure(&result).contains("duplicate removal did not finish"));
    assert!(result.stdout.is_empty());
    denied.assert();
    trash.assert();
}

#[test]
fn duplicates_refuse_incomplete_metadata_before_removal() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let key = Key::generate();
    server
        .mock("GET", "/collections/v2")
        .match_query(mockito::Matcher::Any)
        .with_body(json!({"collections":[collection(1, "Album", &key)]}).to_string())
        .create();
    let mut broken = fixture(12, &key, "one", json!({}));
    broken["metadata"]["encryptedData"] = json!("broken");
    page(
        &mut server,
        1,
        0,
        json!([
            fixture(10, &key, "one", json!({})),
            fixture(11, &key, "one", json!({})),
            broken
        ]),
        false,
    )
    .create();
    let trash = server.mock("POST", "/files/trash").expect(0).create();
    assert!(
        failure(&home.run(&["photos", "duplicate", "remove", "--all", "--yes"]))
            .contains("file 12 is unavailable")
    );
    trash.assert();
}

#[test]
fn duplicates_require_explicit_selection_and_confirmation_without_a_terminal() {
    let home = TestHome::new();
    for (args, expected) in [
        (
            vec!["--all", "--yes", "--offline"],
            "requires network access",
        ),
        (vec!["--yes", "--no-input"], "supply group IDs or --all"),
        (vec!["10", "--no-input"], "supply --yes"),
        (vec!["10", "--all", "--yes"], "cannot be used with"),
    ] {
        let mut command = vec!["photos", "duplicate", "remove"];
        command.extend(args);
        assert!(failure(&home.run(&command)).contains(expected));
    }
    assert_eq!(fs::read_dir(home.dir.path()).unwrap().count(), 0);
    let help = success(home.run(&["help", "photos", "duplicate", "remove"]));
    assert!(String::from_utf8_lossy(&help.stdout).contains("--dry-run"));
}
