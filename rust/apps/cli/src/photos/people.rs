use std::{cmp::Reverse, collections::BTreeSet};

use anyhow::{Context, Result, bail, ensure};
use ente_core::Session;
use ente_photos::{
    ml_consent,
    people::{self, Person},
};
use serde_json::{Map, Value};

use crate::{
    args::{ListArgs, Options},
    core_db::{self, Db, OptionalExtension, SqliteResult, params},
    output::{self, PersonView, escape_controls, select},
};

use super::replica::Replica;

pub const SCHEMA: &str = "
    CREATE TABLE photos_people_sync (id INTEGER PRIMARY KEY CHECK(id=1), cursor INTEGER NOT NULL);
    CREATE TABLE photos_people (id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, record TEXT NOT NULL);
";

struct Entry {
    id: String,
    name: Option<String>,
    person: Result<Person>,
}

pub async fn sync(db: &mut Db, session: &Session, options: &Options) -> Result<()> {
    if options.offline {
        ensure!(
            cursor(db)?.is_some(),
            "no local people data; run the command online first"
        );
        return Ok(());
    }
    if !ml_consent::granted(session).await? {
        db.write(|tx| {
            tx.execute("DELETE FROM photos_people", [])?;
            tx.execute("DELETE FROM photos_people_sync", [])?;
            Ok(())
        })?;
        bail!(
            "machine learning is off for this account; turn it on in the Ente Photos app under Settings > Machine learning to see people"
        );
    }
    let synced_before = cursor(db)?;
    let mut since = synced_before.unwrap_or(0);
    loop {
        let page = people::diff(session, since).await?;
        db.write(|tx| {
            let mut delete = tx.prepare_cached("DELETE FROM photos_people WHERE id=?1")?;
            for id in &page.deleted {
                delete.execute([id])?;
            }
            let mut upsert = tx.prepare_cached(
                "INSERT INTO photos_people(id,updated_at,record) VALUES(?1,?2,?3)
                 ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at,record=excluded.record",
            )?;
            for person in &page.updated {
                upsert.execute(params![person.id, person.updated_at, person.data])?;
            }
            if synced_before.is_some() || !page.has_more {
                tx.execute(
                    "INSERT INTO photos_people_sync VALUES(1,?1) ON CONFLICT(id) DO UPDATE SET cursor=excluded.cursor",
                    [page.cursor],
                )?;
            }
            Ok(())
        })?;
        if !page.has_more {
            return Ok(());
        }
        since = page.cursor;
    }
}

pub fn list(
    replica: &Replica<'_>,
    album: Option<i64>,
    mut incomplete: bool,
    args: &ListArgs,
    as_json: bool,
) -> Result<()> {
    let library = replica.file_ids(album)?;
    let mut people = Vec::new();
    for entry in read(replica.db)? {
        match entry.person {
            Ok(person) => {
                let file_count = person
                    .file_ids()
                    .iter()
                    .filter(|id| library.contains(id))
                    .count();
                if file_count > 0 {
                    people.push(PersonView::new(entry.id, person, file_count));
                }
            }
            Err(error) => {
                eprintln!("person {}: {error:#}", escape_controls(&entry.id));
                incomplete = true;
            }
        }
    }
    people.sort_by(|a, b| {
        (Reverse(a.file_count), &a.name, &a.id).cmp(&(Reverse(b.file_count), &b.name, &b.id))
    });
    output::people(people.into_iter(), args, as_json)?;
    ensure!(!incomplete, "person list is incomplete");
    Ok(())
}

pub fn file_ids(db: &Db, selector: &str) -> Result<BTreeSet<i64>> {
    let entries = read(db)?;
    let by_id = entries.iter().any(|entry| entry.id == selector);
    let matches = entries
        .into_iter()
        .filter(|entry| {
            if by_id {
                entry.id == selector
            } else {
                entry.name.as_deref() == Some(selector)
            }
        })
        .collect();
    let entry = select(matches, selector, "person", "Use an ID.", |entry| {
        (
            escape_controls(&entry.id),
            entry
                .name
                .clone()
                .unwrap_or_else(|| "unavailable".to_owned()),
        )
    })?;
    let person = entry
        .person
        .with_context(|| format!("person {}", escape_controls(&entry.id)))?;
    Ok(person.file_ids())
}

fn read(db: &Db) -> Result<Vec<Entry>> {
    let rows: Vec<(String, String)> = db.read(|db| {
        let mut statement = db.prepare("SELECT id,record FROM photos_people ORDER BY id")?;
        Ok(statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
            .collect::<SqliteResult<_>>()?)
    })?;
    Ok(rows
        .into_iter()
        .map(|(id, record)| {
            let person = Person::from_json(&record).map_err(anyhow::Error::from);
            let name = match &person {
                Ok(person) => Some(person.name.clone()),
                Err(_) => recorded_name(&record),
            };
            Entry { id, name, person }
        })
        .collect())
}

fn recorded_name(record: &str) -> Option<String> {
    match serde_json::from_str::<Map<String, Value>>(record)
        .ok()?
        .remove("name")
    {
        None | Some(Value::Null) => Some(String::new()),
        Some(Value::String(name)) => Some(name),
        Some(_) => None,
    }
}

fn cursor(db: &Db) -> core_db::Result<Option<i64>> {
    db.read(|db| {
        Ok(db
            .query_row(
                "SELECT cursor FROM photos_people_sync WHERE id=1",
                [],
                |r| r.get(0),
            )
            .optional()?)
    })
}
