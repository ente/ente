use crate::Result;
use rusqlite::{Connection, OptionalExtension, params};
use std::time::{SystemTime, UNIX_EPOCH};

pub struct ConfigStore<'a> {
    conn: &'a Connection,
}

impl<'a> ConfigStore<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    pub fn set(&self, key: &str, value: &str) -> Result<()> {
        let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64;

        self.conn.execute(
            "INSERT OR REPLACE INTO config (key, value, updated_at) 
             VALUES (?1, ?2, ?3)",
            params![key, value, now],
        )?;

        Ok(())
    }

    pub fn get(&self, key: &str) -> Result<Option<String>> {
        let mut stmt = self
            .conn
            .prepare("SELECT value FROM config WHERE key = ?1")?;

        let value = stmt
            .query_row(params![key], |row| row.get::<_, String>(0))
            .optional()?;

        Ok(value)
    }

    pub fn delete(&self, key: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM config WHERE key = ?1", params![key])?;

        Ok(())
    }

    pub fn list(&self) -> Result<Vec<(String, String)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT key, value FROM config ORDER BY key")?;

        let configs = stmt
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(configs)
    }
}
