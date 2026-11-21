use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;

use crate::{
    AccountsClient, Result,
    admin::Subscription,
    family::{Family, Member},
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountDetails {
    pub email: String,
    pub usage: i64,
    pub file_count: Option<i64>,
    pub storage_bonus: i64,
    pub subscription: Subscription,
    pub family_data: Option<Family>,
}

impl AccountDetails {
    pub fn plan_active(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_micros() as i64);
        self.plan_active_at(now)
    }

    fn plan_active_at(&self, now_micros: i64) -> bool {
        self.plan_expiry_time() >= now_micros
    }

    pub fn plan_storage(&self) -> i64 {
        self.family()
            .map_or(self.subscription.storage, |family| family.storage)
    }

    pub fn plan_expiry_time(&self) -> i64 {
        self.family()
            .map_or(self.subscription.expiry_time, |family| family.expiry_time)
    }

    pub fn family(&self) -> Option<&Family> {
        self.family_data
            .as_ref()
            .filter(|family| !family.members.is_empty())
    }

    pub fn family_member(&self) -> Option<&Member> {
        self.family()?
            .members
            .iter()
            .find(|member| member.email.trim() == self.email.trim())
    }

    pub fn total_storage(&self) -> i64 {
        self.plan_storage() + self.storage_bonus
    }

    pub fn free_storage(&self) -> i64 {
        let free = self.total_storage() - self.family().map_or(self.usage, Family::usage);
        match self.family_member().and_then(|member| member.storage_limit) {
            Some(limit) => free.min(limit - self.usage),
            None => free,
        }
        .max(0)
    }
}

impl AccountsClient {
    pub async fn account_details(&self) -> Result<AccountDetails> {
        Ok(self
            .api
            .get("/users/details/v2")
            .query(&[("memoryCount", true)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }
}

#[cfg(test)]
mod tests {
    use mockito::Server;
    use serde_json::{Value, json};

    use super::*;
    use crate::test_support::make_client;

    const GB: i64 = 1 << 30;

    fn details(extra: Value) -> AccountDetails {
        let mut value = json!({
            "email": "alice@example.org", "usage": 3 * GB, "fileCount": 339,
            "sharedCollectionsCount": 0, "storageBonus": 10 * GB,
            "subscription": {"productID": "free", "storage": 10 * GB,
                "originalTransactionID": "none", "expiryTime": 4942020944746699i64,
                "paymentProvider": "", "attributes": {}},
        });
        value
            .as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        serde_json::from_value(value).unwrap()
    }

    #[test]
    fn personal_storage_adds_the_bonus_to_the_plan() {
        let details = details(json!({}));
        assert_eq!(details.total_storage(), 20 * GB);
        assert_eq!(details.free_storage(), 17 * GB);
        assert!(details.family().is_none());
        assert!(details.plan_active_at(4942020944746699));
        assert!(!details.plan_active_at(4942020944746700));
    }

    #[test]
    fn family_storage_uses_the_admin_plan_and_member_limits() {
        let family = json!({"familyData": {"storage": 200 * GB, "expiryTime": 4942020944746699i64, "adminBonus": 0,
        "members": [
            {"id": "00000000-0000-4000-8000-00000000000a", "email": "admin@example.org", "status": "SELF", "usage": 50 * GB, "isAdmin": true},
            {"id": "00000000-0000-4000-8000-00000000000b", "email": " alice@example.org ", "status": "ACCEPTED", "usage": 3 * GB, "isAdmin": false, "storageLimit": 5 * GB},
            {"id": "00000000-0000-4000-8000-00000000000c", "email": "new@example.org", "status": "INVITED", "usage": 0, "isAdmin": false}
        ]}});
        let mut details = details(family);
        details.subscription.expiry_time = 1;
        assert_eq!(details.plan_storage(), 200 * GB);
        assert!(details.plan_active_at(2));
        assert_eq!(details.total_storage(), 210 * GB);
        assert_eq!(details.family().unwrap().usage(), 53 * GB);
        assert_eq!(details.free_storage(), 2 * GB);
        assert!(!details.family_member().unwrap().is_admin);
        let details = details.family_data.unwrap();
        assert_eq!(details.members[2].storage_limit, None);
        assert_eq!(details.members[2].usage, 0);
    }

    #[test]
    fn an_empty_family_and_a_missing_file_count_are_not_errors() {
        let details = details(
            json!({"familyData": {"storage": 0, "expiryTime": 0, "adminBonus": 0, "members": []}, "fileCount": null,
            "subscription": {"productID": "50gb_monthly_v4", "storage": 50 * GB, "expiryTime": 1,
                "originalTransactionID": "t", "paymentProvider": "stripe",
                "attributes": {"isCancelled": true}}}),
        );
        assert!(details.family().is_none());
        assert_eq!(details.file_count, None);
        assert_eq!(details.free_storage(), 57 * GB);
    }

    #[test]
    fn free_storage_never_goes_negative() {
        let mut value = json!({"usage": 25 * GB});
        assert_eq!(details(value.clone()).free_storage(), 0);
        value["familyData"] = json!({"storage": 200 * GB, "expiryTime": 1, "adminBonus": 0, "members": [
            {"id": "00000000-0000-4000-8000-00000000000a", "email": "admin@example.org", "status": "SELF", "usage": 50 * GB, "isAdmin": true},
            {"id": "00000000-0000-4000-8000-00000000000b", "email": "other@example.org", "status": "ACCEPTED", "usage": 3 * GB, "isAdmin": false, "storageLimit": GB}
        ]});
        let family = details(value);
        // Not listed among the members: no member cap applies.
        assert!(family.family_member().is_none());
        assert_eq!(family.free_storage(), 157 * GB);
    }

    #[tokio::test]
    async fn account_details_are_fetched_with_the_token() {
        let mut server = Server::new_async().await;
        let details = server
            .mock("GET", "/users/details/v2")
            .match_query(mockito::Matcher::UrlEncoded(
                "memoryCount".into(),
                "true".into(),
            ))
            .match_header("x-auth-token", "token")
            .with_body(
                serde_json::to_string(
                    &json!({"email": "alice@example.org", "usage": 1, "storageBonus": 0,
                "subscription": {"productID": "free", "storage": GB, "expiryTime": 1,
                    "originalTransactionID": "none", "paymentProvider": "", "attributes": {}}}),
                )
                .unwrap(),
            )
            .expect(1)
            .create_async()
            .await;
        let client = make_client(server.url());
        client.set_auth_token(Some("token".into()));
        assert_eq!(client.account_details().await.unwrap().total_storage(), GB);
        details.assert_async().await;
    }
}
