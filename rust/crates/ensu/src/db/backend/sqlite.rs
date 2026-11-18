use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, MutexGuard};

use rusqlite::types::Value as SqlValue;
use rusqlite::{Connection, Transaction, TransactionBehavior, params_from_iter};

use crate::db::{Backend, BackendTx, Error, Result, Row, Value};

#[cfg(test)]
mod transaction_tests;

pub struct SqliteBackend {
    conn: Mutex<Connection>,
    // Accessed only while holding conn's mutex.
    cleanup_failed: AtomicBool,
}

impl SqliteBackend {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch("PRAGMA foreign_keys = ON; PRAGMA secure_delete = ON;")?;
        Ok(Self {
            conn: Mutex::new(conn),
            cleanup_failed: AtomicBool::new(false),
        })
    }

    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys = ON;")?;
        Ok(Self {
            conn: Mutex::new(conn),
            cleanup_failed: AtomicBool::new(false),
        })
    }

    fn lock_conn(&self) -> Result<MutexGuard<'_, Connection>> {
        let conn = self.conn.lock().map_err(|_| {
            Error::UnsupportedOperation("sqlite connection lock poisoned".to_string())
        })?;
        if self.cleanup_failed.load(Ordering::Relaxed) {
            return Err(Error::UnsupportedOperation(
                "sqlite connection has an unfinished transaction; reopen the database".to_string(),
            ));
        }
        Ok(conn)
    }
}

impl BackendTx for SqliteBackend {
    fn execute(&self, sql: &str, params: &[Value]) -> Result<usize> {
        let conn = self.lock_conn()?;
        execute_impl(&conn, sql, params)
    }

    fn query(&self, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
        let conn = self.lock_conn()?;
        query_impl(&conn, sql, params)
    }

    fn query_row(&self, sql: &str, params: &[Value]) -> Result<Option<Row>> {
        let conn = self.lock_conn()?;
        query_row_impl(&conn, sql, params)
    }

    fn execute_batch(&self, sql: &str) -> Result<()> {
        let conn = self.lock_conn()?;
        execute_batch_impl(&conn, sql)
    }
}

impl Backend for SqliteBackend {
    type Tx<'a> = Transaction<'a>;

    fn transaction<T, F>(&self, f: F) -> Result<T>
    where
        F: for<'a> FnOnce(&Self::Tx<'a>) -> Result<T>,
    {
        let mut conn = self.lock_conn()?;
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let result = f(&tx).and_then(|value| {
            tx.commit()?;
            Ok(value)
        });
        // rusqlite ignores rollback errors on drop; block reuse if cleanup failed.
        if !conn.is_autocommit() {
            self.cleanup_failed.store(true, Ordering::Relaxed);
        }
        result
    }
}

impl BackendTx for Transaction<'_> {
    fn execute(&self, sql: &str, params: &[Value]) -> Result<usize> {
        execute_impl(self, sql, params)
    }

    fn query(&self, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
        query_impl(self, sql, params)
    }

    fn query_row(&self, sql: &str, params: &[Value]) -> Result<Option<Row>> {
        query_row_impl(self, sql, params)
    }

    fn execute_batch(&self, sql: &str) -> Result<()> {
        execute_batch_impl(self, sql)
    }
}

fn execute_impl(conn: &Connection, sql: &str, params: &[Value]) -> Result<usize> {
    let params = to_sql_params(params);
    Ok(conn.execute(sql, params_from_iter(params))?)
}

fn execute_batch_impl(conn: &Connection, sql: &str) -> Result<()> {
    conn.execute_batch(sql)?;
    Ok(())
}

fn query_impl(conn: &Connection, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
    let params = to_sql_params(params);
    let mut stmt = conn.prepare(sql)?;
    let mut rows = stmt.query(params_from_iter(params))?;
    let mut results = Vec::new();
    while let Some(row) = rows.next()? {
        let column_count = row.as_ref().column_count();
        let mut values = Vec::with_capacity(column_count);
        for idx in 0..column_count {
            let value: SqlValue = row.get(idx)?;
            values.push(from_sql_value(value)?);
        }
        results.push(values);
    }
    Ok(results)
}

fn query_row_impl(conn: &Connection, sql: &str, params: &[Value]) -> Result<Option<Row>> {
    let rows = query_impl(conn, sql, params)?;
    Ok(rows.into_iter().next())
}

fn to_sql_params(params: &[Value]) -> Vec<SqlValue> {
    params.iter().map(to_sql_value).collect()
}

fn to_sql_value(value: &Value) -> SqlValue {
    match value {
        Value::Null => SqlValue::Null,
        Value::Integer(v) => SqlValue::Integer(*v),
        Value::Text(v) => SqlValue::Text(v.clone()),
        Value::Blob(v) => SqlValue::Blob(v.clone()),
    }
}

fn from_sql_value(value: SqlValue) -> Result<Value> {
    match value {
        SqlValue::Null => Ok(Value::Null),
        SqlValue::Integer(v) => Ok(Value::Integer(v)),
        SqlValue::Text(v) => Ok(Value::Text(v)),
        SqlValue::Blob(v) => Ok(Value::Blob(v)),
        SqlValue::Real(_) => Err(Error::UnsupportedValueType("real".to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disk_connections_enable_secure_delete() {
        let path = std::env::temp_dir().join(format!("ensu-sqlite-{}", uuid::Uuid::new_v4()));
        let backend = SqliteBackend::open(&path).unwrap();
        assert_eq!(
            backend.query_row("PRAGMA secure_delete", &[]).unwrap(),
            Some(vec![Value::Integer(1)])
        );
        drop(backend);
        std::fs::remove_file(path).unwrap();
    }
}
