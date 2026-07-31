use crate::{
    api::client::USER_AGENT,
    cli::account::{AccountCommand, AccountSubcommands},
    models::{
        account::{Account, AccountSecrets as StoredAccountSecrets, App},
        error::{Error, Result},
    },
    storage::Storage,
};
use dialoguer::{Input, Password, Select};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, AuthenticatedAccount,
    CreateAccountParams, LoginParams, OtpPurpose, SecondFactorMethod, SetupTwoFactorParams,
    TotpPurpose,
};
use ente_core::b64;
use ente_core::crypto::SecretVec;
use ente_core::urls::PRODUCTION_API_ORIGIN;
use std::{path::PathBuf, str::FromStr};
use zeroize::Zeroizing;

pub async fn handle_account_command(cmd: AccountCommand, storage: &Storage) -> Result<()> {
    match cmd.command {
        AccountSubcommands::List => list_accounts(storage).await,
        AccountSubcommands::Add {
            email,
            password,
            app,
            endpoint,
            export_dir,
            otp,
            totp_code,
            second_factor,
        } => {
            add_account(
                storage,
                email,
                password,
                &app,
                endpoint,
                export_dir,
                otp,
                totp_code,
                second_factor,
            )
            .await
        }
        AccountSubcommands::Create {
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
        } => {
            create_account(
                storage,
                email,
                password,
                &app,
                endpoint,
                export_dir,
                otp,
                source,
                setup_2fa,
                totp_code,
                show_recovery_key,
            )
            .await
        }
        AccountSubcommands::Update { email, dir, app } => {
            update_account(storage, &email, &dir, &app).await
        }
        AccountSubcommands::GetToken { email, app } => get_token(storage, &email, &app).await,
        AccountSubcommands::TwoFactor {
            email,
            app,
            totp_code,
            show_recovery_key,
        } => enable_two_factor(storage, &email, &app, totp_code, show_recovery_key).await,
    }
}

struct DialoguerAuthFlowUi {
    email_otp: Option<String>,
    totp_code: Option<String>,
    second_factor: Option<SecondFactorMethod>,
    passkey_presented: bool,
}

impl DialoguerAuthFlowUi {
    fn new(
        email_otp: Option<String>,
        totp_code: Option<String>,
        second_factor: Option<SecondFactorMethod>,
    ) -> Self {
        Self {
            email_otp,
            totp_code,
            second_factor,
            passkey_presented: false,
        }
    }
}

impl AuthFlowUi for DialoguerAuthFlowUi {
    fn read_email_otp(
        &mut self,
        email: &str,
        purpose: OtpPurpose,
        resent: bool,
    ) -> ente_accounts::Result<String> {
        if let Some(code) = self.email_otp.take() {
            return Ok(code);
        }

        let prompt = match (purpose, resent) {
            (OtpPurpose::Signup, false) => {
                format!("Enter the signup verification code sent to {email}")
            }
            (OtpPurpose::Signup, true) => {
                format!("Enter the new signup verification code sent to {email}")
            }
            (OtpPurpose::Login, false) => {
                format!("Enter the email-MFA code sent to {email}")
            }
            (OtpPurpose::Login, true) => {
                format!("Enter the new email-MFA code sent to {email}")
            }
        };

        read_six_digit_code_for_accounts(&prompt)
    }

    fn read_totp_code(&mut self, purpose: TotpPurpose) -> ente_accounts::Result<String> {
        if let Some(code) = self.totp_code.take() {
            return Ok(code);
        }

        let prompt = match purpose {
            TotpPurpose::Login => "Enter TOTP code",
            TotpPurpose::Setup => "Enter the current TOTP from your authenticator app",
        };

        read_six_digit_code_for_accounts(prompt)
    }

    fn report_retryable_error(&mut self, message: &str) -> ente_accounts::Result<()> {
        println!("\n{message}");
        Ok(())
    }

