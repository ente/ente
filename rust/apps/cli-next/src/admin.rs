use anyhow::{Context, Result, ensure};
use chrono::{DateTime, Months, NaiveDate, NaiveTime, Utc};
use dialoguer::{Confirm, Input, Select, console::Term};
use ente_accounts::AccountsClient;
use serde_json::json;

use crate::{
    api,
    args::{AdminCommand, AdminEmailCommand, AdminUserCommand, App, Options, SubscriptionArgs},
    output::{self, AdminUserView, SubscriptionView},
    vault::{Account, State},
};

pub async fn run(
    command: AdminCommand,
    selected: Option<&str>,
    app: Option<App>,
    options: &Options,
) -> Result<()> {
    ensure!(!options.offline, "admin commands require network access");
    if let AdminCommand::User { command } = &command {
        let yes = match command {
            AdminUserCommand::Delete { email, yes } => {
                ensure!(email.contains('@'), "supply an email address for deletion");
                Some(*yes)
            }
            AdminUserCommand::DisableTotp(target) | AdminUserCommand::RemovePasskeys(target) => {
                Some(target.yes)
            }
            AdminUserCommand::UpdateSubscription(args) => {
                ensure!(
                    args.no_limit
                        || args.storage.is_some()
                        || args.expires.is_some()
                        || options.can_prompt(),
                    "supply --no-limit, --storage or --expires when running without interactive prompts"
                );
                Some(args.target.yes)
            }
            _ => None,
        };
        if let Some(yes) = yes {
            ensure!(
                yes || options.can_prompt(),
                "this change requires confirmation; supply --yes when running without interactive prompts"
            );
        }
    }
    let state = State::load()?;
    let account = &state.accounts[state.resolve(selected)?];
    let app = account.app(app)?;
    let client = api::accounts_client(&account.origin, app)?;
    client.set_auth_token(Some(ente_core::b64::encode_url_safe(account.token(app)?)));
    execute(command, &client, account, options).await.map_err(|error| {
        if matches!(error.downcast_ref::<ente_accounts::Error>(),
            Some(ente_accounts::Error::Http(ente_core::http::Error::Api { status: 400, message: Some(message), .. }))
                if message == "Token is too old") {
            error.context(format!("administrator login is too old; run account login --account {:?} --app {} and retry", account.name, app.name()))
        } else {
            error
        }
    }).with_context(|| format!("admin action using account {:?} at {}", account.name, account.origin))
}

async fn execute(
    command: AdminCommand,
    client: &AccountsClient,
    account: &Account,
    options: &Options,
) -> Result<()> {
    let command = match command {
        AdminCommand::Email {
            command:
                AdminEmailCommand::Test {
                    to,
                    from,
                    from_name,
                },
        } => {
            client.admin_test_email(&to, &from, &from_name).await?;
            return output::action(
                options.json,
                &json!({"to": to, "accepted": true}),
                &format!(
                    "Test email request accepted for {}.",
                    output::escape_controls(&to)
                ),
            );
        }
        AdminCommand::User { command } => command,
    };
    match command {
        AdminUserCommand::List { list, since } => {
            let users = client.admin_users(since.unwrap_or(0)).await?;
            output::admin_users(users, &list, options.json)
        }
        AdminUserCommand::View { user } => {
            let details = client.admin_user(&user).await?;
            output::admin_user(&details, options.json)
        }
        AdminUserCommand::UpdateSubscription(args) => {
            update_subscription(client, account, args, options).await
        }
        AdminUserCommand::Delete { email, yes } => {
            let target = output::escape_controls(&email);
            confirm(
                "Delete the account currently registered to",
                &target,
                yes,
                account,
            )?;
            let result = client.admin_delete_user(&email).await?;
            output::action(
                options.json,
                &json!({"user": {"id": result.user_id.to_string(), "email": email},
                    "cleanupScheduled": true,
                    "subscriptionCancelled": result.is_subscription_cancelled}),
                &format!(
                    "{target} ({}): Account deleted; data cleanup scheduled. Subscription cancelled: {}.",
                    result.user_id, result.is_subscription_cancelled
                ),
            )
        }
        command => {
            let (target, action) = match &command {
                AdminUserCommand::DisableTotp(target) => (
                    target,
                    "Disable authenticator-code two-factor authentication for",
                ),
                AdminUserCommand::RemovePasskeys(target) => (target, "Remove all passkeys for"),
                _ => unreachable!(),
            };
            let user = client.admin_user(&target.user).await?.user;
            let description = format!("{} ({})", output::escape_controls(&user.email), user.id);
            confirm(action, &description, target.yes, account)?;
            let view = AdminUserView::new(&user)?;
            let (value, message) = match command {
                AdminUserCommand::DisableTotp(_) => {
                    client.admin_disable_totp(user.id).await?;
                    (
                        json!({"user": view, "totpEnabled": false}),
                        "Authenticator-code two-factor authentication disabled.",
                    )
                }
                AdminUserCommand::RemovePasskeys(_) => {
                    client.admin_remove_passkeys(user.id).await?;
                    (json!({"user": view}), "All passkeys removed.")
                }
                _ => unreachable!(),
            };
            output::action(options.json, &value, &format!("{description}: {message}"))
        }
    }
}

