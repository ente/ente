use std::{
    fs,
    io::{self, Write},
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
    },
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
                    Err(error) => {
                        return Err(error)
                            .with_context(|| format!("cannot inspect output {}", path.display()));
                    }
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
                let mut missing = Vec::new();
                for directory in path.ancestors() {
                    if directory.as_os_str().is_empty()
                        || directory.try_exists().with_context(|| {
                            format!("cannot inspect export directory {}", directory.display())
                        })?
                    {
                        break;
                    }
                    missing.push(directory);
                }
                let mut builder = fs::DirBuilder::new();
                builder.recursive(true);
                #[cfg(unix)]
                {
                    use std::os::unix::fs::DirBuilderExt;
                    builder.mode(0o700);
                }
                builder.create(path).with_context(|| {
                    format!("cannot create export directory {}", path.display())
                })?;
                for directory in missing.into_iter().rev() {
                    sync_directory(parent(directory)).with_context(|| {
                        format!(
                            "cannot sync parent of export directory {}",
                            directory.display()
                        )
                    })?;
                }
                Ok(())
            }
        }
    }

    pub fn publish(&self, bytes: &[u8]) -> Result<Option<PathBuf>> {
        match self {
            Self::Stdout => {
                let mut stdout = io::stdout().lock();
                stdout.write_all(bytes)?;
                stdout.flush()?;
                Ok(None)
            }
            Self::File(path) => {
                stage(parent(path), bytes)
                    .with_context(|| format!("cannot prepare output {}", path.display()))?
                    .persist_noclobber(path)
                    .map_err(|error| error.error)
                    .with_context(|| format!("cannot publish {}", path.display()))?;
                sync_directory(parent(path)).with_context(|| {
                    format!(
                        "{} was published, but cannot sync its directory",
                        path.display()
                    )
                })?;
                Ok(Some(path.clone()))
            }
            Self::Directory { path, extension } => {
                publish_directory(path, extension, bytes, Local::now().date_naive())
                    .map(Some)
                    .with_context(|| format!("Auth backup directory {}", path.display()))
            }
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

fn sync_directory(_directory: &Path) -> io::Result<()> {
    #[cfg(unix)]
    fs::File::open(_directory)?.sync_all()?;
    Ok(())
}

fn backup_sequence(name: &str, stem: &str, extension: &str) -> Option<u64> {
    let suffix = name.strip_prefix(stem)?.strip_suffix(extension)?;
    if suffix.is_empty() {
        Some(1)
    } else {
        let digits = suffix.strip_prefix('-')?;
        let sequence: u64 = digits.parse().ok()?;
        (sequence >= 2 && sequence.to_string() == digits).then_some(sequence)
    }
}

fn publish_directory(
    directory: &Path,
    extension: &str,
    bytes: &[u8],
    today: NaiveDate,
) -> Result<PathBuf> {
    let stem = format!("ente-auth-{today}");
    let extension = format!(".{extension}");
    let mut sequence = 0;
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let name = entry.file_name();
        if let Some(number) = name
            .to_str()
            .and_then(|name| backup_sequence(name, &stem, &extension))
        {
            sequence = sequence.max(number);
        }
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
        let path = directory.join(format!("{stem}{suffix}{extension}"));
        match temporary.persist_noclobber(&path) {
            Ok(_) => break path,
            Err(error) if error.error.kind() == io::ErrorKind::AlreadyExists => {
                temporary = error.file
            }
            Err(error) => return Err(error.error).context("cannot publish Auth backup"),
        }
    };
    sync_directory(directory).context("backup published, but cannot sync its directory")?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn publication_allocates_dates_and_preserves_earlier_files() {
        let directory = tempfile::tempdir().unwrap();
        let today = NaiveDate::from_ymd_opt(2026, 10, 8).unwrap();
        let publish = |day, extension| {
            publish_directory(directory.path(), extension, b"complete", day).unwrap()
        };
        for suffix in ["", "-2", "-3"] {
            let path = publish(today, "json");
            assert_eq!(
                path.file_name().unwrap(),
                format!("ente-auth-2026-10-08{suffix}.json").as_str()
            );
            assert_eq!(fs::read(path).unwrap(), b"complete");
        }
        let earlier = directory.path().join("ente-auth-2026-10-08-9.json");
        fs::write(&earlier, b"earlier").unwrap();
        assert_eq!(
            publish(today, "json").file_name().unwrap(),
            "ente-auth-2026-10-08-10.json"
        );
        assert_eq!(
            publish(today, "txt").file_name().unwrap(),
            "ente-auth-2026-10-08.txt"
        );
        assert_eq!(
            publish(today.succ_opt().unwrap(), "json")
                .file_name()
                .unwrap(),
            "ente-auth-2026-10-09.json"
        );
        assert_eq!(fs::read(earlier).unwrap(), b"earlier");
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 7);
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
        let path = publish_directory(
            directory.path(),
            "json",
            b"new",
            NaiveDate::from_ymd_opt(2026, 10, 8).unwrap(),
        )
        .unwrap();
        assert_eq!(path.file_name().unwrap(), "ente-auth-2026-10-08-2.json");
    }

    #[test]
    fn write_failure_preserves_earlier_backup() {
        let directory = tempfile::tempdir().unwrap();
        let old = directory.path().join("old");
        fs::write(&old, b"old").unwrap();
        let missing = Destination::File(directory.path().join("missing/new"));
        assert!(missing.publish(b"new").is_err());
        assert_eq!(fs::read(&old).unwrap(), b"old");
    }
}
