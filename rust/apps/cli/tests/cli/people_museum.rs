use flate2::{Compression, write::GzEncoder};
use reqwest::Method;

use super::*;

#[test]
fn people_list_and_filter_files_against_museum() -> TestResult {
    Museum::run_async(|origin| async move {
        let email = format!("people-{}@example.org", Uuid::new_v4());
        let owner = create_account(&origin, &email).await;
        let home = TestHome::new();
        login(&home, "photos", &email, &["--host", &origin]);
        let (trips, trips_key) = create_album(&origin, &owner, "Trips", "album").await;
        let (family, family_key) = create_album(&origin, &owner, "Family", "album").await;
        let (hidden, hidden_key) = create_album(&origin, &owner, "Hidden", "album").await;
        set_album_metadata(
            &origin,
            &owner,
            hidden,
            &hidden_key,
            "magic-metadata",
            json!({"visibility": 2}),
        )
        .await;
        let mut files = Vec::new();
        for (album, key, title) in [
            (trips, &trips_key, "Beach.jpg"),
            (trips, &trips_key, "Dinner.jpg"),
            (family, &family_key, "Garden.jpg"),
            (hidden, &hidden_key, "Secret.jpg"),
        ] {
            let metadata =
                json!({"title": title, "fileType": 0, "creationTime": 1_700_000_000_000_000i64});
            files.push(
                upload_fixture(&origin, &owner, album, key, title.as_bytes(), metadata)
                    .await
                    .0,
            );
        }
        let [beach, dinner, garden, secret] = files[..] else {
            unreachable!()
        };
        let listed = |output: &Output| {
            serde_json::from_slice::<Value>(&output.stdout)
                .unwrap()
                .as_array()
                .unwrap()
                .iter()
                .map(|file| file["id"].as_str().unwrap().parse::<i64>().unwrap())
                .collect::<Vec<_>>()
        };
        let ids = |args: &[&str]| {
            let mut command = vec!["photos", "file", "list", "--json"];
            command.extend(args);
            listed(&success(home.run(&command)))
        };
        let consent_off = "machine learning is off for this account";
        let not_synced = "no local people data; run the command online first";

        assert!(failure(&home.run(&["photos", "person", "list"])).contains(consent_off));
        assert!(
            failure(&home.run(&["--offline", "photos", "person", "list"])).contains(not_synced)
        );
        set_consent(&origin, &owner, true).await;
        assert_eq!(home.json(&["photos", "person", "list"]), json!([]));

        let key = Key::generate();
        let wrapped = secretbox::encrypt(
            key.as_bytes(),
            &Key::try_from_slice(&owner.secrets.master_key).unwrap(),
        );
        api(Method::POST, &origin, &owner, "/user-entity/key")
            .json(&json!({
                "type": "cgroup",
                "encryptedKey": b64::encode(&wrapped.encrypted_data),
                "header": b64::encode(wrapped.nonce.as_bytes()),
            }))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
        let person = |name: &str, faces: &[i64]| {
            json!({
                "name": name,
                "assigned": [{"id": format!("cluster-{name}"), "faces": faces.iter().map(|id| format!("{id}_0")).collect::<Vec<_>>()}],
            })
        };
        let mut ada_data = person("Ada", &[beach, dinner, garden]);
        ada_data["rejectedFaceIDs"] = json!([format!("{dinner}_0")]);
        ada_data["manuallyAssigned"] = json!([secret]);
        let ada = save_person(&origin, &owner, &key, None, &ada_data).await;
        let bob = save_person(&origin, &owner, &key, None, &person("Bob", &[dinner])).await;
        let ignored =
            save_person(&origin, &owner, &key, None, &person("(ignored)", &[garden])).await;
        let mut twins = vec![
            save_person(&origin, &owner, &key, None, &person("Twin", &[beach])).await,
            save_person(&origin, &owner, &key, None, &person("Twin", &[garden])).await,
        ];
        let ghost = save_person(&origin, &owner, &key, None, &person("Ghost", &[999])).await;

        let view = |id: &str, name: &str, hidden: bool, file_count: usize| json!({"id": id, "name": name, "hidden": hidden, "fileCount": file_count});
        let mut sorted_twins = twins.clone();
        sorted_twins.sort();
        let twin_files = |id: &str| if *id == twins[0] { beach } else { garden };
        assert_eq!(
            home.json(&["photos", "person", "list"]),
            json!([
                view(&ada, "Ada", false, 3),
                view(&ignored, "(ignored)", true, 1),
                view(&bob, "Bob", false, 1),
                view(&sorted_twins[0], "Twin", false, 1),
                view(&sorted_twins[1], "Twin", false, 1),
            ])
        );
        assert_eq!(
            home.json(&["photos", "people", "list", "--album", "Family"]),
            json!([
                view(&ignored, "(ignored)", true, 1),
                view(&ada, "Ada", false, 1),
                view(&twins[1], "Twin", false, 1),
            ])
        );
        let output = success(home.run(&["photos", "person", "list", "--limit", "2"]));
        let table = String::from_utf8(output.stdout).unwrap();
        let rows = table
            .lines()
            .map(|line| line.split_whitespace().collect::<Vec<_>>())
            .collect::<Vec<_>>();
        assert_eq!(
            rows,
            [
                vec!["ID", "NAME", "FILES", "HIDDEN"],
                vec![ada.as_str(), "Ada", "3", "no"],
                vec![ignored.as_str(), "(ignored)", "1", "yes"],
            ]
        );
        assert!(String::from_utf8_lossy(&output.stderr).contains("Showing first 2 results"));

        assert_eq!(ids(&["--person", "Ada"]), [beach, garden, secret]);
        assert_eq!(ids(&["--person", bob.as_str()]), [dinner]);
        assert_eq!(ids(&["--person", "(ignored)"]), [garden]);
        assert_eq!(ids(&["--person", "Ghost"]), Vec::<i64>::new());
        assert_eq!(ids(&["--album", "Trips", "--person", "Ada"]), [beach]);
        assert_eq!(
            ids(&["--person", twins[1].as_str()]),
            [twin_files(&twins[1])]
        );
        let error = failure(&home.run(&["photos", "file", "list", "--person", "Twin"]));
        assert!(error.contains("person \"Twin\" is ambiguous"), "{error}");
        assert!(error.contains("Use an ID."), "{error}");
        assert!(
            failure(&home.run(&["photos", "file", "list", "--person", "Nobody"]))
                .contains("no person matches \"Nobody\"")
        );

        let robert = person("Robert", &[dinner, beach]);
        save_person(&origin, &owner, &key, Some(&bob), &robert).await;
        for id in [&ghost, &twins[1]] {
            api(Method::DELETE, &origin, &owner, "/user-entity/entity")
                .query(&[("id", id)])
                .send()
                .await
                .unwrap()
                .error_for_status()
                .unwrap();
        }
        twins.truncate(1);
        let refreshed = json!([
            view(&ada, "Ada", false, 3),
            view(&bob, "Robert", false, 2),
            view(&ignored, "(ignored)", true, 1),
            view(&twins[0], "Twin", false, 1),
        ]);
        assert_eq!(home.json(&["photos", "person", "list"]), refreshed);
        assert_eq!(
            home.json(&["--offline", "photos", "person", "list"]),
            refreshed
        );
        let output = success(home.run(&[
            "--offline",
            "photos",
            "file",
            "list",
            "--person",
            "Twin",
            "--json",
        ]));
        assert!(output.stderr.is_empty());
        let offline: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(offline[0]["id"], json!(beach.to_string()));
        assert!(
            failure(&home.run(&["photos", "file", "list", "--person", "Ghost"]))
                .contains("no person matches \"Ghost\"")
        );

        let broken = save_person(&origin, &owner, &key, None, &json!({"name": 5})).await;
        let output = home.run(&["photos", "person", "list", "--json"]);
        let error = failure(&output);
        assert!(error.contains(&format!("person {broken}:")), "{error}");
        assert!(error.contains("person list is incomplete"), "{error}");
        assert_eq!(
            serde_json::from_slice::<Value>(&output.stdout).unwrap(),
            refreshed
        );

        set_consent(&origin, &owner, false).await;
        assert!(failure(&home.run(&["photos", "person", "list"])).contains(consent_off));
        assert!(
            failure(&home.run(&["--offline", "photos", "person", "list"])).contains(not_synced)
        );
        assert!(
            failure(&home.run(&["--offline", "photos", "file", "list", "--person", "Ada"]))
                .contains(not_synced)
        );
        assert!(
            failure(&home.run(&["photos", "file", "list", "--person", "Ada"]))
                .contains(consent_off)
        );
        assert_eq!(ids(&[]).len(), 4);

        set_consent(&origin, &owner, true).await;
        let output = home.run(&["photos", "person", "list", "--json"]);
        assert!(failure(&output).contains("person list is incomplete"));
        assert_eq!(
            serde_json::from_slice::<Value>(&output.stdout).unwrap(),
            refreshed
        );

        export::edit_file(
            &origin,
            &owner,
            dinner,
            &Key::generate(),
            1,
            json!({"editedTime": 1}),
        )
        .await;
        let output = success(home.run(&["photos", "file", "list", "--person", "Ada", "--json"]));
        assert!(
            output.stderr.is_empty(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(listed(&output), [beach, garden, secret]);
        let output = home.run(&["photos", "file", "list", "--person", "Robert", "--json"]);
        let error = failure(&output);
        assert!(error.contains(&format!("file {dinner}:")), "{error}");
        assert!(error.contains("file results are incomplete"), "{error}");
        assert_eq!(listed(&output), [beach]);
        Ok(())
    })
}

fn api(
    method: Method,
    origin: &str,
    owner: &AuthenticatedAccount,
    path: &str,
) -> reqwest::RequestBuilder {
    reqwest::Client::new()
        .request(method, format!("{origin}{path}"))
        .header("x-auth-token", b64::encode_url_safe(&owner.secrets.token))
        .header("x-client-package", "io.ente.photos")
}

async fn set_consent(origin: &str, owner: &AuthenticatedAccount, granted: bool) {
    api(Method::POST, origin, owner, "/remote-store/update")
        .json(&json!({"key": "faceSearchEnabled", "value": granted.to_string()}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
}

async fn save_person(
    origin: &str,
    owner: &AuthenticatedAccount,
    key: &Key,
    id: Option<&str>,
    data: &Value,
) -> String {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(data.to_string().as_bytes()).unwrap();
    let encrypted = blob::encrypt(&encoder.finish().unwrap(), key).unwrap();
    let mut body = json!({
        "type": "cgroup",
        "encryptedData": b64::encode(&encrypted.encrypted_data),
        "header": b64::encode(encrypted.decryption_header.as_bytes()),
    });
    let method = match id {
        Some(id) => {
            body["id"] = json!(id);
            Method::PUT
        }
        None => Method::POST,
    };
    let response = api(method, origin, owner, "/user-entity/entity")
        .json(&body)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    match id {
        Some(id) => id.to_owned(),
        None => response.json::<Value>().await.unwrap()["id"]
            .as_str()
            .unwrap()
            .to_owned(),
    }
}
