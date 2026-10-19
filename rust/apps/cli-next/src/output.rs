use std::{fmt::Display, io::Write};

use anyhow::{Context, Result, bail};
use chrono::{DateTime, SecondsFormat};
use dialoguer::console::{Alignment, measure_text_width, pad_str};
use ente_accounts::admin::{Subscription, User, UserDetails};
use ente_photos::{
    collections::{Collection, Visibility},
    files::File,
};
use serde::Serialize;
use serde_json::json as json_value;
use uuid::Uuid;

use crate::{
    args::{App, DEFAULT_LIST_LIMIT, ListArgs},
    vault::Account,
};

pub const MAX_CANDIDATES: usize = 10;

#[derive(Serialize)]
pub struct AccountView<'a> {
    id: String,
    name: &'a str,
    email: &'a str,
    host: &'a str,
    apps: Vec<App>,
    selected: bool,
}

impl<'a> AccountView<'a> {
    pub fn new(account: &'a Account, selected: Option<Uuid>) -> Self {
        Self {
            id: account.user_id.to_string(),
            name: &account.name,
            email: &account.email,
            host: &account.origin,
            apps: account.sessions.keys().copied().collect(),
            selected: selected == Some(account.storage_id),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AlbumView {
    id: String,
    name: String,
    #[serde(rename = "type")]
    kind: &'static str,
    visibility: &'static str,
    owner_id: String,
    updated_at: String,
}

impl TryFrom<Collection> for AlbumView {
    type Error = anyhow::Error;

    fn try_from(album: Collection) -> Result<Self> {
        let updated_at = timestamp(album.updated_at_micros)?;
        Ok(Self {
            id: album.id.to_string(),
            name: album.name,
            kind: album.kind.name(),
            visibility: album.visibility.name(),
            owner_id: album.owner_id.to_string(),
            updated_at,
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileView {
    id: String,
    name: String,
    #[serde(rename = "type")]
    kind: &'static str,
    owner_id: String,
    album_ids: Vec<String>,
    created_at: String,
    modified_at: Option<String>,
    updated_at: String,
    location: Option<LocationView>,
    caption: Option<String>,
    hash: Option<String>,
    date_time: Option<String>,
    offset_time: Option<String>,
    duration_seconds: Option<u64>,
    width: Option<u32>,
    height: Option<u32>,
    visibility: Option<&'static str>,
}

#[derive(Serialize)]
struct LocationView {
    latitude: f64,
    longitude: f64,
}

impl FileView {
    pub fn new(file: File, album_ids: &[i64]) -> Result<Self> {
        Ok(Self {
            id: file.id.to_string(),
            name: file.name,
            kind: file.kind.name(),
            owner_id: file.owner_id.to_string(),
            album_ids: album_ids.iter().map(i64::to_string).collect(),
            created_at: timestamp(file.created_at_micros)?,
            modified_at: file.modified_at_micros.map(timestamp).transpose()?,
            updated_at: timestamp(file.updated_at_micros)?,
            location: file.location.as_ref().map(|location| LocationView {
                latitude: location.latitude,
                longitude: location.longitude,
            }),
            caption: file.caption,
            hash: file.hash,
            date_time: file.date_time,
            offset_time: file.offset_time,
            duration_seconds: file.duration_seconds,
            width: file.width,
            height: file.height,
            visibility: file.visibility.map(Visibility::name),
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminUserView {
    id: String,
    email: String,
    created_at: String,
}

impl AdminUserView {
    pub fn new(user: &User) -> Result<Self> {
        Ok(Self {
            id: user.id.to_string(),
            email: user.email.clone(),
            created_at: timestamp(user.created_at)?,
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionView {
    product_id: String,
    pub storage_bytes: i64,
    pub expires_at: String,
}

impl SubscriptionView {
    pub fn new(subscription: &Subscription) -> Result<Self> {
        Ok(Self {
            product_id: subscription.product_id.clone(),
            storage_bytes: subscription.storage,
            expires_at: timestamp(subscription.expiry_time)?,
        })
    }
}

pub fn json(value: &impl Serialize) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    serde_json::to_writer(&mut stdout, value)?;
    writeln!(stdout)?;
    Ok(())
}

pub fn action(as_json: bool, value: &impl Serialize, message: &str) -> Result<()> {
    if as_json {
        json(value)
    } else {
        writeln!(std::io::stdout(), "{message}").map_err(Into::into)
    }
}

pub fn accounts(accounts: &[AccountView<'_>]) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    if accounts.is_empty() {
        return writeln!(stdout, "No accounts on this device.").map_err(Into::into);
    }
    let rows = accounts
        .iter()
        .map(|account| {
            [
                if account.selected { "*" } else { "" }.to_owned(),
                escape_controls(account.name),
                escape_controls(account.email),
                escape_controls(account.host),
                apps(account),
                account.id.clone(),
            ]
        })
        .collect::<Vec<_>>();
    write_table(
        &mut stdout,
        ["SELECTED", "NAME", "EMAIL", "HOST", "LOGGED IN", "ID"],
        &rows,
    )?;
    Ok(())
}

pub fn account(account: &AccountView<'_>) -> Result<()> {
    write_fields(&[
        ("Name", escape_controls(account.name)),
        ("Email", escape_controls(account.email)),
        ("Host", escape_controls(account.host)),
        ("Logged in", apps(account)),
        (
            "Selected",
            if account.selected { "yes" } else { "no" }.to_owned(),
        ),
        ("ID", account.id.clone()),
    ])
}

pub fn albums(
    albums: impl Iterator<Item = Result<AlbumView>>,
    args: &ListArgs,
    as_json: bool,
) -> Result<()> {
    list(
        albums,
        args,
        as_json,
        ["ID", "NAME", "TYPE", "VISIBILITY", "OWNER", "UPDATED"],
        "No albums.",
        |album| {
            [
                album.id,
                escape_controls(&album.name),
                type_label(album.kind).to_owned(),
                album.visibility.to_owned(),
                album.owner_id,
                album.updated_at,
            ]
        },
    )
}

pub fn album(album: &AlbumView) -> Result<()> {
    write_fields(&[
        ("Name", escape_controls(&album.name)),
        ("Type", type_label(album.kind).to_owned()),
        ("Visibility", album.visibility.to_owned()),
        ("Owner", album.owner_id.clone()),
        ("Updated", album.updated_at.clone()),
        ("ID", album.id.clone()),
    ])
}

pub fn files(
    files: impl Iterator<Item = Result<FileView>>,
    args: &ListArgs,
    as_json: bool,
) -> Result<()> {
    list(
        files,
        args,
        as_json,
        ["ID", "NAME", "TYPE", "CREATED", "ALBUMS"],
        "No files.",
        |file| {
            [
                file.id,
                escape_controls(&file.name),
                type_label(file.kind).to_owned(),
                file.created_at,
                file.album_ids.join(","),
            ]
        },
    )
}

pub fn file(file: &FileView) -> Result<()> {
    let mut fields = vec![
        ("Name", escape_controls(&file.name)),
        ("Type", type_label(file.kind).to_owned()),
        (
            "Visibility",
            file.visibility.unwrap_or("unavailable").to_owned(),
        ),
        ("Created", file.created_at.clone()),
        ("Modified", file.modified_at.clone().unwrap_or_default()),
        ("Updated", file.updated_at.clone()),
        ("Owner", file.owner_id.clone()),
        ("Albums", file.album_ids.join(", ")),
        ("ID", file.id.clone()),
    ];
    for (label, value) in [
        ("Caption", file.caption.as_deref().map(escape_controls)),
        (
            "Location",
            file.location
                .as_ref()
                .map(|l| format!("{}, {}", l.latitude, l.longitude)),
        ),
        ("Date/time", file.date_time.as_deref().map(escape_controls)),
        (
            "UTC offset",
            file.offset_time.as_deref().map(escape_controls),
        ),
        ("Duration", file.duration_seconds.map(|s| format!("{s} s"))),
        ("Width", file.width.map(|w| w.to_string())),
        ("Height", file.height.map(|h| h.to_string())),
        ("Hash", file.hash.as_deref().map(escape_controls)),
    ] {
        if let Some(value) = value {
            fields.push((label, value));
        }
    }
    write_fields(&fields)
}

pub fn admin_users(users: Vec<User>, args: &ListArgs, as_json: bool) -> Result<()> {
    list(
        users.iter().map(AdminUserView::new),
        args,
        as_json,
        ["ID", "EMAIL", "CREATED"],
        "No users.",
        |user| [user.id, escape_controls(&user.email), user.created_at],
    )
}

pub fn admin_user(details: &UserDetails, as_json: bool) -> Result<()> {
    let user = AdminUserView::new(&details.user)?;
    let subscription = details
        .subscription
        .as_ref()
        .map(SubscriptionView::new)
        .transpose()?;
    if as_json {
        return json(&json_value!({"id": user.id, "email": user.email,
            "createdAt": user.created_at, "subscription": subscription}));
    }
    let mut fields = vec![
        ("Email", escape_controls(&user.email)),
        ("ID", user.id),
        ("Created", user.created_at),
    ];
    if let Some(subscription) = subscription {
        fields.extend([
            ("Plan", escape_controls(&subscription.product_id)),
            ("Storage", storage_size(subscription.storage_bytes)),
            ("Expires", subscription.expires_at),
        ]);
    } else {
        fields.push(("Subscription", "unavailable".into()));
    }
    write_fields(&fields)
}

pub fn storage_size(bytes: i64) -> String {
    for (unit, divisor) in [
        ("TB", 1024_i64.pow(4)),
        ("GB", 1024_i64.pow(3)),
        ("MB", 1024_i64.pow(2)),
    ] {
        if bytes >= divisor {
            let size = format!("{:.2}", bytes as f64 / divisor as f64);
            return format!(
                "{} {unit} ({bytes} bytes)",
                size.trim_end_matches('0').trim_end_matches('.')
            );
        }
    }
    format!("{bytes} bytes")
}

fn type_label(kind: &str) -> &str {
    match kind {
        "defaultHidden" => "hidden album",
        "quicklink" => "quick link",
        "livephoto" => "live photo",
        _ => kind,
    }
}

fn timestamp(micros: i64) -> Result<String> {
    Ok(DateTime::from_timestamp_micros(micros)
        .context("timestamp is outside the supported range")?
        .to_rfc3339_opts(SecondsFormat::Micros, true))
}

fn apps(account: &AccountView<'_>) -> String {
    let apps = account
        .apps
        .iter()
        .map(|app| app.name())
        .collect::<Vec<_>>()
        .join(",");
    if apps.is_empty() {
        "none".to_owned()
    } else {
        apps
    }
}

fn write_fields(fields: &[(&str, String)]) -> Result<()> {
    let width = fields
        .iter()
        .map(|(name, _)| measure_text_width(name))
        .max()
        .unwrap_or(0);
    let mut stdout = std::io::stdout().lock();
    for (name, value) in fields {
        writeln!(
            stdout,
            "{}  {value}",
            pad_str(name, width, Alignment::Left, None)
        )?;
    }
    Ok(())
}

pub fn select<T, I: Display>(
    mut matches: Vec<T>,
    selector: &str,
    kind: &str,
    hint: &str,
    identity: impl Fn(&T) -> (I, String),
) -> Result<T> {
    if matches.len() > 1 {
        let candidates = matches
            .iter()
            .take(MAX_CANDIDATES)
            .map(|item| {
                let (id, name) = identity(item);
                format!("  {id}  {name:?}")
            })
            .collect::<Vec<_>>()
            .join("\n");
        let more = if matches.len() > MAX_CANDIDATES {
            "\nMore matches omitted."
        } else {
            ""
        };
        bail!("{kind} {selector:?} is ambiguous:\n{candidates}{more}\n{hint}");
    }
    matches
        .pop()
        .with_context(|| format!("no {kind} matches {selector:?}"))
}

pub(crate) fn list<T: Serialize, const N: usize>(
    mut items: impl Iterator<Item = Result<T>>,
    args: &ListArgs,
    as_json: bool,
    header: [&str; N],
    empty: &str,
    row: impl Fn(T) -> [String; N],
) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    let limit = args.limit().map(|limit| limit as usize);
    let values = items.by_ref().take(limit.unwrap_or(usize::MAX));
    if as_json {
        write!(stdout, "[")?;
        for (index, value) in values.enumerate() {
            let value = value?;
            if index > 0 {
                write!(stdout, ",")?;
            }
            serde_json::to_writer(&mut stdout, &value)?;
        }
        writeln!(stdout, "]")?;
    } else {
        let mut rows = values.map(|value| value.map(&row));
        let first = rows
            .by_ref()
            .take(DEFAULT_LIST_LIMIT as usize)
            .collect::<Result<Vec<_>>>()?;
        if first.is_empty() {
            writeln!(stdout, "{empty}")?;
        } else {
            let widths = write_table(&mut stdout, header, &first)?;
            for row in rows {
                write_row(&mut stdout, &row?, &widths)?;
            }
        }
    }
    stdout.flush()?;
    if let Some(limit) = limit
        && items.next().transpose()?.is_some()
    {
        eprintln!("Showing first {limit} results; use --limit N or --all to see more.");
    }
    Ok(())
}

fn write_table<const N: usize>(
    out: &mut impl Write,
    header: [&str; N],
    rows: &[[String; N]],
) -> Result<[usize; N]> {
    let header = header.map(str::to_owned);
    let widths: [usize; N] = std::array::from_fn(|column| {
        std::iter::once(&header)
            .chain(rows)
            .map(|row| measure_text_width(&row[column]))
            .max()
            .unwrap_or(0)
    });
    for row in std::iter::once(&header).chain(rows) {
        write_row(out, row, &widths)?;
    }
    Ok(widths)
}

fn write_row<const N: usize>(
    out: &mut impl Write,
    row: &[String; N],
    widths: &[usize; N],
) -> Result<()> {
    for (column, cell) in row.iter().enumerate() {
        if column > 0 {
            write!(out, "  ")?;
        }
        if column + 1 == N {
            write!(out, "{cell}")?;
        } else {
            write!(
                out,
                "{}",
                pad_str(cell, widths[column], Alignment::Left, None)
            )?;
        }
    }
    writeln!(out)?;
    Ok(())
}

pub(crate) fn escape_controls(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for c in value.chars() {
        if c.is_control() {
            escaped.extend(c.escape_debug());
        } else {
            escaped.push(c);
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use super::{escape_controls, write_table};

    #[test]
    fn human_output_preserves_printable_names() {
        assert_eq!(
            escape_controls("Bob's \"album\"\t\n"),
            "Bob's \"album\"\\t\\n"
        );
    }

    #[test]
    fn human_tables_align_unicode_cells() {
        let mut output = Vec::new();
        write_table(
            &mut output,
            ["NAME", "LOGGED IN"],
            &[
                ["猫".to_owned(), "photos".to_owned()],
                ["longer".to_owned(), "auth".to_owned()],
            ],
        )
        .unwrap();
        assert_eq!(
            String::from_utf8(output).unwrap(),
            "NAME    LOGGED IN\n猫      photos\nlonger  auth\n"
        );
    }
}
