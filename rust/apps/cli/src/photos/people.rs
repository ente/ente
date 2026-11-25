use std::{cmp::Reverse, collections::BTreeSet};

use anyhow::{Context, Result, bail, ensure};
use ente_core::Session;
use ente_photos::{
    ml_consent,
    people::{self, Person},
};

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
    let mut since = cursor(db)?.unwrap_or(0);
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
            tx.execute(
                "INSERT INTO photos_people_sync VALUES(1,?1) ON CONFLICT(id) DO UPDATE SET cursor=excluded.cursor",
                [page.cursor],
            )?;
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
    let matches = read(db)?
        .into_iter()
        .filter(|entry| {
            entry.id == selector
                || entry
                    .person
                    .as_ref()
                    .is_ok_and(|person| person.name == selector)
        })
        .collect();
    let entry = select(matches, selector, "person", "Use an ID.", |entry| {
        (
            escape_controls(&entry.id),
            entry
                .person
                .as_ref()
                .map_or_else(|_| "unavailable".to_owned(), |person| person.name.clone()),
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
        .map(|(id, record)| Entry {
            person: Person::from_json(&record).map_err(Into::into),
            id,
        })
        .collect())
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
