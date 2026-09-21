use rusqlite::TransactionBehavior;

pub use rusqlite::{
    Connection, Error as SqliteError, OptionalExtension, Result as SqliteResult, Row, Transaction,
    params, params_from_iter, types,
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Sqlite(#[from] SqliteError),
    #[error("database version {current} is newer than this build supports ({target})")]
    Downgrade { current: i64, target: i64 },
}

pub type Result<T> = std::result::Result<T, Error>;

pub struct Db(Connection);

impl Db {
    pub fn new(connection: Connection) -> Self {
        Self(connection)
    }

    pub fn migrate(&mut self, scripts: &[&str]) -> Result<()> {
        let target = scripts.len() as i64;
        let transaction = self
            .0
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let current: i64 =
            transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
        if current > target {
            return Err(Error::Downgrade { current, target });
        }
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

    pub fn read<T>(&self, read: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
        read(&self.0)
    }

    pub fn write<T>(&mut self, write: impl FnOnce(&Transaction<'_>) -> Result<T>) -> Result<T> {
        let transaction = self
            .0
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let result = write(&transaction)?;
        transaction.commit()?;
        Ok(result)
    }
}
