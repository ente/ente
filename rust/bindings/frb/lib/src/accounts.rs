use flutter_rust_bridge::frb;

pub mod types;
pub use types::{AccountsClient, AccountsClientConfig, AccountsError};

#[frb(sync)]
pub fn create_accounts_client(
    config: AccountsClientConfig,
) -> Result<AccountsClient, AccountsError> {
    Ok(AccountsClient(ente_accounts::AccountsClient::new(
        ente_accounts::AccountsClientConfig {
            origin: config.origin,
            client_package: config.client_package,
            client_version: config.client_version,
            user_agent: config.user_agent,
            auth_token: None,
        },
    )?))
}
