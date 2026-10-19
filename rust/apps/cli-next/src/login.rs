use std::{collections::BTreeMap, path::Path};

use anyhow::{Context, Result, ensure};
use dialoguer::{Input, Password, Select, console::Term};
use ente_accounts::{
    AccountsClient, AuthenticatedAccount, DEFAULT_API_ORIGIN, auth,
    login::{LoginFlow, LoginStep},
};
use ente_core::http::{Api, ApiConfig, Http};
use serde::Deserialize;
use uuid::Uuid;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::{
    api,
    args::{LoginArgs, Options},
    output, parse_json, read_input,
    vault::{Account, AccountKeys, DbKey, State, StoredSession, Vault},
};

pub async fn login(args: LoginArgs, options: &Options) -> Result<(State, usize)> {
    let app = args.app;
    let host = args.host.as_deref().map(api::normalize_host).transpose()?;
    let credentials = args.input.as_deref().map(Credentials::read).transpose()?;
    let interactive = credentials.is_none() && options.can_prompt();
    ensure!(
        credentials.is_some() || interactive,
        "login requires email and password; supply --input <file> or --input -"
    );
    let email = email(
        args.email,
        credentials
            .as_ref()
            .and_then(|input| input.email.as_deref()),
        interactive,
    )?;
    let vault = Vault::open()?;
    let index = if let Some(name) = args.name.as_deref() {
        vault
            .state
            .accounts
            .iter()
            .position(|account| account.name == name)
    } else if vault.state.accounts.is_empty() {
        None
    } else {
        Some(vault.state.resolve(None)?)
    };
    let (expected, origin) = if let Some(index) = index {
        let account = &vault.state.accounts[index];
        ensure!(
            host.as_ref().is_none_or(|host| *host == account.origin),
            "account {:?} uses {}; supply a new account name to log in to another server",
            account.name,
            account.origin,
        );
        (Some(account.storage_id), account.origin.clone())
    } else {
        if let Some(name) = args.name.as_deref() {
            vault.state.check_name(name)?;
        }
        (None, host.unwrap_or_else(|| DEFAULT_API_ORIGIN.to_owned()))
    };
    let access = vault.release();
    let mut config = ApiConfig::new(origin.clone());
    config.user_agent = Some(api::USER_AGENT.into());
    Api::new(Http::new()?, config)
        .ping()
        .await
        .context("cannot reach the selected Ente server")?;
    let mut credentials = match credentials {
        Some(credentials) => credentials,
        None => Credentials {
            email: None,
            password: Password::new()
                .with_prompt("Password")
                .interact_on(&Term::stderr())?,
            otp: None,
            totp: None,
        },
    };
    let client = api::accounts_client(&origin, app)?;
    let mut authenticated = authenticate(&client, email, &mut credentials, interactive).await?;
    client.set_auth_token(Some(ente_core::b64::encode_url_safe(
        &authenticated.secrets.token,
    )));

    let mut previous_session = None;
    let result = async {
        let email = client.email().await?;
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
                "authenticated identity does not match the saved account"
            );
        }
        let (identity, session) = saved_keys(&mut authenticated)?;
        let index = if let Some(index) = existing {
            ensure!(
                expected.is_some() || args.name.is_none(),
                "account already exists; use account rename to change its local name"
            );
            let account = &mut vault.state.accounts[index];
            account.email = email;
            account.identity = identity;
            previous_session = account.sessions.insert(app, session);
            index
        } else {
            let new_name = args.name.unwrap_or_else(|| email.clone());
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
                sessions: BTreeMap::from([(app, session)]),
            });
            vault.state.selected = Some(vault.state.accounts[index].storage_id);
            index
        };
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
        eprintln!("Could not end the {session} login: {error}");
    }
    result
}

#[derive(Deserialize, ZeroizeOnDrop)]
#[serde(deny_unknown_fields)]
pub(crate) struct Credentials {
    pub email: Option<String>,
    #[serde(default)]
    pub password: String,
    pub otp: Option<String>,
    pub totp: Option<String>,
}

