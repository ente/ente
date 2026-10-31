use std::sync::{Arc, Mutex};

use ente_core::{
    Session, b64,
    crypto::{Key, Nonce, SecretKey, secretbox},
    http::{ApiConfig, Auth},
};
use ente_photos::dedup::{Addition, RemovalCollection, RemovalFile, RemovalPlan, execute_removal};
use mockito::{Matcher, Server};

fn session(origin: String) -> Result<Session, ente_core::http::Error> {
    Session::new(
        ApiConfig {
            origin,
            client_package: Some("io.ente.photos".into()),
            client_version: None,
            user_agent: None,
            auth: Some(Auth::User("test-token".into())),
        },
        1,
        Key::generate(),
        Key::generate(),
        SecretKey::generate(),
    )
}

fn fixture() -> (RemovalPlan, Vec<RemovalCollection>, Vec<RemovalFile>) {
    (
        RemovalPlan {
            additions: vec![
                Addition {
                    collection_id: 11,
                    file_ids: vec![1],
                },
                Addition {
                    collection_id: 12,
                    file_ids: vec![1],
                },
            ],
            trash_ids: vec![2],
        },
        vec![
            RemovalCollection {
                id: 11,
                key: Key::generate(),
            },
            RemovalCollection {
                id: 12,
                key: Key::generate(),
            },
        ],
        vec![
            RemovalFile {
                id: 1,
                collection_id: 11,
                key: Key::generate(),
            },
            RemovalFile {
                id: 2,
                collection_id: 12,
                key: Key::generate(),
            },
        ],
    )
}

#[tokio::test]
async fn authenticates_encrypts_keys_and_finishes_all_additions_before_trash() {
    let mut server = Server::new_async().await;
    let (plan, collections, files) = fixture();
    let events = Arc::new(Mutex::new(Vec::new()));
    let mut mocks = Vec::new();
    for c in &collections {
        let key = Key::from_bytes(*c.key.as_bytes());
        let file_key = *files[0].key.as_bytes();
        let id = c.id;
        let events = events.clone();
        mocks.push(
            server
                .mock("POST", "/collections/add-files")
                .match_header("x-auth-token", "test-token")
                .match_header("x-client-package", "io.ente.photos")
                .match_body(Matcher::PartialJson(
                    serde_json::json!({"collectionID": id}),
                ))
                .match_request(move |request| {
                    let payload: serde_json::Value =
                        serde_json::from_slice(request.body().unwrap()).unwrap();
                    let f = &payload["files"][0];
                    let plaintext = secretbox::decrypt(
                        &b64::decode(f["encryptedKey"].as_str().unwrap()).unwrap(),
                        &Nonce::try_from_slice(
                            &b64::decode(f["keyDecryptionNonce"].as_str().unwrap()).unwrap(),
                        )
                        .unwrap(),
                        &key,
                    )
                    .unwrap();
                    events.lock().unwrap().push(id);
                    f["id"] == 1 && plaintext == file_key
                })
                .with_status(200)
                .create_async()
                .await,
        );
    }
    let trash_events = events.clone();
    let trash = server
        .mock("POST", "/files/trash")
        .match_header("x-auth-token", "test-token")
        .match_body(Matcher::Json(
            serde_json::json!({"items": [{"fileID": 2, "collectionID": 12}]}),
        ))
        .match_request(move |_| *trash_events.lock().unwrap() == vec![11, 12])
        .with_status(200)
        .create_async()
        .await;
    let mut progress = Vec::new();
    execute_removal(
        &session(server.url()).unwrap(),
        &plan,
        &collections,
        &files,
        |p| progress.push((p.completed, p.total)),
    )
    .await
    .unwrap();
    assert_eq!(progress, vec![(1, 3), (2, 3), (3, 3)]);
    for mock in mocks {
        mock.assert_async().await;
    }
    trash.assert_async().await;
}

#[tokio::test]
async fn does_not_trash_when_a_later_album_addition_fails() {
    let mut server = Server::new_async().await;
    let (plan, collections, files) = fixture();
    let first = server
        .mock("POST", "/collections/add-files")
        .match_body(Matcher::PartialJson(
            serde_json::json!({"collectionID": 11}),
        ))
        .with_status(200)
        .create_async()
        .await;
    let second = server
        .mock("POST", "/collections/add-files")
        .match_body(Matcher::PartialJson(
            serde_json::json!({"collectionID": 12}),
        ))
        .with_status(503)
        .create_async()
        .await;
    let trash = server
        .mock("POST", "/files/trash")
        .expect(0)
        .create_async()
        .await;
    let mut progress = Vec::new();
    assert!(
        execute_removal(
            &session(server.url()).unwrap(),
            &plan,
            &collections,
            &files,
            |p| { progress.push(p.completed) }
        )
        .await
        .is_err()
    );
    assert_eq!(progress, vec![1]);
    first.assert_async().await;
    second.assert_async().await;
    trash.assert_async().await;
}

