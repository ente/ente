use std::{
    fs,
    io::{self, Write},
    num::NonZeroUsize,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, ensure};
use chrono::{Local, NaiveDate};

pub enum Destination {
    Stdout,
    File(PathBuf),
    Directory {
        path: PathBuf,
        extension: &'static str,
        keep: Option<NonZeroUsize>,
    },
}

pub struct Published {
    pub path: Option<PathBuf>,
    pub pruned: usize,
    pub prune_error: Option<anyhow::Error>,
}

impl Destination {
    pub fn file(path: PathBuf) -> Self {
        if path == Path::new("-") {
            Self::Stdout
        } else {
            Self::File(path)
        }
    }

    pub fn prepare(&self) -> Result<()> {
        match self {
            Self::Stdout => Ok(()),
            Self::File(path) => {
                match fs::symlink_metadata(path) {
                    Ok(_) => anyhow::bail!("output already exists: {}", path.display()),
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.into()),
                }
                ensure!(
                    parent(path).is_dir(),
                    "output parent directory does not exist: {}",
                    parent(path).display()
                );
                ensure!(path.file_name().is_some(), "output requires a filename");
                Ok(())
            }
            Self::Directory { path, .. } => {
                let mut builder = fs::DirBuilder::new();
                builder.recursive(true);
                #[cfg(unix)]
                {
                    use std::os::unix::fs::DirBuilderExt;
                    builder.mode(0o700);
                }
                builder
                    .create(path)
                    .with_context(|| format!("cannot create export directory {}", path.display()))
            }
        }
    }

    pub fn publish(&self, bytes: &[u8]) -> Result<Published> {
        match self {
            Self::Stdout => {
                let mut stdout = io::stdout().lock();
                stdout.write_all(bytes)?;
                stdout.flush()?;
                Ok(Published {
                    path: None,
                    pruned: 0,
                    prune_error: None,
                })
            }
            Self::File(path) => {
                stage(parent(path), bytes)?
                    .persist_noclobber(path)
                    .map_err(|error| error.error)
                    .with_context(|| format!("cannot publish {}", path.display()))?;
                Ok(Published {
                    path: Some(path.clone()),
                    pruned: 0,
                    prune_error: None,
                })
            }
            Self::Directory {
                path,
                extension,
                keep,
            } => publish_directory(path, extension, *keep, bytes, Local::now().date_naive()),
        }
    }
}

fn parent(path: &Path) -> &Path {
    path.parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."))
}

fn stage(directory: &Path, bytes: &[u8]) -> Result<tempfile::NamedTempFile> {
    let mut temporary = tempfile::NamedTempFile::new_in(directory)?;
    temporary.write_all(bytes)?;
    temporary.as_file().sync_all()?;
    Ok(temporary)
}

fn backup_name(name: &str, extension: &str) -> Option<(NaiveDate, u64)> {
    let stem = name
        .strip_prefix("ente-auth-")?
        .strip_suffix(&format!(".{extension}"))?;
    let date_text = stem.get(..10)?;
    let date = NaiveDate::parse_from_str(date_text, "%Y-%m-%d").ok()?;
    if date.format("%Y-%m-%d").to_string() != date_text {
        return None;
    }
    let suffix = stem.get(10..)?;
    let sequence = if suffix.is_empty() {
        1
    } else {
        let digits = suffix.strip_prefix('-')?;
        let sequence: u64 = digits.parse().ok()?;
        if sequence < 2 || sequence.to_string() != digits {
            return None;
        }
        sequence
    };
    Some((date, sequence))
}

fn publish_directory(
    directory: &Path,
    extension: &str,
    keep: Option<NonZeroUsize>,
    bytes: &[u8],
    today: NaiveDate,
) -> Result<Published> {
    let mut candidates = Vec::new();
    let mut sequence = 0;
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        if !entry.file_type()?.is_file() {
            continue;
        }
        let name = entry.file_name();
        let Some((date, number)) = name.to_str().and_then(|name| backup_name(name, extension))
        else {
            continue;
        };
        if date == today {
            sequence = sequence.max(number);
        }
        candidates.push(((date, number), entry.path()));
    }
    let mut temporary = stage(directory, bytes)?;
    let path = loop {
        sequence = sequence
            .checked_add(1)
            .context("Auth backup filename suffix exhausted")?;
        let suffix = if sequence == 1 {
            String::new()
        } else {
            format!("-{sequence}")
        };
        let path = directory.join(format!("ente-auth-{today}{suffix}.{extension}"));
        match temporary.persist_noclobber(&path) {
            Ok(_) => break path,
            Err(error) if error.error.kind() == io::ErrorKind::AlreadyExists => {
                temporary = error.file
            }
            Err(error) => return Err(error.error).context("cannot publish Auth backup"),
        }
    };
    #[cfg(unix)]
    fs::File::open(directory)
        .and_then(|directory| directory.sync_all())
        .context("backup published, but cannot sync its directory; older backups were kept")?;
    let mut result = Published {
        path: Some(path),
        pruned: 0,
        prune_error: None,
    };
    if let Some(keep) = keep {
        candidates.sort_unstable_by_key(|candidate| std::cmp::Reverse(candidate.0));
        prune(
            candidates
                .into_iter()
                .skip(keep.get() - 1)
                .map(|(_, path)| path),
            &mut result,
        );
    }
    Ok(result)
}

