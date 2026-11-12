use anyhow::{Result, ensure};
use ente_core::b64;

use crate::{api, args::App, args::Options, output, vault::State};

pub async fn photos(selected: Option<&str>, options: &Options) -> Result<()> {
    ensure!(
        !options.offline,
        "usage is not stored locally; this command requires network access"
    );
    let state = State::load()?;
    let account = &state.accounts[state.resolve(selected)?];
    let client = api::accounts_client(&account.origin, App::Photos)?;
    client.set_auth_token(Some(b64::encode_url_safe(account.token(App::Photos)?)));
    output::usage(&client.account_details().await?, options.json)
}
