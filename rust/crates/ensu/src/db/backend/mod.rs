use crate::db::{Error, Result};

#[cfg(feature = "sqlite")]
pub mod sqlite;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Integer(i64),
    Text(String),
    Blob(Vec<u8>),
}

pub type Row = Vec<Value>;

pub trait BackendTx {
    fn execute(&self, sql: &str, params: &[Value]) -> Result<usize>;
    fn query(&self, sql: &str, params: &[Value]) -> Result<Vec<Row>>;
    fn query_row(&self, sql: &str, params: &[Value]) -> Result<Option<Row>>;
    fn execute_batch(&self, sql: &str) -> Result<()>;
}

pub trait Backend: BackendTx {
    type Tx<'a>: BackendTx
    where
        Self: 'a;

    fn transaction<T, F>(&self, f: F) -> Result<T>
    where
        F: for<'a> FnOnce(&Self::Tx<'a>) -> Result<T>;
}

pub trait RowExt {
    fn get_i64(&self, idx: usize) -> Result<i64>;
    fn get_string(&self, idx: usize) -> Result<String>;
    fn get_blob(&self, idx: usize) -> Result<Vec<u8>>;
    fn get_optional_string(&self, idx: usize) -> Result<Option<String>>;
    fn get_optional_i64(&self, idx: usize) -> Result<Option<i64>>;
}

impl RowExt for Vec<Value> {
    fn get_i64(&self, idx: usize) -> Result<i64> {
        match self.get(idx) {
            Some(Value::Integer(value)) => Ok(*value),
            Some(other) => Err(Error::Row(format!(
                "expected integer at column {idx}, got {other:?}"
            ))),
            None => Err(Error::Row(format!("missing column {idx}"))),
        }
    }

    fn get_string(&self, idx: usize) -> Result<String> {
        match self.get(idx) {
            Some(Value::Text(value)) => Ok(value.clone()),
            Some(other) => Err(Error::Row(format!(
                "expected text at column {idx}, got {other:?}"
            ))),
            None => Err(Error::Row(format!("missing column {idx}"))),
        }
    }

    fn get_blob(&self, idx: usize) -> Result<Vec<u8>> {
        match self.get(idx) {
            Some(Value::Blob(value)) => Ok(value.clone()),
            Some(other) => Err(Error::Row(format!(
                "expected blob at column {idx}, got {other:?}"
            ))),
            None => Err(Error::Row(format!("missing column {idx}"))),
        }
    }

    fn get_optional_string(&self, idx: usize) -> Result<Option<String>> {
        match self.get(idx) {
            Some(Value::Null) => Ok(None),
            Some(Value::Text(value)) => Ok(Some(value.clone())),
            Some(other) => Err(Error::Row(format!(
                "expected optional text at column {idx}, got {other:?}"
            ))),
            None => Err(Error::Row(format!("missing column {idx}"))),
        }
    }

    fn get_optional_i64(&self, idx: usize) -> Result<Option<i64>> {
        match self.get(idx) {
            Some(Value::Null) => Ok(None),
            Some(Value::Integer(value)) => Ok(Some(*value)),
            Some(other) => Err(Error::Row(format!(
                "expected optional integer at column {idx}, got {other:?}"
            ))),
            None => Err(Error::Row(format!("missing column {idx}"))),
        }
    }
}
