use std::collections::HashMap;
use std::hash::Hash;
use std::num::NonZeroUsize;
use std::ops::{Deref, DerefMut};
use std::path::Path;
use std::sync::{Condvar, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use rusqlite::{OpenFlags, TransactionBehavior, types::FromSql};

pub use rusqlite::types;
pub use rusqlite::{
    Error as SqliteError, OptionalExtension, Params, Result as SqliteResult, Row, ToSql,
    Transaction, params_from_iter,
};

const WRITER_PRAGMAS: &str = "PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA journal_size_limit = 6291456;";
const BUSY_TIMEOUT: Duration = Duration::from_secs(30);
pub(crate) const MAX_SQL_BIND_PARAMS_PER_QUERY: usize = 10000;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Sqlite(#[from] SqliteError),
    #[error("currentVersion({current}) cannot be greater than toVersion({target})")]
    Downgrade { current: i64, target: i64 },
    #[error("reader_count must be at least 1")]
    InvalidReaderCount,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Clone, Copy, Debug)]
pub struct OpenOptions {
    pub reader_count: usize,
}

impl Default for OpenOptions {
    fn default() -> Self {
        Self { reader_count: 1 }
    }
}

pub struct Connection(rusqlite::Connection);

impl Connection {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let connection = rusqlite::Connection::open(path)?;
        connection.busy_timeout(BUSY_TIMEOUT)?;
        connection.execute_batch(WRITER_PRAGMAS)?;
        Ok(Self(connection))
    }

    pub fn open_read_only(path: impl AsRef<Path>) -> Result<Self> {
        let flags = OpenFlags::SQLITE_OPEN_READ_ONLY
            | OpenFlags::SQLITE_OPEN_URI
            | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let connection = rusqlite::Connection::open_with_flags(path, flags)?;
        connection.busy_timeout(BUSY_TIMEOUT)?;
        Ok(Self(connection))
    }

    pub fn open_in_memory() -> Result<Self> {
        Ok(Self(rusqlite::Connection::open_in_memory()?))
    }
}

