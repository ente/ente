use std::io::Write;

use anyhow::{Context, Result};
use chrono::{DateTime, SecondsFormat};
use dialoguer::console::{Alignment, measure_text_width, pad_str};
use ente_photos::{collections::Collection, files::File};
use serde::Serialize;
use uuid::Uuid;

use crate::{
    args::{DEFAULT_LIST_LIMIT, ListArgs, Product},
    vault::Account,
};

#[derive(Serialize)]
pub struct AccountView<'a> {
    id: String,
    name: &'a str,
    email: &'a str,
    host: &'a str,
    products: Vec<Product>,
    selected: bool,
}

impl<'a> AccountView<'a> {
    pub fn new(account: &'a Account, selected: Option<Uuid>) -> Self {
        Self {
            id: account.user_id.to_string(),
            name: &account.name,
            email: &account.email,
            host: &account.origin,
            products: account.sessions.keys().copied().collect(),
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
    modified_at: String,
    updated_at: String,
    location: Option<LocationView>,
    caption: Option<String>,
    hash: Option<String>,
    date_time: Option<String>,
    offset_time: Option<String>,
    duration_seconds: Option<u64>,
    width: Option<u32>,
    height: Option<u32>,
    visibility: &'static str,
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
            modified_at: timestamp(file.modified_at_micros)?,
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
            visibility: file.visibility.name(),
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
                products(account),
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
        ("Logged in", products(account)),
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
                album.kind.to_owned(),
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
        ("Type", album.kind.to_owned()),
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
                file.kind.to_owned(),
                file.created_at,
                file.album_ids.join(","),
            ]
        },
    )
}

pub fn file(file: &FileView) -> Result<()> {
    let mut fields = vec![
        ("Name", escape_controls(&file.name)),
        ("Type", file.kind.to_owned()),
        ("Visibility", file.visibility.to_owned()),
        ("Created", file.created_at.clone()),
        ("Modified", file.modified_at.clone()),
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

fn timestamp(micros: i64) -> Result<String> {
    Ok(DateTime::from_timestamp_micros(micros)
        .context("timestamp is outside the supported range")?
        .to_rfc3339_opts(SecondsFormat::Micros, true))
}

fn products(account: &AccountView<'_>) -> String {
    let products = account
        .products
        .iter()
        .map(|product| product.name())
        .collect::<Vec<_>>()
        .join(",");
    if products.is_empty() {
        "none".to_owned()
    } else {
        products
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

fn list<T: Serialize, const N: usize>(
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

fn escape_controls(value: &str) -> String {
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
