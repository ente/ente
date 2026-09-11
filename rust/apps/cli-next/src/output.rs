use std::io::Write;

use anyhow::{Context, Result};
use chrono::{DateTime, SecondsFormat};
use dialoguer::console::{Alignment, measure_text_width, pad_str};
use ente_photos::collections::{Collection, Visibility};
use serde::Serialize;
use uuid::Uuid;

use crate::{args::Product, vault::Account};

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
        let updated_at = DateTime::from_timestamp_micros(album.updated_at_micros)
            .context("album timestamp is outside the supported range")?
            .to_rfc3339_opts(SecondsFormat::Micros, true);
        Ok(Self {
            id: album.id.to_string(),
            name: album.name,
            kind: album.kind.name(),
            visibility: match album.visibility {
                Visibility::Visible => "visible",
                Visibility::Archived => "archived",
                Visibility::Hidden => "hidden",
            },
            owner_id: album.owner_id.to_string(),
            updated_at,
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
    )
}

pub fn account(account: &AccountView<'_>) -> Result<()> {
    let fields = [
        ("Name", escape_controls(account.name)),
        ("Email", escape_controls(account.email)),
        ("Host", escape_controls(account.host)),
        ("Logged in", products(account)),
        (
            "Selected",
            if account.selected { "yes" } else { "no" }.to_owned(),
        ),
        ("ID", account.id.clone()),
    ];
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

pub fn albums(albums: &[AlbumView]) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    if albums.is_empty() {
        return writeln!(stdout, "No albums.").map_err(Into::into);
    }
    let rows = albums
        .iter()
        .map(|album| {
            [
                album.id.clone(),
                escape_controls(&album.name),
                album.kind.to_owned(),
                album.visibility.to_owned(),
                album.owner_id.clone(),
                album.updated_at.clone(),
            ]
        })
        .collect::<Vec<_>>();
    write_table(
        &mut stdout,
        ["ID", "NAME", "TYPE", "VISIBILITY", "OWNER", "UPDATED"],
        &rows,
    )
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

fn write_table<const N: usize>(
    out: &mut impl Write,
    header: [&str; N],
    rows: &[[String; N]],
) -> Result<()> {
    let header = header.map(str::to_owned);
    let widths: [usize; N] = std::array::from_fn(|column| {
        std::iter::once(&header)
            .chain(rows)
            .map(|row| measure_text_width(&row[column]))
            .max()
            .unwrap_or(0)
    });
    for row in std::iter::once(&header).chain(rows) {
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
    }
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
