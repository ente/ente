use super::*;

#[test]
fn duplicates_select_remove_and_refresh_against_museum() -> TestResult {
    Museum::run_async(|origin| async move {
        let email = format!("duplicates-{}@example.org", Uuid::new_v4());
        let owner = create_account(&origin, &email).await;
        let (alpha, alpha_key) = create_album(&origin, &owner, "Alpha", "album").await;
        let (zeta, zeta_key) = create_album(&origin, &owner, "Zeta", "album").await;
        let (favorites, favorites_key) =
            create_album(&origin, &owner, "Favorites", "favorites").await;
        let (hidden, hidden_key) = create_album(&origin, &owner, "Hidden", "album").await;
        set_album_metadata(
            &origin,
            &owner,
            hidden,
            &hidden_key,
            "magic-metadata",
            json!({"visibility":2}),
        )
        .await;
        let original = b"same original uploaded separately";
        let mut files = Vec::new();
        for (album, key, hash) in [
            (alpha, &alpha_key, "one"),
            (zeta, &zeta_key, "one"),
            (favorites, &favorites_key, "one"),
            (alpha, &alpha_key, "two"),
            (zeta, &zeta_key, "two"),
            (hidden, &hidden_key, "one"),
        ] {
            files.push(upload_fixture(&origin, &owner, album, key, original, json!({
                "title":format!("{hash}.jpg"), "fileType":0, "creationTime":1_700_000_000_000_000i64, "hash":hash
            })).await);
        }
        let caption = blob::encrypt_json(&json!({"caption": "retain this caption"}), &files[1].1)?;
        reqwest::Client::new().put(format!("{origin}/files/public-magic-metadata"))
            .header("x-auth-token", b64::encode_url_safe(&owner.secrets.token))
            .header("x-client-package", "io.ente.photos")
            .json(&json!({"metadataList":[{"id":files[1].0,"magicMetadata":{
                "version":1,"count":1,"data":b64::encode(&caption.encrypted_data),"header":b64::encode(caption.decryption_header.as_bytes())
            }}]})).send().await?.error_for_status()?;
        let home = TestHome::new();
        login(&home, "photos", &email, &["--host", &origin, "--no-input"]);
        let groups = home.json(&["photos", "duplicate", "list", "--all"]);
        assert_eq!(groups.as_array().unwrap().len(), 2);
        let selected = files[..3].iter().map(|f| f.0).min().unwrap().to_string();
        let retained = files[1].0.to_string();
        let group = groups
            .as_array()
            .unwrap()
            .iter()
            .find(|g| g["id"] == selected)
            .unwrap();
        assert_eq!(group["files"].as_array().unwrap().len(), 3);
        assert_eq!(group["retainedId"], retained);
        let preview = home.json(&[
            "photos",
            "duplicate",
            "remove",
            &selected,
            "--dry-run",
            "--no-input",
        ]);
        assert_eq!(preview["trashIds"].as_array().unwrap().len(), 2);
        assert_eq!(home.json(&["photos", "duplicate", "list", "--all"]), groups);
        let removed = home.json(&[
            "photos",
            "duplicate",
            "remove",
            &selected,
            "--yes",
            "--no-input",
        ]);
        assert_eq!(removed["dryRun"], false);
        assert_eq!(removed["trashIds"], preview["trashIds"]);
        assert_eq!(removed["retainedIds"], json!([retained]));
        let remaining = home.json(&["photos", "duplicate", "list", "--offline"]);
        assert_eq!(remaining.as_array().unwrap().len(), 1);
        assert_ne!(remaining[0]["id"], selected);
        for album in [alpha, zeta, favorites] {
            let album = album.to_string();
            let file = home.json(&["photos", "file", "view", &retained, "--album", &album]);
            assert_eq!(file["caption"], "retain this caption");
            let target = home.dir.path().join(format!("{album}.jpg"));
            success(home.run(&[
                "photos",
                "file",
                "download",
                &retained,
                "--album",
                &album,
                "--output",
                target.to_str().unwrap(),
            ]));
            assert_eq!(fs::read(target)?, original);
        }
        let hidden_files = home.json(&["photos", "file", "list", "--album", &hidden.to_string()]);
        assert_eq!(hidden_files[0]["id"], files[5].0.to_string());
        let trash = home.json(&["photos", "api", "/trash/v2/diff", "--query", "sinceTime=0"]);
        let mut trash_ids: Vec<_> = trash["diff"]
            .as_array()
            .unwrap()
            .iter()
            .map(|item| item["file"]["id"].as_i64().unwrap())
            .collect();
        trash_ids.sort();
        let mut expected = vec![files[0].0, files[2].0];
        expected.sort();
        assert_eq!(trash_ids, expected);
        let all = home.json(&["photos", "duplicate", "remove", "--all", "--yes"]);
        assert_eq!(all["trashIds"].as_array().unwrap().len(), 1);
        assert_eq!(
            home.json(&["photos", "duplicate", "list", "--offline"]),
            json!([])
        );
        let empty = home.json(&["photos", "duplicate", "remove", "--all", "--yes"]);
        assert_eq!(empty["trashIds"], json!([]));
        Ok(())
    })
}

#[test]
fn duplicates_protect_hidden_memberships_when_listing_and_removing() -> TestResult {
    Museum::run_async(|origin| async move {
        let email = format!("hidden-duplicates-{}@example.org", Uuid::new_v4());
        let owner = create_account(&origin, &email).await;
        let (visible, visible_key) = create_album(&origin, &owner, "Visible", "album").await;
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
        for _ in 0..3 {
            files.push(
                upload_fixture(
                    &origin,
                    &owner,
                    visible,
                    &visible_key,
                    b"duplicate",
                    json!({
                        "title":"photo.jpg", "fileType":0, "creationTime":1, "hash":"same"
                    }),
                )
                .await,
            );
        }
        let protected = files[0].0.to_string();
        let home = TestHome::new();
        login(&home, "photos", &email, &["--host", &origin, "--no-input"]);
        assert_eq!(
            home.json(&["photos", "duplicate", "list", "--all"])[0]["files"]
                .as_array()
                .unwrap()
                .len(),
            3
        );
        export::place(
            &origin,
            &owner,
            hidden,
            &hidden_key,
            files[0].0,
            &files[0].1,
            "add-files",
        )
        .await;
        let groups = home.json(&["photos", "duplicate", "list", "--all"]);
        assert_eq!(groups.as_array().unwrap().len(), 1);
        let candidates = groups[0]["files"].as_array().unwrap();
        assert_eq!(candidates.len(), 2);
        assert!(candidates.iter().all(|file| file["id"] != protected));
        assert_eq!(
            home.json(&["photos", "duplicate", "list", "--all", "--offline"]),
            groups
        );
        let preview = home.json(&["photos", "duplicate", "remove", "--all", "--dry-run"]);
        assert_eq!(preview["trashIds"].as_array().unwrap().len(), 1);
        assert!(
            !preview["trashIds"]
                .as_array()
                .unwrap()
                .contains(&json!(protected))
        );
        let removed = home.json(&["photos", "duplicate", "remove", "--all", "--yes"]);
        assert_eq!(removed["trashIds"], preview["trashIds"]);
        for album in [visible, hidden] {
            let file = home.json(&[
                "photos",
                "file",
                "view",
                &protected,
                "--album",
                &album.to_string(),
            ]);
            assert_eq!(file["id"], protected);
        }
        assert_eq!(
            home.json(&["photos", "duplicate", "list", "--all"]),
            json!([])
        );
        Ok(())
    })
}
