use serde::{Deserialize, Serialize};
use std::{fmt, str::FromStr};
use zeroize::ZeroizeOnDrop;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub user_id: i64,
    pub email: String,
    pub app: App,
    pub endpoint: String,
    pub export_dir: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum App {
    Photos,
    Locker,
    Auth,
}

impl App {
    pub fn client_package(&self) -> &'static str {
        match self {
            App::Photos => "io.ente.photos",
            App::Locker => "io.ente.locker",
            App::Auth => "io.ente.auth",
        }
    }
}

impl fmt::Display for App {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let value = match self {
            App::Photos => "photos",
            App::Locker => "locker",
            App::Auth => "auth",
        };
        write!(f, "{value}")
    }
}

impl FromStr for App {
    type Err = String;

    fn from_str(value: &str) -> std::result::Result<Self, Self::Err> {
        match value.trim().to_ascii_lowercase().as_str() {
            "photos" => Ok(App::Photos),
            "locker" => Ok(App::Locker),
            "auth" => Ok(App::Auth),
            other => Err(format!(
                "Invalid app: {other}. Must be one of: photos, locker, auth"
            )),
        }
    }
}

impl Account {
    pub fn account_key(&self) -> String {
        format!("{}:{}", self.email, self.app.client_package())
    }
}

#[derive(Serialize, Deserialize, ZeroizeOnDrop)]
pub struct AccountSecrets {
    pub token: Vec<u8>,
    pub master_key: Vec<u8>,
    pub secret_key: Vec<u8>,
    pub public_key: Vec<u8>,
}

impl fmt::Debug for AccountSecrets {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AccountSecrets")
            .field("token", &"[REDACTED]")
            .field("master_key", &"[REDACTED]")
            .field("secret_key", &"[REDACTED]")
            .field("public_key_len", &self.public_key.len())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_account_secrets_debug_redacts_secret_material() {
        let secrets = AccountSecrets {
            token: vec![1, 2, 3],
            master_key: vec![4, 5, 6],
            secret_key: vec![7, 8, 9],
            public_key: vec![10, 11, 12],
        };

        let debug = format!("{secrets:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("[1, 2, 3]"));
        assert!(!debug.contains("[4, 5, 6]"));
        assert!(!debug.contains("[7, 8, 9]"));
        assert!(debug.contains("public_key_len"));
    }
}
