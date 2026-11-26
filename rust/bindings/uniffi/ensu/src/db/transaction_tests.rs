use super::*;

#[test]
fn retained_binding_handle_recovers_after_failed_commit() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("chat.db").to_string_lossy().into_owned();
    let key = vec![7; 32];
    let db = EnsuDb::open(path.clone(), key.clone()).unwrap();
    // Keep a second binding object referencing the same application ChatDb.
    let retained = EnsuDb {
        inner: db.inner.clone(),
    };
    let original = db.create_session("original".into()).unwrap();
    let retry = db.create_session("retry deletion".into()).unwrap();
    let reader = rusqlite::Connection::open(&path).unwrap();
    reader
        .execute_batch("BEGIN; SELECT * FROM sessions;")
        .unwrap();
    let error = db.delete_session(original.uuid.clone()).unwrap_err();
    assert!(
        matches!(error, DbError::Other { ref detail } if detail.contains("database is locked"))
    );
    reader.execute_batch("ROLLBACK").unwrap();
    drop(db);

    assert!(
        retained
            .get_session(original.uuid.clone())
            .unwrap()
            .is_some()
    );
    retained.delete_session(retry.uuid.clone()).unwrap();
    let later = retained
        .create_session("acknowledged after failure".into())
        .unwrap();
    assert!(retained.get_session(later.uuid.clone()).unwrap().is_some());
    drop(retained);

    let reopened = EnsuDb::open(path, key).unwrap();
    assert!(reopened.get_session(original.uuid).unwrap().is_some());
    assert!(reopened.get_session(retry.uuid).unwrap().is_none());
    assert_eq!(
        reopened.get_session(later.uuid).unwrap().unwrap().title,
        later.title
    );
}
