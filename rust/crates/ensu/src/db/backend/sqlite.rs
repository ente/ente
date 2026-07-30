use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use rusqlite::types::Value as SqlValue;
use rusqlite::{Connection, params_from_iter};

use crate::db::{Backend, BackendTx, Error, Result, Row, Value};

pub struct SqliteBackend {
    conn: Mutex<Connection>,
}

impl SqliteBackend {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.execute_batch("PRAGMA foreign_keys = ON; PRAGMA secure_delete = ON;")?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys = ON;")?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    fn lock_conn(&self) -> Result<MutexGuard<'_, Connection>> {
        self.conn
            .lock()
            .map_err(|_| Error::UnsupportedOperation("sqlite connection lock poisoned".to_string()))
    }
}

pub struct SqliteTransaction<'a> {
    guard: MutexGuard<'a, Connection>,
}

impl<'a> SqliteTransaction<'a> {
    fn begin(guard: MutexGuard<'a, Connection>) -> Result<Self> {
        guard.execute_batch("BEGIN IMMEDIATE")?;
        Ok(Self { guard })
    }

    fn commit(self) -> Result<()> {
        self.guard.execute_batch("COMMIT")?;
        Ok(())
    }

    fn rollback(self) -> Result<()> {
        self.guard.execute_batch("ROLLBACK")?;
        Ok(())
    }
}

trait SqliteConn {
    fn execute_sql(&self, sql: &str, params: &[SqlValue]) -> rusqlite::Result<usize>;
    fn prepare_sql<'a>(&'a self, sql: &str) -> rusqlite::Result<rusqlite::Statement<'a>>;
    fn execute_batch_sql(&self, sql: &str) -> rusqlite::Result<()>;
}

impl SqliteConn for Connection {
    fn execute_sql(&self, sql: &str, params: &[SqlValue]) -> rusqlite::Result<usize> {
        self.execute(sql, params_from_iter(params.iter().cloned()))
    }

    fn prepare_sql<'a>(&'a self, sql: &str) -> rusqlite::Result<rusqlite::Statement<'a>> {
        self.prepare(sql)
    }

    fn execute_batch_sql(&self, sql: &str) -> rusqlite::Result<()> {
        self.execute_batch(sql)
    }
}

impl<'a> SqliteConn for SqliteTransaction<'a> {
    fn execute_sql(&self, sql: &str, params: &[SqlValue]) -> rusqlite::Result<usize> {
        self.guard
            .execute(sql, params_from_iter(params.iter().cloned()))
    }

    fn prepare_sql<'b>(&'b self, sql: &str) -> rusqlite::Result<rusqlite::Statement<'b>> {
        self.guard.prepare(sql)
    }

    fn execute_batch_sql(&self, sql: &str) -> rusqlite::Result<()> {
        self.guard.execute_batch(sql)
    }
}

impl BackendTx for SqliteBackend {
    fn execute(&self, sql: &str, params: &[Value]) -> Result<usize> {
        let conn = self.lock_conn()?;
        execute_impl(&*conn, sql, params)
    }

    fn query(&self, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
        let conn = self.lock_conn()?;
        query_impl(&*conn, sql, params)
    }

    fn query_row(&self, sql: &str, params: &[Value]) -> Result<Option<Row>> {
        let conn = self.lock_conn()?;
        query_row_impl(&*conn, sql, params)
    }

    fn execute_batch(&self, sql: &str) -> Result<()> {
        let conn = self.lock_conn()?;
        execute_batch_impl(&*conn, sql)
    }
}

impl Backend for SqliteBackend {
    type Tx<'a> = SqliteTransaction<'a>;

    fn transaction<T, F>(&self, f: F) -> Result<T>
    where
        F: for<'a> FnOnce(&Self::Tx<'a>) -> Result<T>,
    {
        let guard = self.lock_conn()?;
        let wrapper = SqliteTransaction::begin(guard)?;
        let result = f(&wrapper);
        match result {
            Ok(value) => {
                wrapper.commit()?;
                Ok(value)
            }
            Err(err) => {
                wrapper.rollback()?;
                Err(err)
            }
        }
    }
}

impl<'a> BackendTx for SqliteTransaction<'a> {
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

fn execute_impl<C: SqliteConn>(conn: &C, sql: &str, params: &[Value]) -> Result<usize> {
    let params = to_sql_params(params);
    Ok(conn.execute_sql(sql, &params)?)
}

fn execute_batch_impl<C: SqliteConn>(conn: &C, sql: &str) -> Result<()> {
    conn.execute_batch_sql(sql)?;
    Ok(())
}

fn query_impl<C: SqliteConn>(conn: &C, sql: &str, params: &[Value]) -> Result<Vec<Row>> {
    let params = to_sql_params(params);
    let mut stmt = conn.prepare_sql(sql)?;
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

fn query_row_impl<C: SqliteConn>(conn: &C, sql: &str, params: &[Value]) -> Result<Option<Row>> {
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
