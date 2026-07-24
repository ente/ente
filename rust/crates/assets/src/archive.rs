use std::fs;
use std::fs::File;
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};

use flate2::read::GzDecoder;
use tar::Archive;

use crate::download::{CancellationToken, Error};

pub(crate) fn extract_tar_gz(
    archive_path: &Path,
    staging_dir: &Path,
    cancellation: &CancellationToken,
) -> Result<PathBuf, Error> {
    if staging_dir.exists() {
        fs::remove_dir_all(staging_dir)?;
    }
    fs::create_dir_all(staging_dir)?;

    let tar_gz = File::open(archive_path)?;
    let mut archive = Archive::new(GzDecoder::new(tar_gz));
    for entry in archive.entries()? {
        if cancellation.is_cancelled() {
            return Err(Error::Cancelled);
        }
        let mut entry = entry?;
        let entry_type = entry.header().entry_type();
        if !entry_type.is_file() && !entry_type.is_dir() {
            return Err(Error::Validation(
                "tar archive contains a link or special file".to_string(),
            ));
        }
        let path = entry.path()?.into_owned();
        if path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        }) {
            return Err(Error::Validation(
                "tar archive contains an unsafe path".to_string(),
            ));
        }
        let destination = staging_dir.join(path);
        if entry_type.is_dir() {
            fs::create_dir_all(destination)?;
            continue;
        }
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut output = File::create(destination)?;
        let mut buffer = [0; 1024 * 1024];
        loop {
            if cancellation.is_cancelled() {
                return Err(Error::Cancelled);
            }
            let count = entry.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            output.write_all(&buffer[..count])?;
        }
    }

    let entries = fs::read_dir(staging_dir)?.collect::<Result<Vec<_>, _>>()?;
    if entries.is_empty() {
        return Err(Error::Validation("tar archive is empty".to_string()));
    }
    Ok(match entries.as_slice() {
        [only] if only.path().is_dir() => only.path(),
        _ => staging_dir.to_path_buf(),
    })
}
