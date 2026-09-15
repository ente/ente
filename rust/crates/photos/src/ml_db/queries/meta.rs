use crate::ml_db::schema;
use crate::ml_db::{MlDb, Result};

impl MlDb {
    pub fn get_meta(&self, key: &str) -> Result<Option<String>> {
        self.db
            .read_optional("SELECT value FROM ml_store_meta WHERE key = ?", [key])
            .map_err(Into::into)
    }

    pub fn set_meta(&self, key: &str, value: &str) -> Result<()> {
        self.db.execute(
            "INSERT OR REPLACE INTO ml_store_meta (key, value) VALUES (?, ?)",
            (key, value),
        )?;
        Ok(())
    }

    pub fn delete_meta(&self, key: &str) -> Result<()> {
        self.db
            .execute("DELETE FROM ml_store_meta WHERE key = ?", [key])?;
        Ok(())
    }

    pub fn clear_meta(&self) -> Result<()> {
        self.db
            .execute_statements([schema::DELETE_ML_STORE_META])
            .map_err(Into::into)
    }
}

#[cfg(test)]
mod tests {
    use crate::ml_db::tests::open;

    #[test]
    fn meta_rows_are_set_replaced_deleted_and_cleared() {
        let (_directory, db) = open();
        assert_eq!(db.get_meta("clip.fill").unwrap(), None);
        db.set_meta("clip.fill", "filling").unwrap();
        db.set_meta("clip.cursor", "42").unwrap();
        assert_eq!(
            db.get_meta("clip.fill").unwrap().as_deref(),
            Some("filling")
        );
        assert_eq!(db.get_meta("clip.cursor").unwrap().as_deref(), Some("42"));
        db.set_meta("clip.fill", "filled").unwrap();
        assert_eq!(db.get_meta("clip.fill").unwrap().as_deref(), Some("filled"));
        db.delete_meta("clip.cursor").unwrap();
        db.delete_meta("missing").unwrap();
        assert_eq!(db.get_meta("clip.cursor").unwrap(), None);
        assert_eq!(db.get_meta("clip.fill").unwrap().as_deref(), Some("filled"));
        db.clear_meta().unwrap();
        assert_eq!(db.get_meta("clip.fill").unwrap(), None);
    }
}
