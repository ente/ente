use super::*;
use rusqlite::hooks::{AuthAction, AuthContext, Authorization, TransactionOperation};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

fn assert_refuses_reuse(backend: &SqliteBackend) {
    assert!(backend.execute("INSERT INTO data VALUES (2)", &[]).is_err());
    assert!(
        backend
            .execute_batch("INSERT INTO data VALUES (3)")
            .is_err()
    );
    assert!(backend.query("SELECT * FROM data", &[]).is_err());
    assert!(backend.query_row("SELECT * FROM data", &[]).is_err());
    assert!(
        backend
            .transaction::<(), _>(|_| panic!("unusable connection reused"))
            .is_err()
    );
}

fn rollback_failure(commit_error: bool) {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("chat.db");
    let backend = SqliteBackend::open(&path).unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER)")
        .unwrap();
    backend.execute_batch("PRAGMA busy_timeout = 0").unwrap();
    let reader = Connection::open(&path).unwrap();
    if commit_error {
        reader.execute_batch("BEGIN; SELECT * FROM data;").unwrap();
    }
    let rollback_attempts = Arc::new(AtomicUsize::new(0));
    let attempts = rollback_attempts.clone();
    // Fail SQLite's actual ROLLBACK, leaving its transaction active. The hook
    // only exists in tests; production does not need rusqlite's hooks feature.
    backend
        .conn
        .lock()
        .unwrap()
        .authorizer(Some(move |ctx: AuthContext<'_>| match ctx.action {
            AuthAction::Transaction {
                operation: TransactionOperation::Rollback,
            } => {
                attempts.fetch_add(1, Ordering::SeqCst);
                Authorization::Deny
            }
            _ => Authorization::Allow,
        }))
        .unwrap();
    let error = backend
        .transaction(|tx| {
            tx.execute("INSERT INTO data VALUES (1)", &[])?;
            if commit_error {
                Ok(())
            } else {
                Err(Error::UnsupportedOperation("original body error".into()))
            }
        })
        .unwrap_err();
    if commit_error {
        reader.execute_batch("ROLLBACK").unwrap();
    }
    assert!(!backend.conn.lock().unwrap().is_autocommit());
    assert_refuses_reuse(&backend);
    if commit_error {
        assert!(
            matches!(error, Error::Sqlite(ref err) if err.sqlite_error_code() == Some(rusqlite::ErrorCode::DatabaseBusy))
        );
    } else {
        assert!(
            matches!(error, Error::UnsupportedOperation(ref message) if message == "original body error")
        );
    }
    assert_eq!(rollback_attempts.load(Ordering::SeqCst), 1);
    drop(backend);
    let reopened = SqliteBackend::open(&path).unwrap();
    assert_eq!(
        reopened
            .query_row("SELECT COUNT(*) FROM data", &[])
            .unwrap(),
        Some(vec![Value::Integer(0)])
    );
    reopened
        .execute("INSERT INTO data VALUES (4)", &[])
        .unwrap();
}

#[test]
fn body_error_with_failed_rollback_refuses_reuse() {
    rollback_failure(false);
}

#[test]
fn commit_error_with_failed_rollback_refuses_reuse() {
    rollback_failure(true);
}

#[test]
fn body_error_rolls_back_before_reuse() {
    let backend = SqliteBackend::open_in_memory().unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER)")
        .unwrap();
    let error = backend
        .transaction::<(), _>(|tx| {
            tx.execute("INSERT INTO data VALUES (1)", &[])?;
            Err(Error::UnsupportedOperation("original body error".into()))
        })
        .unwrap_err();
    assert!(
        matches!(error, Error::UnsupportedOperation(ref message) if message == "original body error")
    );
    backend.execute("INSERT INTO data VALUES (2)", &[]).unwrap();
    assert_eq!(
        backend.query("SELECT value FROM data", &[]).unwrap(),
        vec![vec![Value::Integer(2)]]
    );
}

#[test]
fn panic_rolls_back_and_refuses_reuse() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("chat.db");
    let backend = SqliteBackend::open(&path).unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER)")
        .unwrap();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        backend.transaction::<(), _>(|tx| {
            tx.execute("INSERT INTO data VALUES (1)", &[])?;
            panic!("transaction body panicked");
        })
    }));
    assert!(result.is_err());
    assert!(
        backend
            .conn
            .lock()
            .unwrap_err()
            .into_inner()
            .is_autocommit()
    );
    assert_refuses_reuse(&backend);
    drop(backend);
    let reopened = SqliteBackend::open(&path).unwrap();
    assert!(
        reopened
            .query("SELECT * FROM data", &[])
            .unwrap()
            .is_empty()
    );
}

