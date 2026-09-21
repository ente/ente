use std::path::Path;

use anyhow::{Context, Result};
use rusqlite::{Connection, OpenFlags};
use zeroize::Zeroizing;

use crate::{core_db::Db, replica, vault::DbKey};

const MIGRATIONS: &[&str] = &[replica::SCHEMA];

pub fn open(account_dir: &Path, key: &DbKey, create: bool) -> Result<Db> {
    let mut flags = OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    if create {
        flags |= OpenFlags::SQLITE_OPEN_CREATE;
    }
    let connection = Connection::open_with_flags(account_dir.join("data.db"), flags)?;
    connection
        .query_row("PRAGMA cipher_version", [], |row| row.get::<_, String>(0))
        .context("this CLI build does not support encrypted databases")?;
    let mut encoded_key = Zeroizing::new(String::from("x'"));
    for byte in &key.0 {
        use std::fmt::Write;
        write!(encoded_key, "{byte:02x}")?;
    }
    encoded_key.push('\'');
    connection.pragma_update(None, "key", encoded_key.as_str())?;
    connection
        .query_row("SELECT count(*) FROM sqlite_master", [], |row| {
            row.get::<_, i64>(0)
        })
        .context("cannot open the encrypted database")?;
    connection.execute_batch(
        "PRAGMA foreign_keys = ON; PRAGMA temp_store = MEMORY; PRAGMA journal_mode = WAL;",
    )?;
    let mut db = Db::new(connection);
    db.migrate(MIGRATIONS)?;
    Ok(db)
}