impl Deref for Connection {
    type Target = rusqlite::Connection;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Connection {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

pub struct Database {
    pool: Pool,
}

impl Database {
    pub fn open(path: impl AsRef<Path>, migration_scripts: &[&str]) -> Result<Self> {
        Self::open_with_options(path, migration_scripts, OpenOptions::default())
    }

    pub fn open_with_options(
        path: impl AsRef<Path>,
        migration_scripts: &[&str],
        options: OpenOptions,
    ) -> Result<Self> {
        if options.reader_count == 0 {
            return Err(Error::InvalidReaderCount);
        }
        let path = path.as_ref();
        let mut writer = Connection::open(path)?;
        migrate(&mut writer, migration_scripts)?;
        let readers = (0..options.reader_count)
            .map(|_| Connection::open_read_only(path))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self {
            pool: Pool::new(writer, readers),
        })
    }

    pub fn read_all<C: FromIterator<T>, T, P: Params>(
        &self,
        sql: &str,
        parameters: P,
        map: impl FnMut(&Row<'_>) -> SqliteResult<T>,
    ) -> Result<C> {
        self.pool.read(|connection| {
            let mut statement = connection.prepare_cached(sql)?;
            let rows = statement.query_map(parameters, map)?;
            Ok(rows.collect::<SqliteResult<C>>()?)
        })
    }

    pub fn read_column<C: FromIterator<T>, T: FromSql, P: Params>(
        &self,
        sql: &str,
        parameters: P,
    ) -> Result<C> {
        self.read_all(sql, parameters, |row| row.get(0))
    }

    pub fn read_grouped<K: FromSql + Eq + Hash, V: FromSql, C: FromIterator<V>, P: Params>(
        &self,
        sql: &str,
        parameters: P,
    ) -> Result<HashMap<K, C>> {
        let rows: Vec<(K, V)> = self.read_all(sql, parameters, pair)?;
        Ok(group_into(rows))
    }

    pub fn read_value<T: FromSql>(&self, sql: &str, parameters: impl Params) -> Result<T> {
        self.pool.read(|connection| {
            Ok(connection
                .prepare_cached(sql)?
                .query_row(parameters, |row| row.get(0))?)
        })
    }

    pub fn read_optional<T: FromSql>(
        &self,
        sql: &str,
        parameters: impl Params,
    ) -> Result<Option<T>> {
        self.pool.read(|connection| {
            Ok(connection
                .prepare_cached(sql)?
                .query_row(parameters, |row| row.get(0))
                .optional()?)
        })
    }

    pub fn read_chunked_in<C: FromIterator<T>, T, I: ToSql>(
        &self,
        sql: &str,
        ids: &[I],
        chunk_size: NonZeroUsize,
        mut map: impl FnMut(&Row<'_>) -> SqliteResult<T>,
    ) -> Result<C> {
        let mut rows = Vec::new();
        for chunk in ids.chunks(chunk_size.get()) {
            let sql = expand_in_clause(sql, chunk.len());
            let chunk_rows: Vec<T> = self.read_all(&sql, params_from_iter(chunk), &mut map)?;
            rows.extend(chunk_rows);
        }
        Ok(rows.into_iter().collect())
    }

    pub fn read_transaction<T>(
        &self,
        read: impl FnOnce(&Transaction<'_>) -> Result<T>,
    ) -> Result<T> {
        self.pool.read(|connection| {
            let transaction =
                connection.transaction_with_behavior(TransactionBehavior::Deferred)?;
            let result = read(&transaction)?;
            transaction.commit()?;
            Ok(result)
        })
    }

    pub fn write_transaction<T>(
        &self,
        write: impl FnOnce(&Transaction<'_>) -> Result<T>,
    ) -> Result<T> {
        self.pool.write(|connection| {
            let transaction =
                connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
            let result = write(&transaction)?;
            transaction.commit()?;
            Ok(result)
        })
    }

    pub fn execute(&self, sql: &str, parameters: impl Params) -> Result<usize> {
        self.pool
            .write(|connection| Ok(connection.prepare_cached(sql)?.execute(parameters)?))
    }

    pub fn execute_chunked_in<I: ToSql>(&self, sql: &str, ids: &[I]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        self.write_transaction(|transaction| {
            for chunk in ids.chunks(MAX_SQL_BIND_PARAMS_PER_QUERY) {
                let sql = expand_in_clause(sql, chunk.len());
                transaction.execute(&sql, params_from_iter(chunk))?;
            }
            Ok(())
        })
    }

    pub fn execute_statements<'a>(
        &self,
        statements: impl IntoIterator<Item = &'a str>,
    ) -> Result<()> {
        self.write_transaction(|transaction| {
            for statement in statements {
                transaction.execute_batch(statement)?;
            }
            Ok(())
        })
    }

    pub fn write_batch_atomic<P: Params>(
        &self,
        sql: &str,
        parameter_sets: impl IntoIterator<Item = P>,
    ) -> Result<()> {
        self.write_transaction(|transaction| {
            let mut statement = transaction.prepare_cached(sql)?;
            for parameters in parameter_sets {
                statement.execute(parameters)?;
            }
            Ok(())
        })
    }

    pub fn write_batches_committing_each<P: Params>(
        &self,
        sql: &str,
        batch_size: NonZeroUsize,
        parameter_sets: impl IntoIterator<Item = P>,
    ) -> Result<()> {
        self.pool.write(|connection| {
            let mut parameter_sets = parameter_sets.into_iter().peekable();
            while parameter_sets.peek().is_some() {
                let transaction =
                    connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
                {
                    let mut statement = transaction.prepare_cached(sql)?;
                    for parameters in parameter_sets.by_ref().take(batch_size.get()) {
                        statement.execute(parameters)?;
                    }
                }
                transaction.commit()?;
            }
            Ok(())
        })
    }
}

struct Pool {
    writer: Mutex<Connection>,
    readers: Mutex<Vec<Connection>>,
    reader_available: Condvar,
}

impl Pool {
    fn new(writer: Connection, readers: Vec<Connection>) -> Self {
        Self {
            writer: Mutex::new(writer),
            readers: Mutex::new(readers),
            reader_available: Condvar::new(),
        }
    }

    fn acquire_reader(&self) -> Reader<'_> {
        let mut readers = lock(&self.readers);
        loop {
            if let Some(connection) = readers.pop() {
                return Reader {
                    pool: self,
                    connection: Some(connection),
                };
            }
            readers = self
                .reader_available
                .wait(readers)
                .unwrap_or_else(PoisonError::into_inner);
        }
    }

    fn read<T>(&self, query: impl FnOnce(&mut Connection) -> Result<T>) -> Result<T> {
        let mut reader = self.acquire_reader();
        #[expect(
            clippy::expect_used,
            reason = "acquire_reader returns a guard owning a connection"
        )]
        query(
            reader
                .connection
                .as_mut()
                .expect("acquired reader owns a connection"),
        )
    }

    fn write<T>(&self, statement: impl FnOnce(&mut Connection) -> Result<T>) -> Result<T> {
        statement(&mut lock(&self.writer))
    }
}

struct Reader<'a> {
    pool: &'a Pool,
    connection: Option<Connection>,
}

