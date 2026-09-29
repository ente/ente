use crate::{
    api::client::USER_AGENT,
    cli::account::{AccountCommand, AccountSubcommands, AddArgs, CreateArgs},
    models::{
        account::{Account, App},
        error::{Error, Result},
    },
    storage::Storage,
};
use dialoguer::{Input, Password, Select};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthenticatedAccount, TwoFactorSetup,
    login::{LoginFlow, LoginStep},
    signup::Signup,
};
use ente_core::b64;
use ente_core::urls::PRODUCTION_API_ORIGIN;
use std::{path::PathBuf, str::FromStr};
use zeroize::Zeroizing;

pub async fn handle_account_command(cmd: AccountCommand, storage: &Storage) -> Result<()> {
    match cmd.command {
        AccountSubcommands::List => list_accounts(storage),
        AccountSubcommands::Add(args) => add_account(storage, args).await,
        AccountSubcommands::Create(args) => create_account(storage, args).await,
        AccountSubcommands::Update { email, dir, app } => {
            update_account(storage, &email, &dir, &app)
        }
        AccountSubcommands::GetToken { email, app } => get_token(storage, &email, &app),
        AccountSubcommands::TwoFactor {
            email,
            app,
            totp_code,
            show_recovery_key,
        } => enable_two_factor(storage, &email, &app, totp_code, show_recovery_key).await,
    }
}

#[derive(Clone, Copy)]
enum SecondFactorMethod {
    Totp,
    Passkey,
}

async fn login(
    client: &AccountsClient,
    email: &str,
    password: Option<String>,
    mut otp: Option<String>,
    mut totp_code: Option<String>,
    second_factor: Option<SecondFactorMethod>,
) -> Result<AuthenticatedAccount> {
    let interactive_password = password.is_none();
    let mut password = Zeroizing::new(prompt_password(password, "Enter your password")?);
    let (mut flow, mut step) = LoginFlow::start(client, email.into()).await?;
    loop {
        step = match step {
            LoginStep::EmailCode => {
                let mut resent = false;
                loop {
                    let prompt = if resent {
                        format!("Enter the new email-MFA code sent to {email}")
                    } else {
                        format!("Enter the email-MFA code sent to {email}")
                    };
                    let code = take_code(&mut otp, &prompt)?;
                    match flow.submit_code(client, &code).await {
                        Ok(next) => break next,
                        Err(ente_accounts::Error::IncorrectEmailVerificationCode) => {
                            println!("\nIncorrect email verification code. Try again.");
                            resent = false;
                        }
                        Err(ente_accounts::Error::EmailVerificationCodeExpired) => {
                            flow.resend_code(client).await?;
                            resent = true;
                        }
                        Err(error) => return Err(error.into()),
                    }
                }
            }
            LoginStep::Password => loop {
                match flow.submit_password(client, &password).await {
                    Ok(next) => break next,
                    Err(ente_accounts::Error::IncorrectPassword) if interactive_password => {
                        println!("\nIncorrect password. Try again.");
                        password = Zeroizing::new(prompt_password(None, "Re-enter your password")?);
                    }
                    Err(error) => return Err(error.into()),
                }
            },
            LoginStep::SecondFactor { totp, passkey } => {
                let method = match (totp, passkey) {
                    (true, true) => match second_factor {
                        Some(method) => method,
                        None => match Select::new()
                            .with_prompt("Choose verification method")
                            .items(&["TOTP (Authenticator app)", "Passkey"])
                            .default(0)
                            .interact()
                            .map_err(|error| Error::InvalidInput(error.to_string()))?
                        {
                            0 => SecondFactorMethod::Totp,
                            _ => SecondFactorMethod::Passkey,
                        },
                    },
                    (true, false) => SecondFactorMethod::Totp,
                    (false, true) => SecondFactorMethod::Passkey,
                    (false, false) => {
                        return Err(
                            ente_accounts::Error::Protocol("Missing second factor".into()).into(),
                        );
                    }
                };
                match method {
                    SecondFactorMethod::Totp => loop {
                        let code = take_code(&mut totp_code, "Enter TOTP code")?;
                        match flow.submit_code(client, &code).await {
                            Ok(next) => break next,
                            Err(ente_accounts::Error::IncorrectTotp) => {
                                println!("\nIncorrect TOTP code. Try again.")
                            }
                            Err(error) => return Err(error.into()),
                        }
                    },
                    SecondFactorMethod::Passkey => {
                        let url = flow.passkey_url(client, "ente-cli://passkey")?;
                        println!("\nPasskey verification required");
                        println!("Open this URL in your browser to verify your passkey:\n{url}");
                        if can_open_automatically(&url) && open::that(&url).is_err() {
                            log::error!("failed to open browser");
                        }
                        loop {
                            Input::<String>::new()
                                .with_prompt(
                                    "Press Enter once you have completed passkey verification",
                                )
                                .allow_empty(true)
                                .interact_text()
                                .map_err(|error| Error::InvalidInput(error.to_string()))?;
                            if let Some(next) = flow.poll_passkey(client).await? {
                                break next;
                            }
                        }
                    }
                }
            }
            LoginStep::Complete(account) => return Ok(*account),
        };
    }
}

