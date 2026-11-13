use std::io::Write;

use anyhow::{Context, Result, ensure};
use chrono::{DateTime, SecondsFormat, Utc};
use ente_auth::code::Code;
use serde::Serialize;
use uuid::Uuid;

use super::replica;
use crate::{
    api,
    args::{App, CodeCommand, Options},
    db, home, output,
};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Summary {
    id: String,
    name: String,
    issuer: String,
    account_name: String,
    #[serde(rename = "type")]
    kind: &'static str,
}

impl Summary {
    fn new(id: String, code: &Code) -> Self {
        Self {
            id,
            name: code.name(),
            issuer: code.issuer.clone(),
            account_name: code.account_name.clone(),
            kind: code.kind.as_str(),
        }
    }
}

#[derive(Default)]
struct Failures {
    count: usize,
    ids: Vec<String>,
}

impl Failures {
    fn record(&mut self, id: String) {
        self.count += 1;
        if self.ids.len() < 10 {
            self.ids.push(id);
        }
    }

    fn check(&self) -> Result<()> {
        ensure!(
            self.count == 0,
            "{} unreadable Auth code{} (IDs: {})",
            self.count,
            if self.count == 1 { "" } else { "s" },
            self.ids.join(", ")
        );
        Ok(())
    }
}

pub async fn run(command: CodeCommand, selected: Option<&str>, options: &Options) -> Result<()> {
    let found = {
        let (account, home) = home::open_account(selected, !options.offline)?;
        let session = api::session(&account, App::Auth)?;
        let mut db = db::open(&home.path, &account.db_key, !options.offline)?;
        if !options.offline {
            replica::refresh(&mut db, &session).await?;
        }
        let query = match &command {
            CodeCommand::List { search, .. } => search.as_deref(),
            CodeCommand::View { code } => Some(code.as_str()),
        };
        let id = query.and_then(|query| Uuid::parse_str(query).ok());
        let mut failures = Failures::default();
        replica::read(&db, &session, id, |records| {
            let codes = records.filter_map(|record| {
                let (code_id, record) = match record {
                    Ok(record) => record,
                    Err(error) => return Some(Err(error)),
                };
                let Ok(code) = record.and_then(|line| Code::from_uri(&line)) else {
                    failures.record(code_id);
                    return None;
                };
                if code.trashed {
                    return if id.is_some() && matches!(command, CodeCommand::View { .. }) {
                        Some(Err(anyhow::anyhow!(
                            "code {code_id} is in Trash; restore it in Ente Auth"
                        )))
                    } else {
                        None
                    };
                }
                (id.is_some() || query.is_none_or(|query| code.matches(query)))
                    .then_some(Ok((code_id, code)))
            });
            match &command {
                CodeCommand::List { list, .. } => {
                    output::list(
                        codes.map(|row| row.map(|(id, code)| Summary::new(id, &code))),
                        list,
                        options.json,
                        ["ID", "NAME", "TYPE"],
                        "No codes.",
                        |code| {
                            [
                                code.id,
                                output::escape_controls(&code.name),
                                code.kind.into(),
                            ]
                        },
                    )?;
                    failures.check().context("Auth code list is incomplete")?;
                    Ok(None)
                }
                CodeCommand::View { code: selector } => {
                    let candidates = codes
                        .take(output::MAX_CANDIDATES + 1)
                        .collect::<Result<Vec<_>>>()?;
                    failures.check().with_context(|| {
                        if id.is_some() {
                            format!("cannot read code {selector:?}")
                        } else {
                            format!("cannot resolve code {selector:?}; select a known code ID")
                        }
                    })?;
                    output::select(
                        candidates,
                        selector,
                        "code",
                        "Narrow the search or use an ID.",
                        |(id, code)| (id.clone(), code.name()),
                    )
                    .map(Some)
                }
            }
        })?
    };
    let Some((id, code)) = found else {
        return Ok(());
    };
    let time =
        u64::try_from(Utc::now().timestamp()).context("system clock is before the Unix epoch")?;
    let (otp, valid_until) = code
        .generate(time)
        .with_context(|| format!("cannot generate code {id}"))?;
    let valid_until = DateTime::from_timestamp(i64::try_from(valid_until)?, 0)
        .context("code expiry is outside the supported range")?
        .to_rfc3339_opts(SecondsFormat::Secs, true);
    if options.json {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct View {
            #[serde(flatten)]
            code: Summary,
            otp: String,
            valid_until: String,
        }
        output::json(&View {
            code: Summary::new(id, &code),
            otp,
            valid_until,
        })
    } else {
        writeln!(
            std::io::stdout(),
            "{}\n{otp}\nValid until {valid_until}",
            output::escape_controls(&code.name())
        )
        .map_err(Into::into)
    }
}