    fn choose_second_factor(
        &mut self,
        methods: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        if let Some(choice) = self.second_factor {
            return Ok(choice);
        }

        let options: Vec<&str> = methods
            .iter()
            .map(|method| match method {
                SecondFactorMethod::Totp => "TOTP (Authenticator app)",
                SecondFactorMethod::Passkey => "Passkey",
            })
            .collect();

        let index = Select::new()
            .with_prompt("Choose verification method")
            .items(&options)
            .default(0)
            .interact()
            .map_err(|e| ente_accounts::Error::InvalidInput(e.to_string()))?;

        methods.get(index).copied().ok_or_else(|| {
            ente_accounts::Error::InvalidInput("Invalid second-factor selection".into())
        })
    }

    fn present_passkey_verification(&mut self, url: &str) -> ente_accounts::Result<()> {
        println!("\nPasskey verification required");
        println!("Open this URL in your browser to verify your passkey:\n{url}");

        if !self.passkey_presented
            && can_open_automatically(url)
            && let Err(error) = open::that(url)
        {
            log::error!("failed to open browser: {error}");
        }
        self.passkey_presented = true;

        Ok(())
    }

    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        let _: String = Input::new()
            .with_prompt("Press Enter once you have completed passkey verification")
            .allow_empty(true)
            .interact_text()
            .map_err(|e| ente_accounts::Error::InvalidInput(e.to_string()))?;
        Ok(())
    }

    fn present_totp_secret(
        &mut self,
        secret_code: &str,
        _qr_code: &str,
    ) -> ente_accounts::Result<()> {
        println!("\nTOTP setup secret: {secret_code}");
        println!("Add this secret to your authenticator app, then enter the current code.");
        Ok(())
    }
}

