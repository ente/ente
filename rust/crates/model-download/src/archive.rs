use std::fs;
use std::fs::File;
use std::path::Path;

use flate2::read::GzDecoder;
use tar::Archive;

use crate::download;

pub(crate) fn extract_tar_gz(
    archive_path: &Path,
    staging_dir: &Path,
    dest_dir: &Path,
) -> Result<(), download::Error> {
    if staging_dir.exists() {
        fs::remove_dir_all(staging_dir)?;
    }
    fs::create_dir_all(staging_dir)?;

    let tar_gz = File::open(archive_path)?;
    let mut archive = Archive::new(GzDecoder::new(tar_gz));
    archive.unpack(staging_dir)?;

    let entries = fs::read_dir(staging_dir)?.flatten().collect::<Vec<_>>();
    let source = match entries.as_slice() {
        [only] if only.path().is_dir() => only.path(),
        _ => staging_dir.to_path_buf(),
    };
    if dest_dir.exists() {
        fs::remove_dir_all(dest_dir)?;
    }
    fs::rename(&source, dest_dir)?;
    let _ = fs::remove_dir_all(staging_dir);
    Ok(())
}
