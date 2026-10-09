use std::{collections::BTreeMap, path::Path};

use anyhow::{Context, Result, ensure};
use dialoguer::{Input, Password, Select, console::Term};
use ente_accounts::{
    AccountsClient, AuthenticatedAccount, DEFAULT_API_ORIGIN, auth,
    login::{LoginFlow, LoginStep},
};
use ente_core::http::{Api, ApiConfig, Http};
use serde::Deserialize;
use url::Url;
use uuid::Uuid;
use zeroize::{ZeroizeOnDrop, Zeroizing};

use crate::{
    api,
    args::{LoginArgs, Options, Product},
    parse_json, read_input,
    vault::{Account, AccountKeys, DbKey, State, StoredSession, Vault},
};

pub async fn login(
    product: Product,
    args: LoginArgs,
    selected: Option<&str>,
    options: &Options,
) -> Result<(State, usize)> {
    enum Target<'a> {
        Existing(&'a str),
        New(String),
    }

    let target = match selected {
        Some(name) => Target::Existing(name),
        None => Target::New(normalize_host(
            args.host.as_deref().unwrap_or(DEFAULT_API_ORIGIN),
        )?),
    };
    let credentials = args.input.as_deref().map(Credentials::read).transpose()?;
    let interactive = credentials.is_none() && options.can_prompt();
    ensure!(
        credentials.is_some() || interactive,
        "login requires email and password; supply --input <file> or --input -"
    );
    let vault = Vault::open()?;
    if let Some(name) = args.name.as_deref() {
        vault.state.check_name(name)?;
    }
    let (expected, origin) = match target {
        Target::Existing(name) => {
            let account = &vault.state.accounts[vault.state.named(name)?];
            (Some(account.storage_id), account.origin.clone())
        }
        Target::New(origin) => (None, origin),
    };
    let (snapshot, access) = vault.release();
    let mut config = ApiConfig::new(origin.clone());
    config.user_agent = Some(api::USER_AGENT.into());
    Api::new(Http::new()?, config)
        .ping()
        .await
        .context("cannot reach the selected Ente server")?;
    let mut credentials = match credentials {
        Some(credentials) => credentials,
        None => Credentials::prompt()?,
    };
    let client = api::accounts_client(&origin, product)?;
    let mut authenticated = authenticate(&client, &mut credentials, interactive).await?;
    client.set_auth_token(Some(ente_core::b64::encode_url_safe(
        &authenticated.secrets.token,
    )));

    let supplied_name = args.name.is_some();
    let requested_name = args.name;
    let mut previous_session = None;
    let result = async {
        let email = client.email().await?;
        let snapshot_existing = snapshot.accounts.iter().position(|account| {
            account.origin == origin && account.user_id == authenticated.user_id
        });
        if let Some(expected) = expected {
            ensure!(
                snapshot_existing
                    .is_some_and(|index| snapshot.accounts[index].storage_id == expected),
                "authenticated identity does not match --account"
            );
        }
        let mut new_name = requested_name.unwrap_or_else(|| email.clone());
        if snapshot_existing.is_none() {
            while let Err(error) = snapshot.check_name(&new_name) {
                if !interactive {
                    return Err(error.context("supply a different local account name with --name"));
                }
                eprintln!("{error}");
                new_name = Input::new()
                    .with_prompt("Local account name")
                    .interact_on(&Term::stderr())?;
            }
        }
        drop(snapshot);

        let mut vault = access.open()?;
        let existing = vault
            .state
            .accounts
            .iter()
            .position(|a| a.origin == origin && a.user_id == authenticated.user_id);
        if let Some(expected) = expected {
            let current = vault
                .state
                .accounts
                .iter()
                .position(|account| account.storage_id == expected)
                .context("selected account was removed during login")?;
            ensure!(
                existing == Some(current),
                "authenticated identity does not match --account"
            );
        }
        let recovery_key = Zeroizing::new(
            authenticated
                .recovery_key
                .take()
                .context("account has no recovery key")?,
        );
        let identity = AccountKeys {
            master_key: std::mem::take(&mut authenticated.secrets.master_key),
            recovery_key: auth::recovery_key_from_mnemonic_or_hex(&recovery_key)?.into_vec(),
            secret_key: std::mem::take(&mut authenticated.secrets.secret_key),
        };
        let session = StoredSession {
            token: std::mem::take(&mut authenticated.secrets.token),
        };
        let index = if let Some(index) = existing {
            ensure!(
                !supplied_name,
                "account already exists; use accounts rename to change its local name"
            );
            let account = &mut vault.state.accounts[index];
            account.email = email;
            account.identity = identity;
            previous_session = account.sessions.insert(product, session);
            index
        } else {
            vault.state.check_name(&new_name)?;
            let index = vault.state.accounts.len();
            vault.state.accounts.push(Account {
                db_key: DbKey(*ente_core::crypto::Key::generate().as_bytes()),
                storage_id: Uuid::new_v4(),
                name: new_name,
                email,
                origin,
                user_id: authenticated.user_id,
                identity,
                sessions: BTreeMap::from([(product, session)]),
            });
            index
        };
        if expected.is_none() {
            vault.state.selected = Some(vault.state.accounts[index].storage_id);
        }
        vault.save()?;
        Ok((vault.into_state(), index))
    }
    .await;
    if result.is_ok()
        && let Some(previous) = &previous_session
    {
        client.set_auth_token(Some(ente_core::b64::encode_url_safe(&previous.token)));
    }
    if (result.is_err() || previous_session.is_some())
        && let Err(error) = client.logout().await
        && !matches!(&error, ente_accounts::Error::Http(error) if error.status_code() == Some(401))
    {
        let session = if result.is_err() {
            "unsaved"
        } else {
            "previous"
        };
        eprintln!("Could not revoke the {session} login session: {error}");
    }
    result
}

