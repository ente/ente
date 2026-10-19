use std::{collections::BTreeMap, io::Write};

use anyhow::{Context, Result, ensure};
use dialoguer::{Confirm, Password, console::Term};
use ente_accounts::{DEFAULT_API_ORIGIN, lifecycle::TwoFactorSetup, signup::Signup};
use ente_core::{b64, crypto::Key};
use serde::{Deserialize, Serialize};
use serde_json::json;
use uuid::Uuid;
use zeroize::{ZeroizeOnDrop, Zeroizing};

use crate::{
    api,
    args::{App, CreateArgs, Options, TotpCommand, VerificationPurpose},
    login::{self, Credentials},
    output, parse_json, read_input,
    vault::{Account, DbKey, State, Vault},
};

#[derive(Clone, Serialize, Deserialize)]
pub struct PendingCreation {
    origin: String,
    app: App,
    name: Option<String>,
    signup: Signup,
}

pub async fn request_otp(
    email: Option<String>,
    app: App,
    host: Option<String>,
    purpose: VerificationPurpose,
    options: &Options,
) -> Result<()> {
    ensure!(
        !options.offline,
        "requesting verification requires network access"
    );
    let origin = origin(host.as_deref())?;
    ensure!(
        email.is_some() || options.can_prompt(),
        "request-otp requires --email when prompts are disabled"
    );
    let email = login::email(email, None, options.can_prompt())?;
    api::accounts_client(&origin, app)?
        .send_otp(
            &email,
            match purpose {
                VerificationPurpose::Create => "signup",
                VerificationPurpose::Login => "login",
            },
        )
        .await?;
    output::action(
        options.json,
        &json!({"email": email, "host": origin, "app": app, "purpose": purpose}),
        &format!(
            "Verification code sent to {}.",
            output::escape_controls(&email)
        ),
    )
}

pub async fn create(args: CreateArgs, options: &Options) -> Result<(State, usize)> {
    ensure!(!options.offline, "account creation requires network access");
    let origin = origin(args.host.as_deref())?;
    let mut credentials = args.input.as_deref().map(Credentials::read).transpose()?;
    let interactive = credentials.is_none() && options.can_prompt();
    ensure!(
        credentials.is_some() || interactive,
        "creation requires password and otp; supply --input PATH or --input - and --accept-terms"
    );
    ensure!(
        args.accept_terms || interactive,
        "account creation requires --accept-terms"
    );
    let email = login::email(
        args.email,
        credentials
            .as_ref()
            .and_then(|input| input.email.as_deref()),
        interactive,
    )?;
    if !args.accept_terms {
        ensure!(
            Confirm::new()
                .with_prompt("Agree to Ente's terms and privacy policy?")
                .default(false)
                .interact_on(&Term::stderr())?,
            "cancelled"
        );
    }
    let vault = Vault::open()?;
    let pending = vault
        .state
        .creations
        .iter()
        .find(|pending| pending.origin == origin && pending.signup.email == email)
        .cloned();
    if let Some(pending) = &pending {
        ensure!(
            pending.app == args.app,
            "unfinished creation uses {}; resume with --app {}",
            pending.app.display_name(),
            pending.app.name()
        );
    }
    let name = args
        .name
        .or_else(|| pending.as_ref().and_then(|pending| pending.name.clone()));
    check_creation(
        &vault.state,
        &origin,
        &email,
        name.as_deref().unwrap_or(&email),
    )?;
    let access = vault.release();
    let client = api::accounts_client(&origin, args.app)?;
    let resuming = pending.is_some();
    let signup = if let Some(pending) = pending {
        pending.signup
    } else {
        if interactive {
            client.send_otp(&email, "signup").await?;
            eprintln!(
                "Verification code sent to {}.",
                output::escape_controls(&email)
            );
        }
        let mut supplied = credentials.as_mut().and_then(|input| input.otp.take());
        let response = loop {
            let code = Zeroizing::new(if interactive {
                Password::new()
                    .with_prompt("Email verification code")
                    .interact_on(&Term::stderr())?
            } else {
                supplied.take().context("creation requires otp in --input; request it with account request-otp --email EMAIL")?
            });
            match client.verify_email(&email, &code, None).await {
                Ok(response) => break response,
                Err(ente_accounts::Error::IncorrectEmailVerificationCode) if interactive => {
                    eprintln!("Incorrect verification code. Try again.")
                }
                Err(error) => return Err(error.into()),
            }
        };
        Signup::verified(email.clone(), response)
            .context("cannot create this account; use account login for an existing account")?
    };
    let password = Zeroizing::new(match credentials.as_mut() {
        Some(input) => std::mem::take(&mut input.password),
        None => {
            let prompt = Password::new().with_prompt("Password");
            if resuming {
                prompt
            } else {
                prompt.with_confirmation("Confirm password", "Passwords do not match")
            }
            .interact_on(&Term::stderr())?
        }
    });
    let signup = signup.prepare(&client, &password).await?;
    let mut vault = access.open()?;
    check_creation(
        &vault.state,
        &origin,
        &email,
        name.as_deref().unwrap_or(&email),
    )?;
    let current = vault
        .state
        .creations
        .iter()
        .position(|pending| pending.origin == origin && pending.signup.email == email);
    if resuming {
        let current =
            current.context("unfinished creation changed; inspect account list and retry")?;
        ensure!(
            vault.state.creations[current].signup.user_id == signup.user_id
                && vault.state.creations[current].app == args.app,
            "unfinished creation changed; retry"
        );
        vault.state.creations[current].name = name.clone();
    } else {
        ensure!(
            current.is_none(),
            "another creation was saved for this email; retry to resume it"
        );
        vault.state.creations.push(PendingCreation {
            origin: origin.clone(),
            app: args.app,
            name: name.clone(),
            signup: signup.clone(),
        });
    }
    vault.save()?;
    let access = vault.release();
    let mut authenticated = signup.finish(&client).await?;
    let email = client.email().await?;
    let (identity, session) = login::saved_keys(&mut authenticated)?;
    let mut vault = access.open()?;
    let pending = vault
        .state
        .creations
        .iter()
        .position(|pending| {
            pending.origin == origin
                && pending.signup.user_id == signup.user_id
                && pending.app == args.app
        })
        .context("unfinished creation changed; inspect account list and retry")?;
    let name = vault.state.creations[pending]
        .name
        .clone()
        .unwrap_or_else(|| email.clone());
    check_creation(&vault.state, &origin, &email, &name)?;
    ensure!(
        !vault
            .state
            .accounts
            .iter()
            .any(|account| account.origin == origin && account.user_id == authenticated.user_id),
        "account already exists on this device; use account login"
    );
    let index = vault.state.accounts.len();
    let storage_id = Uuid::new_v4();
    vault.state.accounts.push(Account {
        storage_id,
        db_key: DbKey(*Key::generate().as_bytes()),
        name,
        email,
        origin,
        user_id: authenticated.user_id,
        identity,
        sessions: BTreeMap::from([(args.app, session)]),
    });
    vault.state.selected = Some(storage_id);
    vault.state.creations.remove(pending);
    vault.save()?;
    Ok((vault.into_state(), index))
}

