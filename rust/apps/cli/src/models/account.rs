pub use ente_accounts::AccountSecrets;
use serde::{Deserialize, Serialize};
use std::{fmt, str::FromStr};

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
