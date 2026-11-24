use anyhow::{Context, Result, anyhow, ensure};
use dialoguer::{Confirm, console::Term};
use ente_accounts::{
    Error,
    family::{self, Family, Member, MemberStatus},
};
use ente_core::Session;
use serde_json::json;
use uuid::Uuid;

use crate::{
    api,
    args::{App, FamilyCommand, FamilyMemberCommand, Options},
    output::{self, escape_controls},
    vault::State,
};

pub async fn run(
    command: FamilyCommand,
    selected: Option<&str>,
    app: Option<App>,
    options: &Options,
) -> Result<()> {
    ensure!(
        !options.offline,
        "family plans are not stored locally; this command requires network access"
    );
    if let FamilyCommand::Leave { yes }
    | FamilyCommand::Member {
        command: FamilyMemberCommand::Remove { yes, .. },
    } = &command
    {
        ensure!(
            *yes || options.can_prompt(),
            "this change requires confirmation; supply --yes when running without interactive prompts"
        );
    }
    let state = State::load()?;
    let account = &state.accounts[state.resolve(selected)?];
    let session = api::session(account, account.app(app)?)?;
    match command {
        FamilyCommand::View => {}
        FamilyCommand::Create => family::create(&session)
            .await
            .map_err(|error| match error {
                Error::PaidPlanRequired => anyhow!("a family needs an active paid plan"),
                Error::InAnotherFamily => {
                    anyhow!("this account is a member of another family; leave it first")
                }
                error => error.into(),
            })?,
        FamilyCommand::Leave { yes } => {
            let family = joined(&session).await?;
            let admin = family
                .members
                .iter()
                .find(|member| member.is_admin)
                .context("the family has no admin")?;
            ensure!(
                !admin.email.eq_ignore_ascii_case(&account.email),
                "the family admin cannot leave; remove the members instead"
            );
            confirm(
                &format!("Leave the family of {}?", escape_controls(&admin.email)),
                yes,
            )?;
            family::leave(&session).await?;
            return output::action(options.json, &json!({"left": true}), "Left the family.");
        }
        FamilyCommand::Member { command } => member(command, &session).await?,
    }
    output::family(family::get(&session).await?.as_ref(), options.json)
}

async fn member(command: FamilyMemberCommand, session: &Session) -> Result<()> {
    match command {
        FamilyMemberCommand::Add { email } => {
            family::invite(session, &email)
                .await
                .map_err(|error| match error {
                    Error::NotFamilyAdmin => {
                        anyhow!("only the family admin can invite; start a family with account family create")
                    }
                    Error::PaidPlanRequired => anyhow!("a family needs an active paid plan"),
                    Error::NotRegistered => anyhow!(
                        "{} does not have an Ente account",
                        escape_controls(&email)
                    ),
                    Error::InviteeInFamily => {
                        anyhow!("{} is already in a family", escape_controls(&email))
                    }
                    Error::InviteeHasPaidPlan => anyhow!(
                        "{} has a paid plan; they must cancel it before joining",
                        escape_controls(&email)
                    ),
                    Error::FamilyFull => anyhow!(
                        "the family is full; remove a member or cancel an invite first"
                    ),
                    error => error.into(),
                })
        }
        FamilyMemberCommand::Remove { member, yes } => {
            let family = joined(session).await?;
            let member = find(&family, &member)?;
            let email = escape_controls(&member.email);
            match member.status {
                MemberStatus::Admin => Err(anyhow!("the family admin cannot be removed")),
                MemberStatus::Invited => {
                    confirm(&format!("Cancel the invite for {email}?"), yes)?;
                    family::revoke_invite(session, member.id).await.map_err(admin_only)
                }
                MemberStatus::Accepted => {
                    confirm(&format!("Remove {email} from the family?"), yes)?;
                    family::remove_member(session, member.id)
                        .await
                        .map_err(admin_only)
                }
            }
        }
        FamilyMemberCommand::SetStorage { member, size, .. } => {
            let family = joined(session).await?;
            let member = find(&family, &member)?;
            ensure!(
                member.status == MemberStatus::Accepted,
                "storage limits apply to members who have joined"
            );
            family::set_storage_limit(session, member.id, size)
                .await
                .map_err(|error| match error {
                    Error::StorageLimitAboveFamilyStorage => anyhow!(
                        "the limit exceeds the family storage of {}",
                        output::storage_size(family.total_storage())
                    ),
                    Error::StorageLimitBelowUsage => anyhow!(
                        "{} already uses {}",
                        escape_controls(&member.email),
                        output::storage_size(member.usage)
                    ),
                    error => admin_only(error),
                })
        }
    }
}

async fn joined(session: &Session) -> Result<Family> {
    family::get(session)
        .await?
        .context("this account is not in a family")
}

fn find<'a>(family: &'a Family, selector: &str) -> Result<&'a Member> {
    let id = Uuid::parse_str(selector).ok();
    family
        .members
        .iter()
        .find(|member| Some(member.id) == id || member.email.eq_ignore_ascii_case(selector))
        .with_context(|| format!("no family member matches {selector:?}; run account family view"))
}

fn admin_only(error: Error) -> anyhow::Error {
    match error {
        Error::NotFamilyAdmin => anyhow!("only the family admin can change members"),
        error => error.into(),
    }
}

fn confirm(prompt: &str, yes: bool) -> Result<()> {
    if !yes {
        let accepted = Confirm::new()
            .with_prompt(prompt)
            .default(false)
            .interact_on(&Term::stderr())?;
        ensure!(accepted, "cancelled");
    }
    Ok(())
}
