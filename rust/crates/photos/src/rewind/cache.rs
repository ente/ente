use std::collections::BTreeMap;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, PoisonError};

use super::Result;
use super::state::{REWIND_VERSION, RewindState};

static CLEAR_COUNTS: Mutex<BTreeMap<PathBuf, u64>> = Mutex::new(BTreeMap::new());

pub(super) fn read(directory: &Path, year: i32, local_gallery_mode: bool) -> Option<RewindState> {
    let path = path(directory, year);
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == ErrorKind::NotFound => return None,
        Err(error) => {
            log::warn!("failed to read {}: {error}", path.display());
            return None;
        }
    };
    match serde_json::from_slice::<RewindState>(&bytes) {
        Ok(state) if state.version == REWIND_VERSION && state.year == year => {
            (state.local_gallery_mode == local_gallery_mode).then_some(state)
        }
        Ok(state) => {
            log::info!(
                "ignoring rewind {} cache of version {}",
                state.year,
                state.version
            );
            None
        }
        Err(error) => {
            log::warn!("ignoring unreadable {}: {error}", path.display());
            None
        }
    }
}

pub(super) fn read_final(
    directory: &Path,
    year: i32,
    local_gallery_mode: bool,
) -> Option<RewindState> {
    read(directory, year, local_gallery_mode).filter(|state| state.is_final)
}

pub(super) fn clear_count(directory: &Path) -> u64 {
    clear_count_in(&lock_clear_counts(), directory)
}

pub(super) fn publish(
    directory: &Path,
    state: RewindState,
    clear_count_before: u64,
) -> Result<RewindState> {
    let clear_counts = lock_clear_counts();
    if clear_count_in(&clear_counts, directory) != clear_count_before {
        return Ok(state);
    }
    if let Some(final_state) = read_final(directory, state.year, state.local_gallery_mode) {
        return Ok(final_state);
    }
    write(directory, &state)?;
    Ok(state)
}

pub(super) fn clear(directory: &Path) -> Result<()> {
    let mut clear_counts = lock_clear_counts();
    *clear_counts.entry(directory.to_path_buf()).or_default() += 1;
    match fs::remove_dir_all(directory) {
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
        removed => Ok(removed?),
    }
}

fn write(directory: &Path, state: &RewindState) -> Result<()> {
    fs::create_dir_all(directory)?;
    let path = path(directory, state.year);
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let written = fs::write(&temporary, serde_json::to_vec(state)?)
        .and_then(|()| fs::rename(&temporary, &path));
    if written.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    Ok(written?)
}

fn lock_clear_counts() -> MutexGuard<'static, BTreeMap<PathBuf, u64>> {
    CLEAR_COUNTS.lock().unwrap_or_else(PoisonError::into_inner)
}

fn clear_count_in(clear_counts: &BTreeMap<PathBuf, u64>, directory: &Path) -> u64 {
    directory
        .ancestors()
        .filter_map(|ancestor| clear_counts.get(ancestor))
        .sum()
}

fn path(directory: &Path, year: i32) -> PathBuf {
    directory.join(format!("{year}.json"))
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    use super::{clear_count, lock_clear_counts, publish, read, write};
    use crate::rewind::{REWIND_VERSION, RewindReport, RewindState, RewindStatus, Totals};

    fn state(files: u32, is_final: bool) -> RewindState {
        RewindState {
            year: 2026,
            version: REWIND_VERSION,
            computed_at: 0,
            local_gallery_mode: false,
            ml_coverage: None,
            is_final,
            status: RewindStatus::Ready {
                report: RewindReport {
                    totals: Some(Totals { files }),
                },
            },
        }
    }

    #[test]
    fn a_publication_waits_for_the_lock_and_keeps_a_final_result_written_meanwhile() {
        let directory = tempfile::tempdir().unwrap();
        let cache = directory.path().join("rewind");
        let frozen = state(1, true);
        let clear_count_before = clear_count(&cache);
        let held = lock_clear_counts();
        let (sender, receiver) = mpsc::channel();
        thread::scope(|scope| {
            scope.spawn(|| {
                let published = publish(&cache, state(2, false), clear_count_before);
                sender.send(published.unwrap()).unwrap();
            });
            assert!(receiver.recv_timeout(Duration::from_millis(200)).is_err());
            write(&cache, &frozen).unwrap();
            drop(held);
            assert_eq!(receiver.recv().unwrap(), frozen);
        });
        assert_eq!(read(&cache, 2026, false), Some(frozen));
    }
}