impl Drop for Reader<'_> {
    fn drop(&mut self) {
        if let Some(connection) = self.connection.take() {
            lock(&self.pool.readers).push(connection);
            self.pool.reader_available.notify_one();
        }
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn migrate(connection: &mut Connection, scripts: &[&str]) -> Result<()> {
    let target = scripts.len() as i64;
    let probed: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    check_not_downgrade(probed, target)?;
    if probed == target {
        return Ok(());
    }

    let transaction = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let current: i64 = transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
    check_not_downgrade(current, target)?;
    if current == target {
        return Ok(());
    }
    for script in &scripts[current as usize..] {
        transaction.execute_batch(script)?;
    }
    transaction.pragma_update(None, "user_version", target)?;
    transaction.commit()?;
    Ok(())
}

fn check_not_downgrade(current: i64, target: i64) -> Result<()> {
    if current > target {
        return Err(Error::Downgrade { current, target });
    }
    Ok(())
}

pub fn bind_placeholders(count: usize) -> String {
    vec!["?"; count].join(", ")
}

fn expand_in_clause(sql: &str, count: usize) -> String {
    sql.replacen("{}", &bind_placeholders(count), 1)
}

pub(crate) fn pair<A: types::FromSql, B: types::FromSql>(row: &Row<'_>) -> SqliteResult<(A, B)> {
    Ok((row.get(0)?, row.get(1)?))
}

pub(crate) fn optional_parameter(value: &Option<impl ToSql>) -> Vec<&dyn ToSql> {
    value.iter().map(|value| value as &dyn ToSql).collect()
}

pub(crate) fn group_into<K: Eq + Hash, V, C: FromIterator<V>>(
    rows: impl IntoIterator<Item = (K, V)>,
) -> HashMap<K, C> {
    let mut groups: HashMap<K, Vec<V>> = HashMap::new();
    for (key, value) in rows {
        groups.entry(key).or_default().push(value);
    }
    groups
        .into_iter()
        .map(|(key, values)| (key, values.into_iter().collect()))
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};
    use std::num::NonZeroUsize;
    use std::panic::{AssertUnwindSafe, catch_unwind};
    use std::sync::mpsc::{self, RecvTimeoutError};
    use std::thread;
    use std::time::Duration;

    use super::{
        Connection, Database, Error, MAX_SQL_BIND_PARAMS_PER_QUERY, OpenOptions, bind_placeholders,
        lock, types,
    };

    const CREATE_ITEMS: &str = "CREATE TABLE items (id INTEGER PRIMARY KEY)";
    const ADD_LABEL: &str = "ALTER TABLE items ADD COLUMN label TEXT NOT NULL DEFAULT 'item'";

    fn open() -> (tempfile::TempDir, Database) {
        let directory = tempfile::tempdir().unwrap();
        let db = Database::open(directory.path().join("items.db"), &[CREATE_ITEMS]).unwrap();
        (directory, db)
    }

    fn pragma<T: types::FromSql>(connection: &Connection, name: &str) -> T {
        connection
            .pragma_query_value(None, name, |row| row.get(0))
            .unwrap()
    }

    #[test]
    fn open_applies_connection_pragmas() {
        let directory = tempfile::tempdir().unwrap();
        let connection = Connection::open(directory.path().join("test.db")).unwrap();
        assert_eq!(pragma::<String>(&connection, "journal_mode"), "wal");
        assert_eq!(pragma::<i64>(&connection, "synchronous"), 1);
        assert_eq!(pragma::<i64>(&connection, "journal_size_limit"), 6291456);
        assert_eq!(pragma::<i64>(&connection, "busy_timeout"), 30000);
    }

    #[test]
    fn read_only_connection_reads_wal_without_changing_writer_settings() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("test.db");
        let writer = Connection::open(&path).unwrap();
        writer
            .execute_batch("CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (7);")
            .unwrap();
        let reader = Connection::open_read_only(&path).unwrap();
        let id: i64 = reader
            .query_row("SELECT id FROM t", (), |row| row.get(0))
            .unwrap();
        assert_eq!(id, 7);
        assert!(reader.execute("INSERT INTO t VALUES (8)", ()).is_err());
        assert_eq!(pragma::<String>(&reader, "journal_mode"), "wal");
        assert_eq!(pragma::<i64>(&reader, "busy_timeout"), 30000);
        assert_eq!(pragma::<i64>(&writer, "synchronous"), 1);
        assert_eq!(pragma::<i64>(&writer, "journal_size_limit"), 6291456);
    }

    #[test]
    fn read_only_connection_does_not_create_database() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("missing.db");
        assert!(Connection::open_read_only(&path).is_err());
        assert!(!path.exists());
    }

    #[test]
    fn in_memory_connection_runs_statements() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch("CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (7);")
            .unwrap();
        let id: i64 = connection
            .query_row("SELECT id FROM t", (), |row| row.get(0))
            .unwrap();
        assert_eq!(id, 7);
    }

    #[test]
    fn reader_queries_reject_writes() {
        let (_directory, db) = open();
        db.execute("INSERT INTO items (id) VALUES (?)", [7])
            .unwrap();
        let deleted: Result<Vec<i64>, _> = db.read_column("DELETE FROM items RETURNING id", ());
        assert!(matches!(deleted, Err(Error::Sqlite(_))));
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items", ())
                .unwrap(),
            [7]
        );
    }

    #[test]
    fn failed_batch_rolls_back_and_writer_recovers() {
        let (_directory, db) = open();
        assert!(
            db.write_batch_atomic("INSERT INTO items (id) VALUES (?)", [[1], [2], [1]])
                .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
        assert_eq!(
            db.execute("INSERT INTO items (id) VALUES (?)", [3])
                .unwrap(),
            1
        );
        assert_eq!(
            db.execute("DELETE FROM items WHERE id = ?", [4]).unwrap(),
            0
        );
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items", ())
                .unwrap(),
            [3]
        );
    }

    #[test]
    fn write_transactions_commit_or_rollback_and_writer_recovers() {
        let (_directory, db) = open();
        let result = db.write_transaction(|transaction| {
            transaction.execute("INSERT INTO items VALUES (?)", [1])?;
            transaction.execute("INSERT INTO missing_table VALUES (?)", [2])?;
            Ok(())
        });
        assert!(result.is_err());
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );

        assert!(
            catch_unwind(AssertUnwindSafe(|| {
                let _: super::Result<()> = db.write_transaction(|transaction| {
                    transaction.execute("INSERT INTO items VALUES (?)", [3])?;
                    panic!("transaction callback failed");
                });
            }))
            .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
        let total = db
            .write_transaction(|transaction| {
                transaction.execute("INSERT INTO items VALUES (?)", [1])?;
                transaction.execute("INSERT INTO items VALUES (?)", [2])?;
                Ok(transaction
                    .query_row("SELECT SUM(id) FROM items", (), |row| row.get::<_, i64>(0))?)
            })
            .unwrap();
        assert_eq!(total, 3);
        assert_eq!(
            db.read_value::<i64>("SELECT SUM(id) FROM items", ())
                .unwrap(),
            3
        );
    }

    #[test]
    fn read_transaction_keeps_a_snapshot_and_rejects_writes() {
        let (_directory, db) = open();
        db.execute("INSERT INTO items VALUES (?)", [1]).unwrap();
        let counts = db
            .read_transaction(|transaction| {
                let before: i64 =
                    transaction.query_row("SELECT COUNT(*) FROM items", (), |row| row.get(0))?;
                db.execute("INSERT INTO items VALUES (?)", [2])?;
                let after: i64 =
                    transaction.query_row("SELECT COUNT(*) FROM items", (), |row| row.get(0))?;
                assert!(
                    transaction
                        .execute("INSERT INTO items VALUES (?)", [3])
                        .is_err()
                );
                Ok((before, after))
            })
            .unwrap();
        assert_eq!(counts, (1, 1));
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            2
        );
    }

    #[test]
    fn statement_sequence_rolls_back_if_a_later_statement_fails() {
        let (_directory, db) = open();
        assert!(
            db.execute_statements([
                "INSERT INTO items VALUES (1)",
                "INSERT INTO missing_table VALUES (2)",
            ])
            .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
    }

    #[test]
    fn zero_readers_is_rejected_before_creating_a_database() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("items.db");
        assert!(matches!(
            Database::open_with_options(&path, &[CREATE_ITEMS], OpenOptions { reader_count: 0 }),
            Err(Error::InvalidReaderCount)
        ));
        assert!(!path.exists());
    }

    #[test]
    fn configured_readers_bound_concurrency_and_wake_on_any_returned_connection() {
        for reader_count in [1, 2, 3] {
            let directory = tempfile::tempdir().unwrap();
            let path = directory.path().join("items.db");
            let db = if reader_count == 1 {
                Database::open(path, &[CREATE_ITEMS])
            } else {
                Database::open_with_options(path, &[CREATE_ITEMS], OpenOptions { reader_count })
            }
            .unwrap();

            thread::scope(|scope| {
                let mut release_readers = Vec::new();
                for _ in 0..reader_count {
                    let (entered_tx, entered_rx) = mpsc::channel();
                    let (release_tx, release_rx) = mpsc::channel();
                    release_readers.push(release_tx);
                    let db = &db;
                    scope.spawn(move || {
                        db.read_transaction(|transaction| {
                            transaction.query_row("SELECT 1", (), |_| Ok(()))?;
                            entered_tx.send(()).unwrap();
                            release_rx.recv().unwrap();
                            Ok(())
                        })
                        .unwrap();
                    });
                    entered_rx.recv_timeout(Duration::from_secs(5)).unwrap();
                }

                let (result_tx, result_rx) = mpsc::channel();
                let db = &db;
                scope.spawn(move || {
                    result_tx
                        .send(db.read_value::<i64>("SELECT 7", ()))
                        .unwrap();
                });
                let was_blocked = matches!(
                    result_rx.recv_timeout(Duration::from_millis(100)),
                    Err(RecvTimeoutError::Timeout)
                );
                release_readers.pop().unwrap().send(()).unwrap();
                let result = result_rx.recv_timeout(Duration::from_secs(5));
                for release in release_readers {
                    release.send(()).unwrap();
                }
                assert!(was_blocked);
                assert_eq!(result.unwrap().unwrap(), 7);
            });
        }
    }

    #[test]
    fn reader_returns_to_pool_after_a_callback_panics() {
        let (_directory, db) = open();
        assert!(
            catch_unwind(AssertUnwindSafe(|| {
                let _: super::Result<()> = db.read_transaction(|transaction| {
                    transaction.query_row("SELECT 1", (), |_| Ok(()))?;
                    panic!("reader callback failed");
                });
            }))
            .is_err()
        );
        assert_eq!(lock(&db.pool.readers).len(), 1);
        assert_eq!(db.read_value::<i64>("SELECT 7", ()).unwrap(), 7);
    }

    #[test]
    fn chunked_delete_handles_empty_lists_and_rolls_back_on_failure() {
        let (_directory, db) = open();
        let ids: Vec<i64> = (0..10_001).collect();
        db.write_batch_atomic(
            "INSERT INTO items (id) VALUES (?)",
            ids.iter().map(|id| [id]),
        )
        .unwrap();
        db.execute_chunked_in::<i64>("DELETE FROM items WHERE id IN ({})", &[])
            .unwrap();
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            10_001
        );
        db.execute_statements(["CREATE TRIGGER reject_last_delete BEFORE DELETE ON items
             WHEN OLD.id = 10000 BEGIN SELECT RAISE(ABORT, 'cannot delete'); END"])
            .unwrap();
        assert!(
            db.execute_chunked_in("DELETE FROM items WHERE id IN ({})", &ids)
                .is_err()
        );
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            10_001
        );
        db.execute_statements(["DROP TRIGGER reject_last_delete"])
            .unwrap();
        db.execute_chunked_in("DELETE FROM items WHERE id IN ({})", &ids)
            .unwrap();
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            0
        );
    }

    #[test]
    fn batched_writes_commit_each_completed_batch() {
        let (_directory, db) = open();
        db.write_batches_committing_each(
            "INSERT INTO missing_table VALUES (?)",
            const { NonZeroUsize::new(2).unwrap() },
            Vec::<[i64; 1]>::new(),
        )
        .unwrap();
        assert!(
            db.write_batches_committing_each(
                "INSERT INTO items (id) VALUES (?)",
                const { NonZeroUsize::new(2).unwrap() },
                [[1], [2], [3], [4], [1]]
            )
            .is_err()
        );
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items ORDER BY id", ())
                .unwrap(),
            [1, 2, 3, 4]
        );
        assert!(
            db.write_batches_committing_each(
                "INSERT INTO items (id) VALUES (?)",
                const { NonZeroUsize::new(2).unwrap() },
                [[5], [6], [7], [5], [8]]
            )
            .is_err()
        );
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items ORDER BY id", ())
                .unwrap(),
            [1, 2, 3, 4, 5, 6]
        );
        db.write_batches_committing_each(
            "INSERT INTO items (id) VALUES (?)",
            const { NonZeroUsize::new(2).unwrap() },
            [[7], [8], [9]],
        )
        .unwrap();
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items ORDER BY id", ())
                .unwrap(),
            [1, 2, 3, 4, 5, 6, 7, 8, 9]
        );
        assert!(
            db.write_batches_committing_each(
                "INSERT INTO items (id) VALUES (?)",
                NonZeroUsize::MIN,
                [[10], [11], [10]],
            )
            .is_err()
        );
        assert_eq!(
            db.read_column::<Vec<i64>, _, _>("SELECT id FROM items ORDER BY id", ())
                .unwrap(),
            (1..=11).collect::<Vec<_>>()
        );
    }

    #[test]
    fn chunked_reads_query_each_chunk_in_order() {
        let (_directory, db) = open();
        db.write_batch_atomic("INSERT INTO items (id) VALUES (?)", (1..=7).map(|id| [id]))
            .unwrap();
        let ids: Vec<i64> = (1..=7).collect();
        let one_at_a_time: Vec<i64> = db
            .read_chunked_in(
                "SELECT id FROM items WHERE id IN ({}) ORDER BY id DESC",
                &ids,
                NonZeroUsize::MIN,
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(one_at_a_time, ids);
        let by_chunk: Vec<i64> = db
            .read_chunked_in(
                "SELECT id FROM items WHERE id IN ({}) ORDER BY id DESC",
                &ids,
                const { NonZeroUsize::new(3).unwrap() },
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(by_chunk, [3, 2, 1, 6, 5, 4, 7]);
        let single_chunk: Vec<i64> = db
            .read_chunked_in(
                "SELECT id FROM items WHERE id IN ({}) ORDER BY id DESC",
                &ids,
                const { NonZeroUsize::new(10).unwrap() },
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(single_chunk, [7, 6, 5, 4, 3, 2, 1]);
        let none: Vec<i64> = db
            .read_chunked_in(
                "SELECT id FROM missing_table WHERE id IN ({})",
                &Vec::<i64>::new(),
                const { NonZeroUsize::new(3).unwrap() },
                |row| row.get(0),
            )
            .unwrap();
        assert!(none.is_empty());
        let many: Vec<i64> = (0..=MAX_SQL_BIND_PARAMS_PER_QUERY as i64).collect();
        let found: HashSet<i64> = db
            .read_chunked_in(
                "SELECT id FROM items WHERE id IN ({})",
                &many,
                const { NonZeroUsize::new(MAX_SQL_BIND_PARAMS_PER_QUERY).unwrap() },
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(found, HashSet::from([1, 2, 3, 4, 5, 6, 7]));
    }

    #[test]
    fn grouped_reads_collect_values_per_key() {
        let (_directory, db) = open();
        db.write_batch_atomic("INSERT INTO items (id) VALUES (?)", (1..=5).map(|id| [id]))
            .unwrap();
        let by_parity: HashMap<i64, Vec<i64>> = db
            .read_grouped("SELECT id % 2, id FROM items ORDER BY id", ())
            .unwrap();
        assert_eq!(
            by_parity,
            HashMap::from([(1, vec![1, 3, 5]), (0, vec![2, 4])])
        );
        let by_label: HashMap<String, HashSet<i64>> = db
            .read_grouped(
                "SELECT CASE WHEN id < 3 THEN 'low' ELSE 'high' END, id FROM items",
                (),
            )
            .unwrap();
        assert_eq!(
            by_label,
            HashMap::from([
                ("low".to_string(), HashSet::from([1, 2])),
                ("high".to_string(), HashSet::from([3, 4, 5]))
            ])
        );
        let empty: HashMap<i64, Vec<i64>> = db
            .read_grouped("SELECT id, id FROM items WHERE id > 5", ())
            .unwrap();
        assert!(empty.is_empty());
    }

    #[test]
    fn open_migrates_a_caller_schema_and_refuses_downgrade() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("items.db");
        {
            let db = Database::open(&path, &[CREATE_ITEMS]).unwrap();
            db.execute("INSERT INTO items (id) VALUES (?)", [7])
                .unwrap();
        }
        {
            let db = Database::open(&path, &[CREATE_ITEMS, ADD_LABEL]).unwrap();
            assert_eq!(db.read_value::<i64>("PRAGMA user_version", ()).unwrap(), 2);
            assert_eq!(
                db.read_optional::<String>("SELECT label FROM items WHERE id = ?", [7])
                    .unwrap(),
                Some("item".to_string())
            );
            assert_eq!(
                db.read_optional::<String>("SELECT label FROM items WHERE id = ?", [8])
                    .unwrap(),
                None
            );
        }
        let db = Database::open(&path, &[CREATE_ITEMS, ADD_LABEL]).unwrap();
        assert_eq!(
            db.read_value::<i64>("SELECT COUNT(*) FROM items", ())
                .unwrap(),
            1
        );
        assert!(matches!(
            Database::open(&path, &[CREATE_ITEMS]),
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
            let db = Database::open(&path, &[CREATE_ITEMS]).unwrap();
            db.execute("INSERT INTO items (id) VALUES (?)", [7])
                .unwrap();
        }
        assert!(
            Database::open(
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
                .pragma_query_value(None, "user_version", |row| row.get(0))
                .unwrap();
            assert_eq!(version, 1);
            let columns: Vec<String> = connection
                .prepare("SELECT name FROM pragma_table_info('items')")
                .unwrap()
                .query_map((), |row| row.get(0))
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            assert_eq!(columns, ["id"]);
        }
        let db = Database::open(&path, &[CREATE_ITEMS, ADD_LABEL]).unwrap();
        assert_eq!(db.read_value::<i64>("SELECT id FROM items", ()).unwrap(), 7);
        assert_eq!(db.read_value::<i64>("PRAGMA user_version", ()).unwrap(), 2);
    }

    #[test]
    fn bind_placeholders_joins_question_marks() {
        assert_eq!(bind_placeholders(0), "");
        assert_eq!(bind_placeholders(1), "?");
        assert_eq!(bind_placeholders(3), "?, ?, ?");
    }
}
