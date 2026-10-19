use std::{collections::BTreeMap, io::Write, path::Path, time::Duration};

use anyhow::{Context, Result, ensure};
use ente_accounts::{AccountsClient, AccountsClientConfig};
use ente_core::{
    Session, b64,
    crypto::{Key, SecretKey},
    http::{ApiConfig, Auth},
};
use reqwest::{
    Client, Method,
    header::{HeaderMap, HeaderName, HeaderValue},
    redirect::Policy,
};
use url::Url;
use zeroize::Zeroizing;

use crate::{
    args::{ApiArgs, App, Options},
    parse_json, read_input,
    vault::{Account, State},
};

pub(crate) const USER_AGENT: &str = concat!("ente-cli-next/", env!("CARGO_PKG_VERSION"));

pub fn normalize_host(host: &str) -> Result<String> {
    let input = if host.contains("://") {
        host.to_owned()
    } else {
        format!("https://{host}")
    };
    let mut url = Url::parse(&input).context("invalid API host")?;
    if !host.contains("://")
        && url.host_str().is_some_and(|h| {
            h == "localhost"
                || h.trim_matches(['[', ']'])
                    .parse::<std::net::IpAddr>()
                    .is_ok_and(|ip| ip.is_loopback())
        })
    {
        ensure!(
            url.set_scheme("http").is_ok(),
            "host must be an HTTP or HTTPS origin"
        );
    }
    ensure!(
        matches!(url.scheme(), "http" | "https") && url.host_str().is_some(),
        "host must be an HTTP or HTTPS origin"
    );
    ensure!(
        url.username().is_empty() && url.password().is_none(),
        "host must not contain credentials"
    );
    Ok(url.origin().ascii_serialization())
}

pub fn http() -> Result<Client> {
    Ok(Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(15))
        .read_timeout(Duration::from_secs(30))
        .redirect(Policy::none())
        .build()?)
}

pub fn accounts_client(origin: &str, app: App) -> Result<AccountsClient> {
    Ok(AccountsClient::new(
        AccountsClientConfig::new(app.client_package())
            .with_origin(origin)
            .with_user_agent(USER_AGENT),
    )?)
}

pub async fn logout(account: &Account, app: App) -> Result<()> {
    let client = accounts_client(&account.origin, app)?;
    client.set_auth_token(Some(b64::encode_url_safe(account.token(app)?)));
    match client.logout().await {
        Ok(()) => Ok(()),
        Err(ente_accounts::Error::Http(error)) if error.status_code() == Some(401) => Ok(()),
        Err(error) => Err(error.into()),
    }
}

pub fn session(account: &Account, app: App) -> Result<Session> {
    let mut config = ApiConfig::new(account.origin.clone());
    config.client_package = Some(app.client_package().into());
    config.user_agent = Some(USER_AGENT.into());
    config.auth = Some(Auth::User(b64::encode_url_safe(account.token(app)?)));
    Session::new(
        config,
        account.user_id,
        Key::try_from_slice(&account.identity.master_key)?,
        Key::try_from_slice(&account.identity.recovery_key)?,
        SecretKey::try_from_slice(&account.identity.secret_key)?,
    )
    .map_err(Into::into)
}

pub async fn run(app: App, args: ApiArgs, selected: Option<&str>, options: &Options) -> Result<()> {
    ensure!(!options.offline, "this command requires network access");
    let state = State::load()?;
    let account = &state.accounts[state.resolve(selected)?];
    ensure!(
        !(args.headers.as_deref() == Some(Path::new("-"))
            && args.body.as_deref() == Some(Path::new("-"))),
        "headers and body cannot both read stdin"
    );
    let origin = Url::parse(&format!("{}/", account.origin))?;
    let mut url = origin.join(&args.path).context("invalid API path")?;
    ensure!(
        url.origin() == origin.origin(),
        "API URL must stay at the selected account's origin"
    );
    for query in args.query {
        let (name, value) = query
            .split_once('=')
            .context("--query requires name=value")?;
        url.query_pairs_mut().append_pair(name, value);
    }
    let mut headers = HeaderMap::new();
    if let Some(path) = args.headers {
        let values: BTreeMap<String, String> = parse_json(&read_input(&path, u64::MAX)?)
            .context("headers must be a JSON object of strings")?;
        for (name, value) in values {
            let mut value = HeaderValue::from_str(&Zeroizing::new(value))?;
            value.set_sensitive(true);
            headers.insert(HeaderName::from_bytes(name.as_bytes())?, value);
        }
    }
    if !headers.contains_key("x-auth-token") {
        if let Some(host) = headers.get("host") {
            ensure!(
                host == &origin[url::Position::BeforeHost..url::Position::AfterPort],
                "Host cannot redirect stored account credentials"
            );
        }
        let token = Zeroizing::new(b64::encode_url_safe(account.token(app)?));
        let mut value = HeaderValue::from_str(&token)?;
        value.set_sensitive(true);
        headers.insert("x-auth-token", value);
    }
    if !headers.contains_key("x-client-package") {
        headers.insert(
            "x-client-package",
            HeaderValue::from_static(app.client_package()),
        );
    }
    let method = Method::from_bytes(args.method.to_ascii_uppercase().as_bytes())?;
    let mut request = http()?.request(method, url).headers(headers);
    if let Some(path) = args.body {
        request = request.body(read_input(&path, u64::MAX)?.to_vec());
    }
    let mut response = request.send().await.map_err(ente_core::http::Error::from)?;
    let status = response.status();
    let mut stdout = std::io::stdout().lock();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(ente_core::http::Error::from)?
    {
        stdout.write_all(&chunk)?;
    }
    stdout.flush()?;
    ensure!(status.is_success(), "HTTP {status}");
    Ok(())
}