async fn signup(
    client: &AccountsClient,
    email: &str,
    password: &str,
    mut otp: Option<String>,
    source: Option<&str>,
) -> Result<AuthenticatedAccount> {
    client.send_otp(email, "signup").await?;
    let mut resent = false;
    let verification = loop {
        let prompt = if resent {
            format!("Enter the new signup verification code sent to {email}")
        } else {
            format!("Enter the signup verification code sent to {email}")
        };
        let code = take_code(&mut otp, &prompt)?;
        match client.verify_email(email, &code, source).await {
            Ok(response) => break response,
            Err(ente_accounts::Error::IncorrectEmailVerificationCode) => {
                println!("\nIncorrect email verification code. Try again.");
                resent = false;
            }
            Err(ente_accounts::Error::EmailVerificationCodeExpired) => {
                client.send_otp(email, "signup").await?;
                resent = true;
            }
            Err(error) => return Err(error.into()),
        }
    };
    Ok(Signup::verified(email.into(), verification)?
        .prepare(client, password)
        .await?
        .finish(client)
        .await?)
}

async fn setup_two_factor(
    client: &AccountsClient,
    master_key: &[u8],
    key_attributes: &ente_accounts::KeyAttributes,
    mut code: Option<String>,
) -> Result<TwoFactorSetup> {
    let setup = TwoFactorSetup::start(client, master_key, key_attributes).await?;
    println!("\nTOTP setup secret: {}", setup.secret_code);
    println!("Add this secret to your authenticator app, then enter the current code.");
    loop {
        let code = take_code(
            &mut code,
            "Enter the current TOTP from your authenticator app",
        )?;
        match setup.enable(client, &code).await {
            Ok(()) => return Ok(setup),
            Err(ente_accounts::Error::IncorrectTotp) => println!(
                "Incorrect TOTP code. Enter the current code from your authenticator app and try again."
            ),
            Err(error) => return Err(error.into()),
        }
    }
}

fn take_code(code: &mut Option<String>, prompt: &str) -> Result<String> {
    match code.take() {
        Some(code) => Ok(code),
        None => read_six_digit_code(prompt),
    }
}

fn list_accounts(storage: &Storage) -> Result<()> {
    let accounts = storage.accounts().list()?;

    if accounts.is_empty() {
        println!("No accounts configured. Use 'ente account create' or 'ente account add'.");
        return Ok(());
    }

    println!("\nConfigured accounts:\n");
    println!(
        "{:<30} {:<10} {:<30} {:<40}",
        "Email", "App", "Endpoint", "Export Directory"
    );
    println!("{}", "-".repeat(110));

    for account in accounts {
        let endpoint_display = if account.endpoint == PRODUCTION_API_ORIGIN {
            "api.ente.com (prod)".to_string()
        } else if account.endpoint.starts_with("http://localhost") {
            format!(
                "localhost:{}",
                account.endpoint.split(':').next_back().unwrap_or("")
            )
        } else {
            account.endpoint.clone()
        };

        println!(
            "{:<30} {:<10} {:<30} {:<40}",
            account.email,
            account.app.to_string(),
            endpoint_display,
            account.export_dir.as_deref().unwrap_or("Not configured")
        );
    }

    Ok(())
}