async fn list_accounts(storage: &Storage) -> Result<()> {
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

#[allow(clippy::too_many_arguments)]
async fn add_account(
    storage: &Storage,
    email_arg: Option<String>,
    password_arg: Option<String>,
    app_arg: &str,
    endpoint: String,
    export_dir_arg: Option<String>,
    otp: Option<String>,
    totp_code: Option<String>,
    second_factor: Option<String>,
) -> Result<()> {
    println!("\n=== Add Existing Ente Account ===\n");

    let email = prompt_email(email_arg)?;
    let interactive_password = password_arg.is_none();
    let mut password = Zeroizing::new(prompt_password(password_arg, "Enter your password")?);
    let app = resolve_app(app_arg)?;
    let second_factor = parse_second_factor(second_factor.as_deref())?;

    if let Ok(Some(_)) = storage.accounts().get(&email, app) {
        println!("\nAccount already exists for {email} with app {app}");
        return Ok(());
    }

    let export_dir = resolve_export_dir(export_dir_arg, &email)?;
    ensure_export_dir(&export_dir)?;

    let client = new_accounts_client(&endpoint, app)?;
    let mut ui = DialoguerAuthFlowUi::new(otp, totp_code, second_factor);
    let mut flow = AuthFlow::new(&client, &mut ui);
    let authenticated = loop {
        match flow
            .login(LoginParams {
                email: email.clone(),
                password: password.clone(),
            })
            .await
        {
            Ok(authenticated) => break authenticated,
            Err(error) if interactive_password && is_retryable_password_error(&error) => {
                println!("\nIncorrect password. Try again.");
                password = Zeroizing::new(prompt_password(None, "Re-enter your password")?);
            }
            Err(error) => return Err(error.into()),
        }
    };

    persist_account(storage, &email, app, &endpoint, &export_dir, authenticated)?;

    println!("\nAccount added successfully!");
    println!("  Email: {email}");
    println!("  App: {app}");
    println!("  Endpoint: {endpoint}");
    println!("  Export directory: {export_dir}");

    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn create_account(
    storage: &Storage,
    email_arg: Option<String>,
    password_arg: Option<String>,
    app_arg: &str,
    endpoint: String,
    export_dir_arg: Option<String>,
    otp: Option<String>,
    source: Option<String>,
    setup_2fa: bool,
    totp_code: Option<String>,
    show_recovery_key: bool,
) -> Result<()> {
    println!("\n=== Create Ente Account ===\n");

    let email = prompt_email(email_arg)?;
    let password = Zeroizing::new(prompt_password(password_arg, "Choose a password")?);
    let app = resolve_app(app_arg)?;

    if let Ok(Some(_)) = storage.accounts().get(&email, app) {
        println!("\nAccount already exists for {email} with app {app}");
        return Ok(());
    }

    let export_dir = resolve_export_dir(export_dir_arg, &email)?;
    ensure_export_dir(&export_dir)?;

    let client = new_accounts_client(&endpoint, app)?;
    let mut ui = DialoguerAuthFlowUi::new(otp, totp_code, Some(SecondFactorMethod::Totp));
    let mut flow = AuthFlow::new(&client, &mut ui);
    let created = flow
        .create_account(CreateAccountParams {
            email: email.clone(),
            password,
            source,
        })
        .await?;

    let AuthenticatedAccount {
        user_id,
        key_attributes,
        secrets,
        recovery_key,
    } = created;

    let two_factor_master_key = secrets.master_key.clone();
    let two_factor_key_attributes = key_attributes.clone();

    persist_account(
        storage,
        &email,
        app,
        &endpoint,
        &export_dir,
        AuthenticatedAccount {
            user_id,
            key_attributes,
            secrets,
            recovery_key: recovery_key.clone(),
        },
    )?;

    println!("\nAccount created successfully!");
    println!("  Email: {email}");
    println!("  App: {app}");
    println!("  Endpoint: {endpoint}");
    println!("  Export directory: {export_dir}");

    if show_recovery_key {
        if let Some(recovery_key) = recovery_key.as_deref() {
            println!("\nRecovery key: {recovery_key}");
        } else {
            println!("\nRecovery key is not available for this account.");
        }
    }

    if setup_2fa {
        let result = flow
            .setup_two_factor(SetupTwoFactorParams {
                master_key: SecretVec::new(two_factor_master_key),
                key_attributes: Some(two_factor_key_attributes),
            })
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

    let mut ui = DialoguerAuthFlowUi::new(None, totp_code, Some(SecondFactorMethod::Totp));
    let mut flow = AuthFlow::new(&client, &mut ui);
    let result = flow
        .setup_two_factor(SetupTwoFactorParams {
            master_key: SecretVec::new(secrets.master_key.clone()),
            key_attributes: None,
        })
        .await?;

    println!("\nTwo-factor authentication enabled for {email}.");
    if show_recovery_key {
        println!("Recovery key: {}", result.recovery_key);
    }

    Ok(())
}

async fn update_account(storage: &Storage, email: &str, dir: &str, app_str: &str) -> Result<()> {
    let app = resolve_app(app_str)?;

    if storage.accounts().get(email, app)?.is_none() {
        return Err(Error::NotFound(format!(
            "Account not found: {} (app: {})",
            email, app
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

async fn get_token(storage: &Storage, email: &str, app_str: &str) -> Result<()> {
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
    authenticated: AuthenticatedAccount,
) -> Result<()> {
    let account = Account {
        user_id: authenticated.user_id,
        email: email.to_string(),
        app,
        endpoint: endpoint.to_string(),
        export_dir: Some(export_dir.to_string()),
    };

    storage.accounts().add(&account)?;
    let stored_secrets = StoredAccountSecrets {
        token: authenticated.secrets.token.clone(),
        master_key: authenticated.secrets.master_key.clone(),
        secret_key: authenticated.secrets.secret_key.clone(),
        public_key: authenticated.secrets.public_key.clone(),
    };
    storage
        .accounts()
        .store_secrets(account.user_id, account.app, &stored_secrets)?;

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

fn is_retryable_password_error(error: &ente_accounts::Error) -> bool {
    matches!(
        error,
        ente_accounts::Error::AuthenticationFailed(message) if message == "Incorrect password"
    ) || error.is_http_status(&[401])
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

fn read_six_digit_code_for_accounts(prompt: &str) -> ente_accounts::Result<String> {
    read_six_digit_code(prompt)
        .map_err(|error| ente_accounts::Error::InvalidInput(error.to_string()))
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