fn origin(host: Option<&str>) -> Result<String> {
    host.map(api::normalize_host)
        .transpose()
        .map(|host| host.unwrap_or_else(|| DEFAULT_API_ORIGIN.to_owned()))
}

fn check_creation(state: &State, origin: &str, email: &str, name: &str) -> Result<()> {
    ensure!(
        !state
            .accounts
            .iter()
            .any(|account| account.origin == origin && account.email == email),
        "account already exists on this device; use account login"
    );
    state.check_name(name)
}

pub async fn totp(
    command: TotpCommand,
    selected: Option<&str>,
    app: Option<App>,
    options: &Options,
) -> Result<()> {
    ensure!(
        !options.offline,
        "authenticator setup and status require network access"
    );
    let input = match &command {
        TotpCommand::Enable { input } => {
            ensure!(
                input.is_some() || options.can_prompt(),
                "supply secret and totp in --input PATH or --input -"
            );
            input
                .as_deref()
                .map(|path| {
                    parse_json::<Confirmation>(&read_input(path, u64::MAX)?)
                        .context("input must contain secret and totp strings")
                })
                .transpose()?
        }
        _ => None,
    };
    if let Some(input) = &input {
        ensure!(
            !input.secret.is_empty(),
            "supply a nonempty secret in --input"
        );
        ensure!(!input.totp.is_empty(), "supply a nonempty totp in --input");
    }
    let state = State::load()?;
    let account = &state.accounts[state.resolve(selected)?];
    let app = account.app(app)?;
    let client = api::accounts_client(&account.origin, app)?;
    client.set_auth_token(Some(b64::encode_url_safe(account.token(app)?)));
    let enabled = client.get_two_factor_status().await?;
    if matches!(command, TotpCommand::Status) {
        return output::action(
            options.json,
            &json!({"totpEnabled": enabled}),
            if enabled {
                "Authenticator protection is enabled."
            } else {
                "Authenticator protection is disabled."
            },
        );
    }
    ensure!(!enabled, "authenticator protection is already enabled");
    let secret = Zeroizing::new(match &input {
        Some(input) => input.secret.clone(),
        None => client.setup_two_factor().await?.secret_code,
    });
    if matches!(command, TotpCommand::Setup) {
        return if options.json {
            output::json(&json!({"secret": secret.as_str()}))
        } else {
            writeln!(std::io::stdout(), "{}", secret.as_str()).map_err(Into::into)
        };
    }
    let setup = TwoFactorSetup::from_secret(secret.to_string(), &account.identity.recovery_key);
    let incorrect_code =
        "Code not accepted. Check the code and your computer's date and time, then try again.";
    if let Some(input) = input {
        setup
            .enable(&client, &input.totp)
            .await
            .map_err(|error| match error {
                ente_accounts::Error::IncorrectTotp => anyhow::anyhow!(incorrect_code),
                error => error.into(),
            })?;
    } else {
        eprintln!("Add this secret to your authenticator: {}", secret.as_str());
        loop {
            let code = Zeroizing::new(
                Password::new()
                    .with_prompt("Authenticator code")
                    .interact_on(&Term::stderr())?,
            );
            match setup.enable(&client, &code).await {
                Err(ente_accounts::Error::IncorrectTotp) => {
                    eprintln!("{incorrect_code}")
                }
                result => {
                    result?;
                    break;
                }
            }
        }
    }
    output::action(
        options.json,
        &json!({"totpEnabled": true}),
        "Authenticator protection is enabled.",
    )
}

#[derive(Deserialize, ZeroizeOnDrop)]
#[serde(deny_unknown_fields)]
struct Confirmation {
    secret: String,
    totp: String,
}