fn normalize_host(host: &str) -> Result<String> {
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

#[derive(Deserialize, ZeroizeOnDrop)]
#[serde(deny_unknown_fields)]
struct Credentials {
    email: String,
    password: String,
    otp: Option<String>,
    totp: Option<String>,
}

impl Credentials {
    fn read(path: &Path) -> Result<Self> {
        parse_json(&read_input(path)?)
            .context("login input must contain email and password, with optional otp and totp")
    }

    fn prompt() -> Result<Self> {
        Ok(Self {
            email: Input::new()
                .with_prompt("Email")
                .interact_on(&Term::stderr())?,
            password: Password::new()
                .with_prompt("Password")
                .interact_on(&Term::stderr())?,
            otp: None,
            totp: None,
        })
    }
}

async fn authenticate(
    client: &AccountsClient,
    credentials: &mut Credentials,
    interactive: bool,
) -> Result<AuthenticatedAccount> {
    let (mut flow, mut step) = LoginFlow::start(client, credentials.email.clone()).await?;
    loop {
        step = match step {
            LoginStep::EmailCode => loop {
                let code = verification_code(
                    &mut credentials.otp,
                    interactive,
                    "Email verification code",
                    "otp",
                )?;
                match flow.submit_code(client, &code).await {
                    Ok(next) => break next,
                    Err(ente_accounts::Error::IncorrectEmailVerificationCode) if interactive => {
                        eprintln!("Incorrect email verification code. Try again.");
                    }
                    Err(ente_accounts::Error::EmailVerificationCodeExpired) if interactive => {
                        flow.resend_code(client).await?;
                    }
                    Err(error) => return Err(error.into()),
                }
            },
            LoginStep::Password => flow.submit_password(client, &credentials.password).await?,
            LoginStep::SecondFactor { totp, passkey } => {
                let use_passkey = match (totp, passkey) {
                    (true, true) if interactive => {
                        Select::new()
                            .with_prompt("Verify with")
                            .items(["Authenticator code", "Passkey in browser"])
                            .interact_on(&Term::stderr())?
                            == 1
                    }
                    (true, _) => false,
                    (false, true) => true,
                    (false, false) => {
                        return Err(
                            ente_accounts::Error::Protocol("Missing second factor".into()).into(),
                        );
                    }
                };
                if use_passkey {
                    ensure!(
                        interactive,
                        "passkey login requires an interactive terminal without --input or --no-input"
                    );
                    let url = flow.passkey_url(client, "ente-cli://passkey")?;
                    eprintln!("Open this URL to verify your passkey:\n{url}");
                    loop {
                        Input::<String>::new()
                            .with_prompt("Press Enter after completing verification")
                            .allow_empty(true)
                            .interact_on(&Term::stderr())?;
                        if let Some(next) = flow.poll_passkey(client).await? {
                            break next;
                        }
                    }
                } else {
                    loop {
                        let code = verification_code(
                            &mut credentials.totp,
                            interactive,
                            "Authenticator code",
                            "totp",
                        )?;
                        match flow.submit_code(client, &code).await {
                            Ok(next) => break next,
                            Err(ente_accounts::Error::IncorrectTotp) if interactive => {
                                eprintln!("Incorrect TOTP code. Try again.");
                            }
                            Err(error) => return Err(error.into()),
                        }
                    }
                }
            }
            LoginStep::Complete(account) => return Ok(*account),
        };
    }
}

fn verification_code(
    supplied: &mut Option<String>,
    interactive: bool,
    label: &str,
    field: &str,
) -> Result<String> {
    if interactive {
        return Ok(Password::new()
            .with_prompt(label)
            .interact_on(&Term::stderr())?);
    }
    supplied
        .take()
        .with_context(|| format!("login requires {label}; supply {field} in --input"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noninteractive_codes_come_from_their_login_input_fields() {
        let mut credentials: Credentials = parse_json(
            br#"{"email":"user@example.org","password":"secret","otp":"123456","totp":"654321"}"#,
        )
        .unwrap();
        assert_eq!(
            verification_code(
                &mut credentials.otp,
                false,
                "Email verification code",
                "otp"
            )
            .unwrap(),
            "123456"
        );
        assert_eq!(
            verification_code(&mut credentials.totp, false, "Authenticator code", "totp").unwrap(),
            "654321"
        );
        assert!(
            verification_code(&mut credentials.totp, false, "Authenticator code", "totp")
                .unwrap_err()
                .to_string()
                .contains("supply totp in --input")
        );
    }
}