#[tokio::test]
async fn validates_every_file_before_the_first_mutation() {
    let mut server = Server::new_async().await;
    let (mut plan, collections, files) = fixture();
    plan.trash_ids.push(999);
    let addition = server
        .mock("POST", "/collections/add-files")
        .expect(0)
        .create_async()
        .await;
    let mut progress = Vec::new();
    assert!(
        execute_removal(
            &session(server.url()).unwrap(),
            &plan,
            &collections,
            &files,
            |p| { progress.push(p) }
        )
        .await
        .is_err()
    );
    assert!(progress.is_empty());
    addition.assert_async().await;
}

#[tokio::test]
async fn batches_requests_and_propagates_trash_failure_without_completion() {
    let mut server = Server::new_async().await;
    let collections = vec![RemovalCollection {
        id: 11,
        key: Key::generate(),
    }];
    let files: Vec<_> = (1..=1002)
        .map(|id| RemovalFile {
            id,
            collection_id: 11,
            key: Key::generate(),
        })
        .collect();
    let plan = RemovalPlan {
        additions: vec![],
        trash_ids: (1..=1002).collect(),
    };
    let first = server
        .mock("POST", "/files/trash")
        .match_request(|r| {
            serde_json::from_slice::<serde_json::Value>(r.body().unwrap()).unwrap()["items"]
                .as_array()
                .unwrap()
                .len()
                == 1000
        })
        .with_status(200)
        .create_async()
        .await;
    let second = server
        .mock("POST", "/files/trash")
        .match_request(|r| {
            serde_json::from_slice::<serde_json::Value>(r.body().unwrap()).unwrap()["items"]
                .as_array()
                .unwrap()
                .len()
                == 2
        })
        .with_status(503)
        .create_async()
        .await;
    let mut progress = Vec::new();
    assert!(
        execute_removal(
            &session(server.url()).unwrap(),
            &plan,
            &collections,
            &files,
            |p| { progress.push(p) }
        )
        .await
        .is_err()
    );
    assert!(progress.is_empty());
    first.assert_async().await;
    second.assert_async().await;
}

#[tokio::test]
async fn batches_large_album_additions_before_trashing() {
    let mut server = Server::new_async().await;
    let collections = vec![RemovalCollection {
        id: 11,
        key: Key::generate(),
    }];
    let files: Vec<_> = (1..=1002)
        .map(|id| RemovalFile {
            id,
            collection_id: 11,
            key: Key::generate(),
        })
        .collect();
    let plan = RemovalPlan {
        additions: vec![Addition {
            collection_id: 11,
            file_ids: (1..=1001).collect(),
        }],
        trash_ids: vec![1002],
    };
    let batches = Arc::new(Mutex::new(Vec::new()));
    let mut mocks = Vec::new();
    for size in [1000, 1] {
        let seen = batches.clone();
        mocks.push(
            server
                .mock("POST", "/collections/add-files")
                .match_request(move |r| {
                    let value: serde_json::Value =
                        serde_json::from_slice(r.body().unwrap()).unwrap();
                    if value["files"].as_array().unwrap().len() != size {
                        return false;
                    }
                    seen.lock().unwrap().push(size);
                    true
                })
                .with_status(200)
                .create_async()
                .await,
        );
    }
    let seen = batches.clone();
    let trash = server
        .mock("POST", "/files/trash")
        .match_request(move |_| *seen.lock().unwrap() == vec![1000, 1])
        .with_status(200)
        .create_async()
        .await;
    let mut progress = Vec::new();
    execute_removal(
        &session(server.url()).unwrap(),
        &plan,
        &collections,
        &files,
        |p| progress.push((p.completed, p.total)),
    )
    .await
    .unwrap();
    assert_eq!(progress, vec![(1, 2), (2, 2)]);
    for mock in mocks {
        mock.assert_async().await;
    }
    trash.assert_async().await;
}

