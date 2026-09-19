use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, Mutex, PoisonError, Weak};

use super::Index;

#[derive(Default)]
pub(super) struct Locks {
    pub mutations: Mutex<()>,
    pub fills: [Mutex<()>; Index::ALL.len()],
}

static REGISTRY: LazyLock<Mutex<HashMap<PathBuf, Weak<Locks>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(super) fn for_database(db_path: &Path) -> Arc<Locks> {
    let key = db_path
        .canonicalize()
        .unwrap_or_else(|_| db_path.to_path_buf());
    let mut registry = REGISTRY.lock().unwrap_or_else(PoisonError::into_inner);
    registry.retain(|_, lock| lock.strong_count() > 0);
    if let Some(lock) = registry.get(&key).and_then(Weak::upgrade) {
        return lock;
    }
    let lock = Arc::new(Locks::default());
    registry.insert(key, Arc::downgrade(&lock));
    lock
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::for_database;
    use crate::ml_store::tests::{DB_FILE, open};

    #[test]
    fn mutation_lock_is_shared_per_canonical_database_path() {
        let (directory, _store) = open();
        let first = for_database(&directory.path().join(DB_FILE));
        let second = for_database(&directory.path().join(".").join(DB_FILE));
        assert!(Arc::ptr_eq(&first, &second));
        let other = for_database(&directory.path().join("ente.ml.offline.db"));
        assert!(!Arc::ptr_eq(&first, &other));
    }
}
