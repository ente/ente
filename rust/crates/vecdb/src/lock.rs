use std::fs::{File, TryLockError};
use std::path::{Path, PathBuf};
use std::time::Duration;

use super::VecDbError;

const ACQUIRE_ATTEMPTS: usize = 8;
const CONTENTION_GRACE_STEPS: usize = 50;
const CONTENTION_GRACE_STEP: Duration = Duration::from_millis(1);

#[derive(Debug)]
pub(crate) struct WriterLock {
    _file: File,
}

impl WriterLock {
    pub(crate) fn acquire(log_path: &Path) -> Result<Self, VecDbError> {
        let mut remaining_grace = CONTENTION_GRACE_STEPS;
        loop {
            if let Some(lock) = Self::acquire_once(log_path)? {
                return Ok(lock);
            }
            if remaining_grace == 0 {
                return Err(VecDbError::Locked(log_path.to_path_buf()));
            }
            remaining_grace -= 1;
            std::thread::sleep(CONTENTION_GRACE_STEP);
        }
    }

    fn acquire_once(log_path: &Path) -> Result<Option<Self>, VecDbError> {
        let sidecar = lock_path(log_path);
        for _ in 0..ACQUIRE_ATTEMPTS {
            let file = open_sidecar(&sidecar)?;
            match file.try_lock() {
                Ok(()) => {
                    if lock_is_on_the_linked_sidecar(&file, &sidecar)? {
                        return Ok(Some(Self { _file: file }));
                    }
                }
                Err(TryLockError::WouldBlock) => return Ok(None),
                Err(TryLockError::Error(source)) => return Err(VecDbError::io(&sidecar, source)),
            }
        }
        Err(VecDbError::Locked(log_path.to_path_buf()))
    }
}

pub(crate) fn lock_path(log_path: &Path) -> PathBuf {
    let mut extended = log_path.as_os_str().to_os_string();
    extended.push(".lock");
    PathBuf::from(extended)
}

fn open_sidecar(sidecar: &Path) -> Result<File, VecDbError> {
    File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(sidecar)
        .map_err(|source| VecDbError::io(sidecar, source))
}

#[cfg(unix)]
fn lock_is_on_the_linked_sidecar(file: &File, sidecar: &Path) -> Result<bool, VecDbError> {
    use std::io::ErrorKind;
    use std::os::unix::fs::MetadataExt;

    let held = file
        .metadata()
        .map_err(|source| VecDbError::io(sidecar, source))?;
    match std::fs::metadata(sidecar) {
        Ok(linked) => Ok(linked.dev() == held.dev() && linked.ino() == held.ino()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(false),
        Err(source) => Err(VecDbError::io(sidecar, source)),
    }
}

#[cfg(not(unix))]
fn lock_is_on_the_linked_sidecar(_file: &File, _sidecar: &Path) -> Result<bool, VecDbError> {
    Ok(true)
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;

    #[test]
    fn lock_path_appends_the_lock_extension() {
        assert_eq!(
            lock_path(Path::new("/a/vectors")),
            Path::new("/a/vectors.lock")
        );
        assert_eq!(
            lock_path(Path::new("/a/vectors.db")),
            Path::new("/a/vectors.db.lock")
        );
    }

    #[test]
    fn acquire_creates_and_locks_the_sidecar() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let _guard = WriterLock::acquire(&log_path).unwrap();
        assert!(lock_path(&log_path).exists());
        assert!(!log_path.exists());
    }

    #[test]
    fn second_acquire_on_the_same_path_reports_the_log_path() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let _holder = WriterLock::acquire(&log_path).unwrap();
        let error = WriterLock::acquire(&log_path).unwrap_err();
        assert!(matches!(error, VecDbError::Locked(locked) if locked == log_path));
    }

    #[test]
    fn dropping_the_guard_releases_the_lock() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let holder = WriterLock::acquire(&log_path).unwrap();
        drop(holder);
        assert!(WriterLock::acquire(&log_path).is_ok());
    }

    #[test]
    fn distinct_paths_lock_independently() {
        let dir = TempDir::new().unwrap();
        let _first = WriterLock::acquire(&dir.path().join("first")).unwrap();
        assert!(WriterLock::acquire(&dir.path().join("second")).is_ok());
    }

    #[cfg(unix)]
    #[test]
    fn unlinking_the_sidecar_orphans_the_held_lock_and_frees_the_path() {
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("log");
        let sidecar = lock_path(&log_path);
        let orphaned = WriterLock::acquire(&log_path).unwrap();
        std::fs::remove_file(&sidecar).unwrap();
        assert!(!lock_is_on_the_linked_sidecar(&orphaned._file, &sidecar).unwrap());
        let successor = WriterLock::acquire(&log_path).unwrap();
        assert!(lock_is_on_the_linked_sidecar(&successor._file, &sidecar).unwrap());
        let error = WriterLock::acquire(&log_path).unwrap_err();
        assert!(matches!(error, VecDbError::Locked(locked) if locked == log_path));
    }
}
