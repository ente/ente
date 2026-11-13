use crate::db::Connection;

use super::{Error, Result};

pub(super) fn migrate(connection: &mut Connection, scripts: &[&str]) -> Result<()> {
    let target = scripts.len() as i64;
    let transaction = connection.immediate_transaction()?;
    let current: i64 = transaction.pragma_query_value("user_version", |row| Ok(row.get(0)?))?;
    if current > target {
        return Err(Error::Downgrade { current, target });
    }
    if current == target {
        return Ok(());
    }
    for script in &scripts[current as usize..] {
        transaction.execute_batch(script)?;
    }
    transaction.pragma_update("user_version", target)?;
    transaction.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::sync::Barrier;
    use std::thread;

    use crate::db::{self, Connection, Database, OpenOptions};

    use super::migrate;
    use crate::ml_db::{Error, Result};

    const CREATE_ITEMS: &str = "CREATE TABLE items (id INTEGER PRIMARY KEY)";
    const ADD_LABEL: &str = "ALTER TABLE items ADD COLUMN label TEXT NOT NULL DEFAULT 'item'";

    fn open(path: &Path, scripts: &[&str]) -> Result<Database> {
        Database::open(path, OpenOptions::default(), |connection| {
            migrate(connection, scripts)
        })
    }

    #[test]
    fn upgrades_keep_data_and_refuse_downgrades() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("items.db");
        {
            let db = open(&path, &[CREATE_ITEMS]).unwrap();
            db.write(|connection| connection.execute("INSERT INTO items VALUES (7)", ()))
                .unwrap();
        }
        let db = open(&path, &[CREATE_ITEMS, ADD_LABEL]).unwrap();
        let (version, label): (i64, String) = db
            .read(|connection| {
                Ok((
                    connection.pragma_query_value("user_version", |row| Ok(row.get(0)?))?,
                    connection.query_row("SELECT label FROM items WHERE id = 7", (), |row| {
                        Ok(row.get(0)?)
                    })?,
                ))
            })
            .unwrap();
        assert_eq!(version, 2);
        assert_eq!(label, "item");
        assert!(matches!(
            open(&path, &[CREATE_ITEMS]),
            Err(Error::Downgrade {
                current: 2,
                target: 1
            })
        ));
    }

    #[test]
    fn failed_migration_keeps_previous_schema_and_version() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("items.db");
        {
            let db = open(&path, &[CREATE_ITEMS]).unwrap();
            db.write(|connection| connection.execute("INSERT INTO items VALUES (7)", ()))
                .unwrap();
        }
        assert!(
            open(
                &path,
                &[
                    CREATE_ITEMS,
                    ADD_LABEL,
                    "INSERT INTO missing_table VALUES (1)"
                ]
            )
            .is_err()
        );
        {
            let connection = Connection::open(&path).unwrap();
            let version: i64 = connection
                .pragma_query_value("user_version", |row| Ok(row.get(0)?))
                .unwrap();
            let columns = connection
                .prepare_cached("SELECT name FROM pragma_table_info('items')")
                .unwrap()
                .query_map((), |row| Ok(row.get::<_, String>(0)?))
                .unwrap()
                .collect::<db::Result<Vec<_>>>()
                .unwrap();
            assert_eq!(version, 1);
            assert_eq!(columns, ["id"]);
        }
        let db = open(&path, &[CREATE_ITEMS, ADD_LABEL]).unwrap();
        assert_eq!(
            db.read(|connection| connection
                .query_row("SELECT id FROM items", (), |row| Ok(row.get::<_, i64>(0)?)))
                .unwrap(),
            7
        );
    }

    #[test]
    fn concurrent_open_applies_each_migration_once() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("items.db");
        drop(open(&path, &[CREATE_ITEMS]).unwrap());
        let barrier = Barrier::new(2);
        thread::scope(|scope| {
            for _ in 0..2 {
                let path = &path;
                let barrier = &barrier;
                scope.spawn(move || {
                    barrier.wait();
                    let db = open(path, &[CREATE_ITEMS, ADD_LABEL]).unwrap();
                    let version = db
                        .read(|connection| {
                            connection
                                .pragma_query_value("user_version", |row| Ok(row.get::<_, i64>(0)?))
                        })
                        .unwrap();
                    assert_eq!(version, 2);
                });
            }
        });
    }
}
