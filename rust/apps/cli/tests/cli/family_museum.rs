use ente_test_support::{Museum, TestResult};
use uuid::Uuid;

use super::{
    museum::{create_account, login},
    *,
};

const GB: i64 = 1 << 30;

#[test]
fn family_plan_across_accounts() -> TestResult {
    Museum::run(|museum| {
        tokio::runtime::Runtime::new()?.block_on(async {
            let origin = museum.endpoint();
            let [admin_email, member_email, invitee_email] =
                ["family-admin", "family-member", "family-invitee"]
                    .map(|prefix| format!("{prefix}-{}@example.org", Uuid::new_v4()));
            let admin = create_account(origin, &admin_email).await;
            create_account(origin, &member_email).await;
            create_account(origin, &invitee_email).await;
            let admin_home = TestHome::new();
            let member_home = TestHome::new();
            login(
                &admin_home,
                "photos",
                &admin_email,
                &["--host", origin, "--no-input"],
            );
            login(
                &member_home,
                "photos",
                &member_email,
                &["--host", origin, "--no-input"],
            );
            let view = ["account", "family", "view"];
            assert_eq!(admin_home.json(&view), Value::Null);
            museum.execute_sql(&format!(
                "UPDATE subscriptions SET product_id = 'family', storage = {} WHERE user_id = {}",
                200 * GB,
                admin.user_id
            ))?;

            let created = admin_home.json(&["account", "family", "create"]);
            assert_eq!(created["storageBytes"], 200 * GB);
            assert_eq!(created["members"][0]["email"], admin_email);
            assert_eq!(created["members"][0]["status"], "SELF");
            let error = failure(&admin_home.run(&["account", "family", "leave", "--yes"]));
            assert!(error.contains("the family admin cannot leave"), "{error}");

            admin_home.json(&["account", "family", "member", "add", &invitee_email]);
            let invited = admin_home.json(&["account", "family", "member", "add", &member_email]);
            let id = find(&invited, &member_email)["id"]
                .as_str()
                .unwrap()
                .to_owned();
            assert_eq!(find(&invited, &member_email)["status"], "INVITED");
            let error = failure(&admin_home.run(&[
                "account",
                "family",
                "member",
                "set-storage",
                &member_email,
                "1GB",
            ]));
            assert!(error.contains("members who have joined"), "{error}");
            let remove_invitee = ["account", "family", "member", "remove", &invitee_email];
            let error =
                failure(&admin_home.run(&[remove_invitee.as_slice(), &["--no-input"]].concat()));
            assert!(error.contains("supply --yes"), "{error}");
            let revoked = admin_home.json(&[remove_invitee.as_slice(), &["--yes"]].concat());
            assert_eq!(revoked["members"].as_array().unwrap().len(), 2);

            accept(museum, origin, &id).await?;
            let joined = member_home.json(&view);
            assert_eq!(find(&joined, &member_email)["status"], "ACCEPTED");
            let plain = String::from_utf8(success(member_home.run(&view)).stdout)?;
            assert!(plain.contains("Storage  200 GB\n"), "{plain}");
            assert!(
                plain.contains(&format!("{member_email}  member ")),
                "{plain}"
            );
            let error =
                failure(&member_home.run(&["account", "family", "member", "add", &invitee_email]));
            assert!(
                error.contains("only the family admin can invite"),
                "{error}"
            );

            let set_storage = ["account", "family", "member", "set-storage", &id];
            let limited = admin_home.json(&[set_storage.as_slice(), &["1.5GB"]].concat());
            assert_eq!(
                find(&limited, &member_email)["storageLimitBytes"],
                3 * GB / 2
            );
            let error = failure(&admin_home.run(&[set_storage.as_slice(), &["1TB"]].concat()));
            assert!(
                error.contains("exceeds the family storage of 200 GB"),
                "{error}"
            );
            let unlimited = admin_home.json(&[set_storage.as_slice(), &["--no-limit"]].concat());
            assert_eq!(
                find(&unlimited, &member_email)["storageLimitBytes"],
                Value::Null
            );
            assert_eq!(member_home.json(&view), unlimited);

            let error = failure(&member_home.run(&["account", "family", "leave", "--no-input"]));
            assert!(error.contains("supply --yes"), "{error}");
            assert_eq!(
                member_home.json(&["account", "family", "leave", "--yes"]),
                json!({"left": true})
            );
            assert_eq!(member_home.json(&view), Value::Null);
            let error = failure(&member_home.run(&["account", "family", "leave", "--yes"]));
            assert!(error.contains("not in a family"), "{error}");

            admin_home.json(&["account", "family", "member", "add", &member_email]);
            accept(museum, origin, &id).await?;
            let error = failure(&admin_home.run(&[
                "account",
                "family",
                "member",
                "remove",
                &admin_email,
                "--yes",
            ]));
            assert!(
                error.contains("the family admin cannot be removed"),
                "{error}"
            );
            let removed = admin_home.json(&["account", "family", "member", "remove", &id, "--yes"]);
            assert_eq!(removed["members"].as_array().unwrap().len(), 1);
            assert_eq!(member_home.json(&view), Value::Null);
            let error =
                failure(&admin_home.run(&["account", "family", "member", "remove", &id, "--yes"]));
            assert!(error.contains("no family member matches"), "{error}");
            Ok(())
        })
    })
}

fn find<'a>(family: &'a Value, email: &str) -> &'a Value {
    family["members"]
        .as_array()
        .unwrap()
        .iter()
        .find(|member| member["email"] == email)
        .unwrap()
}

// Museum only emails the invite token, so plant a known one and accept it as the invite link would.
async fn accept(museum: &Museum, origin: &str, id: &str) -> TestResult {
    let token = Uuid::new_v4().simple().to_string();
    museum.execute_sql(&format!(
        "UPDATE families SET token = '{token}' WHERE id = '{id}'"
    ))?;
    reqwest::Client::new()
        .post(format!("{origin}/family/accept-invite"))
        .json(&json!({"token": token}))
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}
