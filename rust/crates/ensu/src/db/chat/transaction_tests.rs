use super::*;
use crate::db::SqliteBackend;
use rusqlite::Connection;

#[test]
fn busy_commit_zero_timeout_recovers_chat_durability() -> Result<()> {
    let root = tempfile::tempdir()?;
    let path = root.path().join("chat.db");
    let key = vec![7; 32];
    let db = ChatDb::open_sqlite_with_defaults(&path, key.clone())?;
    db.backend.execute_batch("PRAGMA busy_timeout = 0")?;
    assert_eq!(
        db.backend.query_row("PRAGMA journal_mode", &[])?,
        Some(vec![Value::Text("delete".into())])
    );
    let original = db.create_session("original")?;
    let retry = db.create_session("retry deletion")?;
    let reader = Connection::open(&path)?;
    reader.execute_batch("BEGIN; SELECT * FROM sessions;")?;

    let result = db.delete_session(original.uuid);
    assert!(
        matches!(result, Err(Error::Sqlite(ref err)) if err.sqlite_error_code() == Some(rusqlite::ErrorCode::DatabaseBusy))
    );
    reader.execute_batch("ROLLBACK")?;
    assert!(
        db.get_session(original.uuid)?.is_some(),
        "failed delete must be rolled back before reuse"
    );
    db.delete_session(retry.uuid)?;
    let later = db.create_session("acknowledged after failure")?;
    assert!(db.get_session(later.uuid)?.is_some());
    drop(db);

    let reopened = ChatDb::<SqliteBackend>::open_sqlite_with_defaults(&path, key)?;
    assert!(reopened.get_session(original.uuid)?.is_some());
    assert!(reopened.get_session(retry.uuid)?.is_none());
    assert_eq!(
        reopened
            .get_session(later.uuid)?
            .map(|session| session.title),
        Some(later.title)
    );
    Ok(())
}