fn prune(paths: impl Iterator<Item = PathBuf>, result: &mut Published) {
    for path in paths {
        match fs::remove_file(&path) {
            Ok(()) => result.pruned += 1,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                result.prune_error = Some(
                    anyhow::Error::new(error)
                        .context(format!("backup saved, but cannot prune {}", path.display())),
                );
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn publication_allocates_dates_and_prunes_only_its_format() {
        let directory = tempfile::tempdir().unwrap();
        let today = NaiveDate::from_ymd_opt(2026, 10, 8).unwrap();
        let publish = |day, extension, keep| {
            publish_directory(
                directory.path(),
                extension,
                NonZeroUsize::new(keep),
                b"complete",
                day,
            )
            .unwrap()
        };
        for suffix in ["", "-2", "-3"] {
            let result = publish(today, "json", 0);
            assert_eq!(
                result.path.unwrap().file_name().unwrap(),
                format!("ente-auth-2026-10-08{suffix}.json").as_str()
            );
            assert_eq!(result.pruned, 0);
        }
        for name in [
            "unrelated.json",
            "ente-auth-2026-10-08-01.json",
            "ente-auth-2026-10-08-1.json",
            "ente-auth-2026-02-30.json",
        ] {
            fs::write(directory.path().join(name), b"untouched").unwrap();
        }
        let text = publish(today, "txt", 1).path.unwrap();
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 8);
        let next_day = today.succ_opt().unwrap();
        let result = publish(next_day, "json", 2);
        assert_eq!(result.pruned, 2);
        assert_eq!(
            result.path.unwrap().file_name().unwrap(),
            "ente-auth-2026-10-09.json"
        );
        assert!(
            directory
                .path()
                .join("ente-auth-2026-10-08-3.json")
                .exists()
        );
        assert!(text.exists());
        let result = publish(today, "txt", 1);
        assert_eq!(result.pruned, 1);
        assert!(!text.exists());
        assert!(directory.path().join("ente-auth-2026-10-09.json").exists());
        let earlier_day = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
        let result = publish(earlier_day, "json", 1);
        assert_eq!(result.pruned, 2);
        assert!(result.path.unwrap().exists());
        for name in [
            "unrelated.json",
            "ente-auth-2026-10-08-01.json",
            "ente-auth-2026-10-08-1.json",
            "ente-auth-2026-02-30.json",
        ] {
            assert_eq!(fs::read(directory.path().join(name)).unwrap(), b"untouched");
        }
    }

    #[test]
    fn exact_publication_refuses_a_path_created_after_preflight() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("output");
        let destination = Destination::File(path.clone());
        destination.prepare().unwrap();
        fs::write(&path, b"concurrent writer").unwrap();
        assert!(destination.publish(b"replacement").is_err());
        assert_eq!(fs::read(&path).unwrap(), b"concurrent writer");
        #[cfg(unix)]
        {
            let link = directory.path().join("symlink");
            std::os::unix::fs::symlink(directory.path().join("missing"), &link).unwrap();
            assert!(Destination::File(link).prepare().is_err());
        }
        fs::create_dir(directory.path().join("ente-auth-2026-10-08.json")).unwrap();
        let result = publish_directory(
            directory.path(),
            "json",
            None,
            b"new",
            NaiveDate::from_ymd_opt(2026, 10, 8).unwrap(),
        )
        .unwrap();
        assert_eq!(
            result.path.unwrap().file_name().unwrap(),
            "ente-auth-2026-10-08-2.json"
        );
    }

    #[test]
    fn write_and_prune_failures_preserve_complete_backups() {
        let directory = tempfile::tempdir().unwrap();
        let old = directory.path().join("old");
        fs::write(&old, b"old").unwrap();
        let missing = Destination::File(directory.path().join("missing/new"));
        assert!(missing.publish(b"new").is_err());
        assert_eq!(fs::read(&old).unwrap(), b"old");
        let new = directory.path().join("new");
        let mut result = Destination::File(new.clone()).publish(b"new").unwrap();
        let replaced_candidate = directory.path().join("replaced");
        fs::create_dir(&replaced_candidate).unwrap();
        prune([old.clone(), replaced_candidate].into_iter(), &mut result);
        assert_eq!(result.pruned, 1);
        assert!(result.prune_error.is_some());
        assert_eq!(fs::read(new).unwrap(), b"new");
        assert!(!old.exists());
    }
}