async fn update_subscription(
    client: &AccountsClient,
    account: &Account,
    mut args: SubscriptionArgs,
    options: &Options,
) -> Result<()> {
    let mut details = client.admin_user(&args.target.user).await?;
    let subscription = details
        .subscription
        .as_mut()
        .context("server did not return a subscription")?;
    ensure!(
        subscription.product_id == "free",
        "user is not on a free plan"
    );
    if !args.no_limit && args.storage.is_none() && args.expires.is_none() {
        args.no_limit = Select::new()
            .with_prompt("Subscription limits")
            .items(["100 TB and another 100 years", "Custom storage or expiry"])
            .interact_on(&Term::stderr())?
            == 0;
        if !args.no_limit {
            args.storage = prompt_change(
                "Storage (MB/GB/TB; leave empty to keep current)",
                parse_size,
            )?;
            args.expires = prompt_change(
                "Expiry (date or RFC3339; leave empty to keep current)",
                parse_date,
            )?;
            ensure!(
                args.storage.is_some() || args.expires.is_some(),
                "no subscription changes supplied"
            );
        }
    }
    let before = SubscriptionView::new(subscription)?;
    if args.no_limit {
        subscription.storage = 100 * 1024_i64.pow(4);
        subscription.expiry_time = Utc::now()
            .checked_add_months(Months::new(1200))
            .context("expiry is outside the supported range")?
            .timestamp_micros();
    } else {
        if let Some(storage) = args.storage {
            subscription.storage = storage;
        }
        if let Some(expires) = args.expires {
            subscription.expiry_time = expires;
        }
    }
    let after = SubscriptionView::new(subscription)?;
    eprintln!(
        "Storage: {} -> {}\nExpires: {} -> {}",
        output::storage_size(before.storage_bytes),
        output::storage_size(after.storage_bytes),
        before.expires_at,
        after.expires_at
    );
    confirm(
        "Update subscription for",
        &format!(
            "{} ({})",
            output::escape_controls(&details.user.email),
            details.user.id
        ),
        args.target.yes,
        account,
    )?;
    client
        .admin_update_subscription(details.user.id, subscription)
        .await?;
    output::admin_user(&details, options.json)
}

fn confirm(action: &str, target: &str, yes: bool, account: &Account) -> Result<()> {
    if !yes {
        let accepted = Confirm::new()
            .with_prompt(format!(
                "{action} {target} on {} as {} ({})?",
                account.origin,
                output::escape_controls(&account.email),
                account.user_id
            ))
            .default(false)
            .interact_on(&Term::stderr())?;
        ensure!(accepted, "cancelled");
    }
    Ok(())
}

fn prompt_change(label: &str, parse: fn(&str) -> Result<i64, String>) -> Result<Option<i64>> {
    let value: String = Input::new()
        .with_prompt(label)
        .allow_empty(true)
        .validate_with(|value: &String| {
            if value.is_empty() {
                Ok(())
            } else {
                parse(value).map(|_| ())
            }
        })
        .interact_on(&Term::stderr())?;
    if value.is_empty() {
        Ok(None)
    } else {
        parse(&value).map(Some).map_err(anyhow::Error::msg)
    }
}

pub fn parse_size(input: &str) -> Result<i64, String> {
    let input = input.to_ascii_uppercase();
    let (number, multiplier) = [
        ("MB", 1024_i64.pow(2)),
        ("GB", 1024_i64.pow(3)),
        ("TB", 1024_i64.pow(4)),
    ]
    .into_iter()
    .find_map(|(unit, multiplier)| input.strip_suffix(unit).map(|number| (number, multiplier)))
    .ok_or("use a size such as 500GB or 1.5TB (MB/GB/TB use powers of 1024)")?;
    let value = number.parse::<f64>().map_err(|_| "invalid storage size")?;
    let bytes = value * multiplier as f64;
    if !number.chars().all(|c| c.is_ascii_digit() || c == '.')
        || !bytes.is_finite()
        || bytes < 1.0
        || bytes >= i64::MAX as f64
    {
        return Err("storage must be positive and fit in a signed 64-bit byte count".into());
    }
    Ok(bytes as i64)
}

pub fn parse_date(input: &str) -> Result<i64, String> {
    if input.len() == 10
        && let Ok(date) = NaiveDate::parse_from_str(input, "%Y-%m-%d")
    {
        return Ok(date.and_time(NaiveTime::MIN).and_utc().timestamp_micros());
    }
    DateTime::parse_from_rfc3339(input)
        .map(|date| date.timestamp_micros())
        .map_err(|_| "use YYYY-MM-DD (midnight UTC) or RFC3339 with a timezone".into())
}

#[cfg(test)]
mod tests {
    use super::{parse_date, parse_size};

    #[test]
    fn storage_uses_go_units_and_dates_use_utc_or_explicit_offsets() {
        for (input, bytes) in [
            ("5MB", 5242880),
            ("1.5gB", 1610612736),
            ("2Tb", 2199023255552),
        ] {
            assert_eq!(parse_size(input).unwrap(), bytes);
        }
        for input in ["0GB", "-1GB", "1e2GB", "1GiB", "NaNGB", "999999999999TB"] {
            assert!(parse_size(input).is_err(), "{input}");
        }
        for input in [
            "2030-01-01",
            "2030-01-01T00:00:00Z",
            "2030-01-01T05:30:00+05:30",
        ] {
            assert_eq!(parse_date(input).unwrap(), 1893456000000000);
        }
        for input in ["2030-02-30", "2030-01-01 18:00:00", "2030-01-01T18:00:00"] {
            assert!(parse_date(input).is_err(), "{input}");
        }
    }
}
