use std::{
    collections::BTreeMap,
    io::{self, IsTerminal},
    path::Path,
};

use anyhow::{Context, Result, ensure};
use dialoguer::{Input, Password, Select, console::Term};
use ente_accounts::{
    AuthFlow, AuthFlowUi, DEFAULT_API_ORIGIN, LoginParams, OtpPurpose, SecondFactorMethod,
    TotpPurpose, auth,
};
use ente_core::http::{Api, ApiConfig, Http};
use serde::Deserialize;
use url::Url;
use uuid::Uuid;
use zeroize::{ZeroizeOnDrop, Zeroizing};

use crate::{
    api,
    args::{LoginArgs, Product},
    parse_json, read_input,
    vault::{Account, AccountKeys, State, StoredSession, Vault},
};

pub async fn login(
    product: Product,
    args: LoginArgs,
    selected: Option<&str>,
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
    let (params, mut ui) = match credentials {
        Some(credentials) => credentials.into_login(),
        None => LoginUi::prompt()?,
    };
    let client = api::accounts_client(&origin, product)?;
    let mut authenticated = AuthFlow::new(&client, &mut ui).login(params).await?;
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
                if !ui.interactive {
                    return Err(error);
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

    fn into_login(mut self) -> (LoginParams, LoginUi) {
        let params = LoginParams {
            email: std::mem::take(&mut self.email),
            password: Zeroizing::new(std::mem::take(&mut self.password)),
        };
        (
            params,
            LoginUi {
                interactive: false,
                credentials: Some(self),
            },
        )
    }
}

struct LoginUi {
    interactive: bool,
    credentials: Option<Credentials>,
}

impl LoginUi {
    fn prompt() -> Result<(LoginParams, Self)> {
        ensure!(
            io::stdin().is_terminal() && io::stderr().is_terminal(),
            "noninteractive login requires --input <file> or --input -"
        );
        let email = Input::new()
            .with_prompt("Email")
            .interact_on(&Term::stderr())?;
        let password = Password::new()
            .with_prompt("Password")
            .interact_on(&Term::stderr())?;
        Ok((
            LoginParams {
                email,
                password: Zeroizing::new(password),
            },
            Self {
                interactive: true,
                credentials: None,
            },
        ))
    }

    fn secret_prompt(&self, label: &str) -> ente_accounts::Result<String> {
        Password::new()
            .with_prompt(label)
            .interact_on(&Term::stderr())
            .map_err(|error| ente_accounts::Error::Ui(Box::new(error)))
    }
}

impl AuthFlowUi for LoginUi {
    fn read_email_otp(
        &mut self,
        _email: &str,
        _purpose: OtpPurpose,
        _resent: bool,
    ) -> ente_accounts::Result<String> {
        if self.interactive {
            return self.secret_prompt("Email verification code");
        }
        self.credentials
            .as_mut()
            .and_then(|c| c.otp.take())
            .ok_or_else(|| {
                ente_accounts::Error::InvalidInput(
                    "login requires an email verification code; supply otp in --input".into(),
                )
            })
    }

    fn read_totp_code(&mut self, _purpose: TotpPurpose) -> ente_accounts::Result<String> {
        if self.interactive {
            return self.secret_prompt("Authenticator code");
        }
        self.credentials
            .as_mut()
            .and_then(|c| c.totp.take())
            .ok_or_else(|| {
                ente_accounts::Error::InvalidInput(
                    "login requires an authenticator code; supply totp in --input".into(),
                )
            })
    }

    fn report_retryable_error(&mut self, message: &str) -> ente_accounts::Result<()> {
        if !self.interactive {
            return Err(ente_accounts::Error::InvalidInput(message.into()));
        }
        eprintln!("{message}");
        Ok(())
    }

    fn choose_second_factor(
        &mut self,
        methods: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        if !self.interactive {
            return Ok(SecondFactorMethod::Totp);
        }
        let labels: Vec<_> = methods
            .iter()
            .map(|method| match method {
                SecondFactorMethod::Totp => "Authenticator code",
                SecondFactorMethod::Passkey => "Passkey in browser",
            })
            .collect();
        let index = Select::new()
            .with_prompt("Verify with")
            .items(&labels)
            .interact_on(&Term::stderr())
            .map_err(|error| ente_accounts::Error::Ui(Box::new(error)))?;
        Ok(methods[index])
    }

    fn present_passkey_verification(&mut self, url: &str) -> ente_accounts::Result<()> {
        if !self.interactive {
            return Err(ente_accounts::Error::InvalidInput(
                "passkey login requires an interactive terminal".into(),
            ));
        }
        eprintln!("Open this URL to verify your passkey:\n{url}");
        Ok(())
    }

    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        Input::<String>::new()
            .with_prompt("Press Enter after completing verification")
            .allow_empty(true)
            .interact_on(&Term::stderr())
            .map_err(|error| ente_accounts::Error::Ui(Box::new(error)))?;
        Ok(())
    }

    fn present_totp_secret(
        &mut self,
        _secret_code: &str,
        _qr_code: &str,
    ) -> ente_accounts::Result<()> {
        Err(ente_accounts::Error::InvalidInput(
            "login cannot enroll a new authenticator".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noninteractive_codes_come_from_their_login_input_fields() {
        let credentials: Credentials = parse_json(
            br#"{"email":"user@example.org","password":"secret","otp":"123456","totp":"654321"}"#,
        )
        .unwrap();
        let mut ui = LoginUi {
            interactive: false,
            credentials: Some(credentials),
        };
        assert_eq!(
            ui.read_email_otp("user@example.org", OtpPurpose::Login, false)
                .unwrap(),
            "123456"
        );
        assert_eq!(ui.read_totp_code(TotpPurpose::Login).unwrap(), "654321");
        assert!(
            ui.read_totp_code(TotpPurpose::Login)
                .unwrap_err()
                .to_string()
                .contains("supply totp in --input")
        );
    }
}