#[test]
fn already_rolled_back_body_preserves_original_error() {
    let backend = SqliteBackend::open_in_memory().unwrap();
    let result: Result<()> = backend.transaction(|tx| {
        tx.execute_batch("ROLLBACK")?;
        Err(Error::UnsupportedOperation("original body error".into()))
    });
    assert!(
        matches!(result, Err(Error::UnsupportedOperation(ref message)) if message == "original body error")
    );
    backend
        .transaction(|tx| tx.execute_batch("CREATE TABLE data (value INTEGER)"))
        .unwrap();
}

#[test]
fn commit_after_ended_transaction_reports_error_and_allows_reuse() {
    let backend = SqliteBackend::open_in_memory().unwrap();
    assert!(
        backend
            .transaction(|tx| tx.execute_batch("ROLLBACK"))
            .is_err()
    );
    backend
        .transaction(|tx| tx.execute_batch("CREATE TABLE data (value INTEGER)"))
        .unwrap();
}

#[test]
fn manual_transaction_commit_remains_durable() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("manual.db");
    let backend = SqliteBackend::open(&path).unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER)")
        .unwrap();
    backend.execute_batch("BEGIN IMMEDIATE").unwrap();
    backend
        .execute("INSERT INTO data VALUES (?)", &[Value::Integer(1)])
        .unwrap();
    backend
        .execute_batch("INSERT INTO data VALUES (2)")
        .unwrap();
    assert_eq!(
        backend
            .query("SELECT value FROM data ORDER BY value", &[])
            .unwrap(),
        vec![vec![Value::Integer(1)], vec![Value::Integer(2)]]
    );
    assert_eq!(
        backend.query_row("SELECT COUNT(*) FROM data", &[]).unwrap(),
        Some(vec![Value::Integer(2)])
    );
    backend.execute("COMMIT", &[]).unwrap();
    drop(backend);
    let reopened = SqliteBackend::open(&path).unwrap();
    assert_eq!(
        reopened
            .query_row("SELECT COUNT(*) FROM data", &[])
            .unwrap(),
        Some(vec![Value::Integer(2)])
    );
}

#[test]
fn manual_transaction_survives_failed_wrapper_begin() {
    let backend = SqliteBackend::open_in_memory().unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER); BEGIN")
        .unwrap();
    backend.execute("INSERT INTO data VALUES (1)", &[]).unwrap();
    assert!(
        backend
            .transaction::<(), _>(|_| panic!("nested BEGIN must fail"))
            .is_err()
    );
    // The failed wrapper BEGIN must neither roll back nor poison the caller's transaction.
    assert_eq!(
        backend.query_row("SELECT COUNT(*) FROM data", &[]).unwrap(),
        Some(vec![Value::Integer(1)])
    );
    backend.execute_batch("ROLLBACK").unwrap();
    assert_eq!(
        backend.query_row("SELECT COUNT(*) FROM data", &[]).unwrap(),
        Some(vec![Value::Integer(0)])
    );
    backend
        .transaction(|tx| tx.execute("INSERT INTO data VALUES (2)", &[]))
        .unwrap();
    assert_eq!(
        backend.query_row("SELECT value FROM data", &[]).unwrap(),
        Some(vec![Value::Integer(2)])
    );
}

#[test]
fn manual_savepoints_preserve_commit_and_rollback() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("savepoints.db");
    let backend = SqliteBackend::open(&path).unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER); SAVEPOINT outer_tx")
        .unwrap();
    backend.execute("INSERT INTO data VALUES (1)", &[]).unwrap();
    backend
        .execute_batch("SAVEPOINT inner_tx; INSERT INTO data VALUES (2)")
        .unwrap();
    backend
        .execute_batch("ROLLBACK TO inner_tx; RELEASE inner_tx")
        .unwrap();
    assert_eq!(
        backend.query_row("SELECT value FROM data", &[]).unwrap(),
        Some(vec![Value::Integer(1)])
    );
    backend.execute_batch("RELEASE outer_tx").unwrap();
    drop(backend);
    let reopened = SqliteBackend::open(&path).unwrap();
    assert_eq!(
        reopened.query("SELECT value FROM data", &[]).unwrap(),
        vec![vec![Value::Integer(1)]]
    );
}

#[test]
fn wrapper_transaction_preserves_savepoints() {
    let backend = SqliteBackend::open_in_memory().unwrap();
    backend
        .execute_batch("CREATE TABLE data (value INTEGER)")
        .unwrap();
    backend.transaction(|tx| {
        tx.execute("INSERT INTO data VALUES (1)", &[])?;
        tx.execute_batch("SAVEPOINT inner_tx; INSERT INTO data VALUES (2); ROLLBACK TO inner_tx; RELEASE inner_tx")
    }).unwrap();
    assert_eq!(
        backend.query("SELECT value FROM data", &[]).unwrap(),
        vec![vec![Value::Integer(1)]]
    );
}