async fn add_account(storage: &Storage, args: AddArgs) -> Result<()> {
    println!("\n=== Add Existing Ente Account ===\n");

    let AddArgs {
        email,
        password,
        app,
        endpoint,
        export_dir,
        otp,
        totp_code,
        second_factor,
    } = args;

    let email = prompt_email(email)?;
    let app = resolve_app(&app)?;
    let second_factor = parse_second_factor(second_factor.as_deref())?;

    if let Ok(Some(_)) = storage.accounts().get(&email, app) {
        println!("\nAccount already exists for {email} with app {app}");
        return Ok(());
    }

    let export_dir = resolve_export_dir(export_dir, &email)?;
    ensure_export_dir(&export_dir)?;

    let client = new_accounts_client(&endpoint, app)?;
    let authenticated = login(&client, &email, password, otp, totp_code, second_factor).await?;

    persist_account(storage, &email, app, &endpoint, &export_dir, &authenticated)?;

    println!("\nAccount added successfully!");
    println!("  Email: {email}");
    println!("  App: {app}");
    println!("  Endpoint: {endpoint}");
    println!("  Export directory: {export_dir}");

    Ok(())
}

async fn create_account(storage: &Storage, args: CreateArgs) -> Result<()> {
    println!("\n=== Create Ente Account ===\n");

    let CreateArgs {
        email,
        password,
        app,
        endpoint,
        export_dir,
        otp,
        source,
        setup_2fa,
        totp_code,
        show_recovery_key,
    } = args;

    let email = prompt_email(email)?;
    let password = Zeroizing::new(prompt_password(password, "Choose a password")?);
    let app = resolve_app(&app)?;

    if let Ok(Some(_)) = storage.accounts().get(&email, app) {
        println!("\nAccount already exists for {email} with app {app}");
        return Ok(());
    }

    let export_dir = resolve_export_dir(export_dir, &email)?;
    ensure_export_dir(&export_dir)?;

    let client = new_accounts_client(&endpoint, app)?;
    let created = signup(&client, &email, &password, otp, source.as_deref()).await?;

    persist_account(storage, &email, app, &endpoint, &export_dir, &created)?;

    println!("\nAccount created successfully!");
    println!("  Email: {email}");
    println!("  App: {app}");
    println!("  Endpoint: {endpoint}");
    println!("  Export directory: {export_dir}");

    if show_recovery_key {
        if let Some(recovery_key) = created.recovery_key.as_deref() {
            println!("\nRecovery key: {recovery_key}");
        } else {
            println!("\nRecovery key is not available for this account.");
        }
    }

    if setup_2fa {
        let result = setup_two_factor(
            &client,
            &created.secrets.master_key,
            &created.key_attributes,
            totp_code,
        )
        .await?;

        println!("\nTwo-factor authentication enabled.");
        if show_recovery_key {
            println!("Recovery key: {}", result.recovery_key);
        }
    }

    Ok(())
}

async fn enable_two_factor(
    storage: &Storage,
    email: &str,
    app_arg: &str,
    totp_code: Option<String>,
    show_recovery_key: bool,
) -> Result<()> {
    let app = resolve_app(app_arg)?;
    let account = storage
        .accounts()
        .get(email, app)?
        .ok_or_else(|| Error::NotFound(format!("Account not found: {email}")))?;
    let secrets = storage
        .accounts()
        .get_secrets(account.user_id, account.app)?
        .ok_or_else(|| Error::NotFound(format!("Secrets not found for account {email}")))?;

    let client = new_accounts_client(&account.endpoint, app)?;
    let token = b64::encode_url_safe(&secrets.token);
    client.set_auth_token(Some(token));

    let key_attributes = client
        .get_session_validity()
        .await?
        .key_attributes
        .ok_or(ente_accounts::Error::MissingKeyAttributes)?;
    let result = setup_two_factor(&client, &secrets.master_key, &key_attributes, totp_code).await?;

    println!("\nTwo-factor authentication enabled for {email}.");
    if show_recovery_key {
        println!("Recovery key: {}", result.recovery_key);
    }

    Ok(())
}

fn update_account(storage: &Storage, email: &str, dir: &str, app_str: &str) -> Result<()> {
    let app = resolve_app(app_str)?;

    if storage.accounts().get(email, app)?.is_none() {
        return Err(Error::NotFound(format!(
            "Account not found: {email} (app: {app})"
        )));
    }

    ensure_export_dir(dir)?;
    storage.accounts().update_export_dir(email, app, dir)?;

    println!("\nAccount updated successfully!");
    println!("  Email: {email}");
    println!("  App: {app}");
    println!("  New export directory: {dir}");

    Ok(())
}