#[tokio::test]
async fn plans_and_executes_retention_rules_without_a_client_supplied_plan() {
    use ente_photos::dedup::{Duplicate, remove_duplicates};

    let cases = [
        (
            "caption before edits",
            Some("caption"),
            Some("renamed"),
            None,
            None,
            2,
        ),
        ("renamed copy", None, None, Some("renamed"), None, 3),
        ("edited date", None, None, None, Some(123), 3),
        ("caption tie", Some("caption"), None, None, None, 1),
        ("edit tie", None, Some("renamed"), None, Some(123), 1),
        (
            "empty name overrides date",
            None,
            None,
            Some(""),
            Some(123),
            1,
        ),
        ("fallback", None, None, None, None, 1),
    ];
    for (name, caption, first_name, last_name, last_time, retained) in cases {
        let mut server = Server::new_async().await;
        let mut groups = vec![vec![
            Duplicate {
                file_id: 1,
                collection_ids: vec![11],
                edited_name: first_name.map(String::from),
                ..Default::default()
            },
            Duplicate {
                file_id: 2,
                collection_ids: vec![12],
                caption: caption.map(String::from),
                ..Default::default()
            },
            Duplicate {
                file_id: 3,
                collection_ids: vec![13],
                edited_name: last_name.map(String::from),
                edited_time: last_time,
                ..Default::default()
            },
        ]];
        if name == "caption tie" {
            groups[0][0].caption = Some("first".into());
        }
        let collections: Vec<_> = (11..=13)
            .map(|id| RemovalCollection {
                id,
                key: Key::generate(),
            })
            .collect();
        let files: Vec<_> = (1..=3)
            .map(|id| RemovalFile {
                id,
                collection_id: id + 10,
                key: Key::generate(),
            })
            .collect();
        let mut additions = Vec::new();
        for collection in &collections {
            if collection.id == retained + 10 {
                continue;
            }
            let key = Key::from_bytes(*collection.key.as_bytes());
            let expected_key = *files[(retained - 1) as usize].key.as_bytes();
            additions.push(
                server
                    .mock("POST", "/collections/add-files")
                    .match_body(Matcher::PartialJson(
                        serde_json::json!({"collectionID": collection.id}),
                    ))
                    .match_request(move |request| {
                        let body: serde_json::Value =
                            serde_json::from_slice(request.body().unwrap()).unwrap();
                        let f = &body["files"][0];
                        f["id"] == retained
                            && secretbox::decrypt(
                                &b64::decode(f["encryptedKey"].as_str().unwrap()).unwrap(),
                                &Nonce::try_from_slice(
                                    &b64::decode(f["keyDecryptionNonce"].as_str().unwrap())
                                        .unwrap(),
                                )
                                .unwrap(),
                                &key,
                            )
                            .unwrap()
                                == expected_key
                    })
                    .with_status(200)
                    .create_async()
                    .await,
            );
        }
        let expected: Vec<_> = (1..=3).filter(|id| *id != retained).collect();
        let items: Vec<_> = expected
            .iter()
            .map(|id| serde_json::json!({"fileID": id, "collectionID": id + 10}))
            .collect();
        let trash = server
            .mock("POST", "/files/trash")
            .match_body(Matcher::Json(serde_json::json!({"items": items})))
            .with_status(200)
            .create_async()
            .await;
        let mut progress = Vec::new();
        let result = remove_duplicates(
            &session(server.url()).unwrap(),
            &groups,
            &collections,
            &files,
            |p| progress.push((p.completed, p.total)),
        )
        .await
        .unwrap();
        assert_eq!(result, expected, "{name}");
        assert_eq!(progress, vec![(1, 3), (2, 3), (3, 3)], "{name}");
        for addition in additions {
            addition.assert_async().await;
        }
        trash.assert_async().await;
    }
}

#[tokio::test]
async fn combined_removal_batches_groups_and_skips_empty_input() {
    use ente_photos::dedup::{Duplicate, remove_duplicates};

    let mut server = Server::new_async().await;
    let collections = vec![RemovalCollection {
        id: 11,
        key: Key::generate(),
    }];
    let files: Vec<_> = (1..=4)
        .map(|id| RemovalFile {
            id,
            collection_id: if id % 2 == 0 { 11 } else { 12 },
            key: Key::generate(),
        })
        .collect();
    let groups = vec![
        vec![
            Duplicate {
                file_id: 1,
                collection_ids: vec![12],
                ..Default::default()
            },
            Duplicate {
                file_id: 2,
                collection_ids: vec![11],
                ..Default::default()
            },
        ],
        vec![
            Duplicate {
                file_id: 3,
                collection_ids: vec![12],
                ..Default::default()
            },
            Duplicate {
                file_id: 4,
                collection_ids: vec![11],
                ..Default::default()
            },
        ],
    ];
    let addition = server
        .mock("POST", "/collections/add-files")
        .match_request(|r| {
            let body: serde_json::Value = serde_json::from_slice(r.body().unwrap()).unwrap();
            body["collectionID"] == 11
                && body["files"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|f| f["id"].as_i64().unwrap())
                    .collect::<Vec<_>>()
                    == vec![1, 3]
        })
        .with_status(200)
        .create_async()
        .await;
    let trash = server.mock("POST", "/files/trash").match_body(Matcher::Json(serde_json::json!({"items": [{"fileID":2,"collectionID":11},{"fileID":4,"collectionID":11}]}))).with_status(200).create_async().await;
    let session = session(server.url()).unwrap();
    let mut progress = Vec::new();
    assert_eq!(
        remove_duplicates(&session, &groups, &collections, &files, |p| progress
            .push((p.completed, p.total)))
        .await
        .unwrap(),
        vec![2, 4]
    );
    assert_eq!(progress, vec![(1, 2), (2, 2)]);
    addition.assert_async().await;
    trash.assert_async().await;
    progress.clear();
    assert!(
        remove_duplicates(&session, &[], &[], &[], |p| progress
            .push((p.completed, p.total)))
        .await
        .unwrap()
        .is_empty()
    );
    assert!(progress.is_empty());
    addition.assert_async().await;
    trash.assert_async().await;
}
