use serde::Deserialize;
use serde_json::{Value, json};

use crate::{AccountsClient, Result};

#[derive(Deserialize)]
pub struct User {
    #[serde(rename = "ID")]
    pub id: i64,
    pub email: String,
    #[serde(rename = "creationTime")]
    pub created_at: i64,
}

#[derive(Deserialize)]
pub struct UserDetails {
    pub user: User,
    pub subscription: Option<Subscription>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Subscription {
    #[serde(rename = "productID")]
    pub product_id: String,
    pub storage: i64,
    pub expiry_time: i64,
    #[serde(rename = "originalTransactionID")]
    transaction_id: String,
    payment_provider: String,
    attributes: Value,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Deletion {
    #[serde(rename = "userID")]
    pub user_id: i64,
    pub is_subscription_cancelled: bool,
}

impl AccountsClient {
    pub async fn admin_user(&self, user: &str) -> Result<UserDetails> {
        let key = if user.parse::<i64>().is_ok() {
            "id"
        } else {
            "email"
        };
        Ok(self
            .api
            .get("/admin/user")
            .query(&[(key, user)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

    pub async fn admin_users(&self, since: i64) -> Result<Vec<User>> {
        #[derive(Deserialize)]
        struct Response {
            users: Vec<User>,
        }
        let response: Response = self
            .api
            .get("/admin/users")
            .query(&[("sinceTime", since)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?;
        Ok(response.users)
    }

    pub async fn admin_delete_user(&self, email: &str) -> Result<Deletion> {
        Ok(self
            .api
            .delete("/admin/user/delete")
            .query(&[("email", email)])
            .send()
            .await?
            .error_for_code()
            .await?
            .json()
            .await?)
    }

    pub async fn admin_disable_totp(&self, user_id: i64) -> Result<()> {
        self.api
            .post("/admin/user/disable-2fa")
            .json(&json!({"userID": user_id}))
            .send()
            .await?
            .error_for_code()
            .await?;
        Ok(())
    }

    pub async fn admin_remove_passkeys(&self, user_id: i64) -> Result<()> {
        self.api
            .post("/admin/user/disable-passkeys")
            .json(&json!({"userID": user_id}))
            .send()
            .await?
            .error_for_code()
            .await?;
        Ok(())
    }

    pub async fn admin_update_subscription(
        &self,
        user_id: i64,
        subscription: &Subscription,
    ) -> Result<()> {
        self.api
            .put("/admin/user/subscription")
            .json(&json!({
                "userID": user_id,
                "storage": subscription.storage,
                "expiryTime": subscription.expiry_time,
                "productID": subscription.product_id,
                "transactionID": subscription.transaction_id,
                "paymentProvider": subscription.payment_provider,
                "attributes": subscription.attributes,
            }))
            .send()
            .await?
            .error_for_code()
            .await?;
        Ok(())
    }

    pub async fn admin_test_email(&self, to: &str, from: &str, from_name: &str) -> Result<()> {
        self.api
            .post("/admin/mail")
            .json(&json!({
                "to": [to], "fromEmail": from, "fromName": from_name,
                "subject": "Test mail from Ente", "body": "This is a test mail from Ente",
            }))
            .send()
            .await?
            .error_for_code()
            .await?;
        Ok(())
    }
}