fn get_token(storage: &Storage, email: &str, app_str: &str) -> Result<()> {
    let app = resolve_app(app_str)?;

    let account = storage
        .accounts()
        .get(email, app)?
        .ok_or_else(|| Error::NotFound(format!("Account not found: {email}")))?;

    let secrets = storage
        .accounts()
        .get_secrets(account.user_id, account.app)?
        .ok_or_else(|| Error::NotFound(format!("Secrets not found for account {email}")))?;

    let token = b64::encode_url_safe(&secrets.token);
    println!("{token}");

    Ok(())
}

fn persist_account(
    storage: &Storage,
    email: &str,
    app: App,
    endpoint: &str,
    export_dir: &str,
    authenticated: &AuthenticatedAccount,
) -> Result<()> {
    let account = Account {
        user_id: authenticated.user_id,
        email: email.to_string(),
        app,
        endpoint: endpoint.to_string(),
        export_dir: Some(export_dir.to_string()),
    };

    storage.accounts().add(&account)?;
    storage
        .accounts()
        .store_secrets(account.user_id, account.app, &authenticated.secrets)?;

    Ok(())
}

fn prompt_email(email_arg: Option<String>) -> Result<String> {
    if let Some(email) = email_arg {
        Ok(email)
    } else {
        Input::new()
            .with_prompt("Enter your email address")
            .interact_text()
            .map_err(|e| Error::InvalidInput(e.to_string()))
    }
}

fn prompt_password(password_arg: Option<String>, prompt: &str) -> Result<String> {
    if let Some(password) = password_arg {
        Ok(password)
    } else {
        Password::new()
            .with_prompt(prompt)
            .interact()
            .map_err(|e| Error::InvalidInput(e.to_string()))
    }
}

fn resolve_export_dir(export_dir_arg: Option<String>, email: &str) -> Result<String> {
    if let Some(dir) = export_dir_arg {
        Ok(dir)
    } else {
        Input::new()
            .with_prompt("Enter export directory path")
            .default(format!("./exports/{email}"))
            .interact_text()
            .map_err(|e| Error::InvalidInput(e.to_string()))
    }
}

fn ensure_export_dir(dir: &str) -> Result<()> {
    let export_path = PathBuf::from(dir);
    if !export_path.exists() {
        println!("Creating export directory: {dir}");
        std::fs::create_dir_all(&export_path).map_err(Error::Io)?;
    }
    Ok(())
}

fn resolve_app(app_arg: &str) -> Result<App> {
    App::from_str(app_arg).map_err(Error::InvalidInput)
}

fn parse_second_factor(second_factor: Option<&str>) -> Result<Option<SecondFactorMethod>> {
    second_factor
        .map(|value| match value.trim().to_ascii_lowercase().as_str() {
            "totp" => Ok(SecondFactorMethod::Totp),
            "passkey" => Ok(SecondFactorMethod::Passkey),
            other => Err(Error::InvalidInput(format!(
                "Invalid second-factor method: {other}. Must be one of: totp, passkey"
            ))),
        })
        .transpose()
}

fn new_accounts_client(endpoint: &str, app: App) -> Result<AccountsClient> {
    AccountsClient::new(
        AccountsClientConfig::new(app.client_package())
            .with_origin(endpoint.to_string())
            .with_user_agent(USER_AGENT),
    )
    .map_err(Error::from)
}

fn can_open_automatically(url: &str) -> bool {
    url.split_once("://").is_some_and(|(scheme, _)| {
        scheme.eq_ignore_ascii_case("https") || scheme.eq_ignore_ascii_case("http")
    })
}

fn read_six_digit_code(prompt: &str) -> Result<String> {
    Input::new()
        .with_prompt(prompt)
        .validate_with(|input: &String| {
            if input.len() == 6 && input.chars().all(char::is_numeric) {
                Ok(())
            } else {
                Err("Code must be 6 digits")
            }
        })
        .interact_text()
        .map_err(|e| Error::InvalidInput(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::can_open_automatically;

    #[test]
    fn automatic_opening_is_limited_to_web_urls() {
        assert!(can_open_automatically("https://accounts.ente.io"));
        assert!(can_open_automatically("HTTP://localhost:3000"));
        assert!(!can_open_automatically("ente-cli://passkey"));
        assert!(!can_open_automatically("file:///etc/hosts"));
    }
}
