use super::*;

const GB: i64 = 1 << 30;

#[test]
fn family_view_shows_storage_and_members() {
    let mut server = mockito::Server::new();
    let home = TestHome::new();
    home.seed(&server.url());
    let outside = server
        .mock("GET", "/family/members")
        .match_header("x-auth-token", b64::encode_url_safe(&[0xfb, 0xef]).as_str())
        .with_status(400)
        .with_body("{}")
        .expect(2)
        .create();
    assert_eq!(home.json(&["account", "family", "view"]), Value::Null);
    let plain = success(home.run(&["account", "family", "view"]));
    assert_eq!(String::from_utf8_lossy(&plain.stdout), "Not in a family.\n");
    outside.assert();
    outside.remove();

    let family = server
        .mock("GET", "/family/members")
        .with_body(
            json!({"storage": 200 * GB, "expiryTime": 4942020944746699i64, "adminBonus": 10 * GB, "members": [
                {"id": "00000000-0000-4000-8000-00000000000a", "email": "fixture@example.org", "status": "SELF",
                    "usage": 50 * GB, "isAdmin": true, "userID": 9007199254740993i64},
                {"id": "00000000-0000-4000-8000-00000000000b", "email": "bob@example.org", "status": "ACCEPTED",
                    "usage": 3 * GB, "isAdmin": false, "storageLimit": 5 * GB, "userID": 1},
                {"id": "00000000-0000-4000-8000-00000000000c", "email": "carol@example.org", "status": "INVITED",
                    "usage": 0, "isAdmin": false}
            ]})
            .to_string(),
        )
        .expect(2)
        .create();
    assert_eq!(
        home.json(&["account", "family", "view"]),
        json!({"storageBytes": 210 * GB, "usedBytes": 53 * GB, "expiresAt": "2126-08-10T07:35:44.746699Z",
        "members": [
            {"id": "00000000-0000-4000-8000-00000000000a", "email": "fixture@example.org", "status": "SELF",
                "admin": true, "usedBytes": 50 * GB, "storageLimitBytes": null},
            {"id": "00000000-0000-4000-8000-00000000000b", "email": "bob@example.org", "status": "ACCEPTED",
                "admin": false, "usedBytes": 3 * GB, "storageLimitBytes": 5 * GB},
            {"id": "00000000-0000-4000-8000-00000000000c", "email": "carol@example.org", "status": "INVITED",
                "admin": false, "usedBytes": 0, "storageLimitBytes": null}
        ]})
    );
    let plain = success(home.run(&["account", "family", "view"]));
    assert_eq!(
        String::from_utf8_lossy(&plain.stdout),
        "Storage  210 GB\nUsed     53 GB\nExpires  2126-08-10T07:35:44.746699Z\n\n\
         EMAIL                STATUS   USED     LIMIT  ID\n\
         fixture@example.org  admin    50 GB    none   00000000-0000-4000-8000-00000000000a\n\
         bob@example.org      member   3 GB     5 GB   00000000-0000-4000-8000-00000000000b\n\
         carol@example.org    invited  0 bytes  none   00000000-0000-4000-8000-00000000000c\n"
    );
    family.assert();
}