impl Credentials {
    pub fn read(path: &Path) -> Result<Self> {
        let input: Self = parse_json(&read_input(path, u64::MAX)?)
            .context("input must contain email and password strings, with optional otp and totp; --email can supply email")?;
        ensure!(
            !input.password.is_empty(),
            "supply a nonempty password in --input"
        );
        Ok(input)
    }
}

pub(crate) fn email(
    flag: Option<String>,
    input: Option<&str>,
    interactive: bool,
) -> Result<String> {
    ensure!(
        flag.as_deref()
            .zip(input)
            .is_none_or(|(flag, input)| flag.trim().to_lowercase() == input.trim().to_lowercase()),
        "--email differs from email in --input"
    );
    let email = match flag.or_else(|| input.map(str::to_owned)) {
        Some(email) => email,
        None => {
            ensure!(interactive, "supply email through --email or --input");
            Input::new()
                .with_prompt("Email")
                .interact_on(&Term::stderr())?
        }
    };
    let email = email.trim().to_lowercase();
    ensure!(!email.is_empty(), "email cannot be empty");
    Ok(email)
}

pub(crate) fn saved_keys(
    authenticated: &mut AuthenticatedAccount,
) -> Result<(AccountKeys, StoredSession)> {
    let recovery_key = Zeroizing::new(
        authenticated
            .recovery_key
            .take()
            .context("account has no recovery key")?,
    );
    Ok((
        AccountKeys {
            master_key: std::mem::take(&mut authenticated.secrets.master_key),
            recovery_key: auth::recovery_key_from_mnemonic_or_hex(&recovery_key)?.into_vec(),
            secret_key: std::mem::take(&mut authenticated.secrets.secret_key),
        },
        StoredSession {
            token: std::mem::take(&mut authenticated.secrets.token),
        },
    ))
}

async fn authenticate(
    client: &AccountsClient,
    email: String,
    credentials: &mut Credentials,
    interactive: bool,
) -> Result<AuthenticatedAccount> {
    let displayed_email = output::escape_controls(&email);
    let (mut flow, mut step) = LoginFlow::prepare(client, email).await?;
    if matches!(step, LoginStep::EmailCode) {
        if interactive {
            flow.resend_code(client).await?;
            eprintln!("Verification code sent to {displayed_email}.");
        } else {
            ensure!(
                credentials.otp.is_some(),
                "login requires otp in --input; request it with account request-otp --email EMAIL --purpose login"
            );
        }
    }
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
                        eprintln!("Incorrect verification code. Try again.");
                    }
                    Err(ente_accounts::Error::EmailVerificationCodeExpired) if interactive => {
                        flow.resend_code(client).await?;
                        eprintln!(
                            "Verification code expired. A new code has been sent to {displayed_email}."
                        );
                    }
                    Err(error) => return Err(error.into()),
                }
            },
            LoginStep::Password => loop {
                match flow.submit_password(client, &credentials.password).await {
                    Ok(next) => break next,
                    Err(ente_accounts::Error::IncorrectPassword) if interactive => {
                        eprintln!("Incorrect password. Try again.");
                        credentials.password.zeroize();
                        credentials.password = Password::new()
                            .with_prompt("Password")
                            .interact_on(&Term::stderr())?;
                    }
                    Err(error) => return Err(error.into()),
                }
            },
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
                    eprintln!("Opening browser for passkey authentication.");
                    if !url::Url::parse(&url).is_ok_and(|url| {
                        matches!(url.scheme(), "http" | "https") && open::that(url.as_str()).is_ok()
                    }) {
                        eprintln!(
                            "Could not open the browser. Open this URL to complete passkey authentication:"
                        );
                    }
                    eprintln!("{url}\n");
                    loop {
                        Input::<String>::new()
                            .with_prompt("Press Enter after completing authentication")
                            .allow_empty(true)
                            .interact_on(&Term::stderr())?;
                        if let Some(next) = flow.poll_passkey(client).await? {
                            break next;
                        }
                        eprintln!("Passkey authentication is not complete.");
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
                                eprintln!("Incorrect authenticator code. Try again.");
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
