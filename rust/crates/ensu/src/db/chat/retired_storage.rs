use std::path::Path;

pub(super) fn cleanup(db_path: &Path) {
    let Some(root) = db_path.parent() else {
        return;
    };
    for name in ["llmchat_sync.db", "llmchat_sync_v2.db", "llmchat_online.db"] {
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(root.join(format!("{name}{suffix}")));
        }
    }
    for name in ["llmchat", "sync_meta", "chat_attachments_encrypted"] {
        let _ = std::fs::remove_dir_all(root.join(name));
    }
}

#[cfg(test)]
mod tests {
    use crate::db::chat::ChatDb;
    use crate::db::crypto::KEY_BYTES;
    use uuid::Uuid;

    #[test]
    fn sqlite_open_removes_retired_storage() {
        let root = std::env::temp_dir().join(format!("ensu-db-{}", Uuid::new_v4()));
        std::fs::create_dir_all(root.join("sync_meta")).unwrap();
        std::fs::create_dir_all(root.join("llmchat")).unwrap();
        for name in [
            "llmchat_sync.db",
            "llmchat_sync.db-wal",
            "llmchat_sync_v2.db",
            "llmchat_online.db",
        ] {
            std::fs::write(root.join(name), b"obsolete").unwrap();
        }

        ChatDb::open_sqlite_with_defaults(root.join("llmchat.db"), vec![1u8; KEY_BYTES]).unwrap();

        assert!(!root.join("llmchat_sync.db").exists());
        assert!(!root.join("llmchat_sync.db-wal").exists());
        assert!(!root.join("llmchat_sync_v2.db").exists());
        assert!(!root.join("llmchat_online.db").exists());
        assert!(!root.join("sync_meta").exists());
        assert!(!root.join("llmchat").exists());
        std::fs::remove_dir_all(root).unwrap();
    }
}
