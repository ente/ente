use std::collections::HashMap;

use super::helpers::pair;

use crate::ml_db::{MlDb, Result};

pub const PET_ML_VERSION: i64 = 1;

impl MlDb {
    pub fn pet_indexed_file_ids(&self, minimum_ml_version: i64) -> Result<HashMap<i64, i64>> {
        self.read_all(
            "SELECT DISTINCT file_id, ml_version FROM pet_faces WHERE ml_version >= ?",
            [minimum_ml_version],
            pair,
        )
    }
}
