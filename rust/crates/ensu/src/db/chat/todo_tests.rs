use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};

use super::*;
use crate::tools::test_support::db;

#[test]
fn manual_edits_check_versions_and_titles() {
    let db = db();
    let changes = Arc::new(AtomicI64::new(0));
    let seen = changes.clone();
    db.observe_tools(Arc::new(move || {
        seen.fetch_add(1, Ordering::Relaxed);
    }));
    let todo = db.create_todo("  read   book ", None).unwrap();
    assert_eq!(changes.load(Ordering::Relaxed), 1);
    assert_eq!(todo.title, "Read book");
    assert!(db.create_todo(" ", None).is_err());
    assert_eq!(db.create_todo(".env", None).unwrap().title, ".env");
    assert!(db.create_todo(&"x".repeat(201), None).is_err());
    let renamed = db
        .update_todo(todo.id, todo.version, "Read the book", Some(1))
        .unwrap();
    assert_eq!(renamed.version, 2);
    assert!(
        db.update_todo(todo.id, todo.version, "Stale", None)
            .is_err()
    );
    let done = db
        .set_todo_completed(renamed.id, renamed.version, true)
        .unwrap();
    assert_eq!(
        db.set_todo_completed(done.id, done.version, true).unwrap(),
        done
    );
    assert!(db.delete_todo(done.id, renamed.version).is_err());
    db.delete_todo(done.id, done.version).unwrap();
    assert!(db.get_todo(done.id).unwrap().is_none());
}

#[test]
fn an_unchanged_update_keeps_its_version() {
    let db = db();
    let todo = db.create_todo("Read book", Some(5)).unwrap();
    let changes = Arc::new(AtomicI64::new(0));
    let seen = changes.clone();
    db.observe_tools(Arc::new(move || {
        seen.fetch_add(1, Ordering::Relaxed);
    }));

    let update = |version| db.update_todo(todo.id, version, "  read   book ", Some(5));
    assert_eq!(update(todo.version).unwrap(), todo);
    assert_eq!(db.get_todo(todo.id).unwrap(), Some(todo.clone()));
    assert_eq!(changes.load(Ordering::Relaxed), 0);
    assert!(matches!(
        update(todo.version + 1),
        Err(Error::Refused(Refusal::TodoChanged))
    ));
    let renamed = db
        .update_todo(todo.id, todo.version, "Read the book", Some(5))
        .unwrap();
    assert_eq!(renamed.version, todo.version + 1);
}

#[test]
fn version_six_databases_gain_to_do_tables_and_keep_chats() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("chat.db");
    let session = {
        let db = ChatDb::open_sqlite_with_defaults(&path, vec![7; 32]).unwrap();
        let session = db.create_session("Kept").unwrap();
        db.backend
            .execute_batch("DROP TABLE tool_turns; DROP TABLE todos; PRAGMA user_version = 6;")
            .unwrap();
        session
    };
    let db = ChatDb::open_sqlite_with_defaults(&path, vec![7; 32]).unwrap();
    assert_eq!(db.get_session(session.uuid).unwrap().unwrap().title, "Kept");
    assert_eq!(
        db.backend
            .query_row("PRAGMA user_version", &[])
            .unwrap()
            .unwrap()
            .get_i64(0)
            .unwrap(),
        8
    );
    db.create_todo("Works", None).unwrap();
}
