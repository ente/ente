use std::{
    fs::{self, File},
    io::{self, Read, Write},
    path::Path,
    time::{Duration, UNIX_EPOCH},
};

use anyhow::{Context, Result, ensure};
use ente_core::{
    b64,
    crypto::hash::{self, HashState},
};
use serde_json::Value;
use tokio::sync::watch;

use super::{names, store::Properties};

pub struct HashWriter {
    pub file: File,
    digest: HashState,
    pub size: u64,
    cancel: watch::Receiver<bool>,
}

impl HashWriter {
    pub fn new(file: File, cancel: &watch::Receiver<bool>) -> Result<Self> {
        Ok(Self {
            file,
            digest: HashState::new(Some(64), None)?,
            size: 0,
            cancel: cancel.clone(),
        })
    }

    pub fn finish(self) -> Result<(File, u64, String)> {
        self.file.sync_all()?;
        Ok((self.file, self.size, b64::encode(&self.digest.finalize()?)))
    }
}

impl Write for HashWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if *self.cancel.borrow() {
            return Err(io::Error::other(super::Cancelled));
        }
        let written = self.file.write(bytes)?;
        self.digest
            .update(&bytes[..written])
            .map_err(io::Error::other)?;
        self.size += written as u64;
        Ok(written)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

pub fn hash_cancellable(path: &Path, cancel: &watch::Receiver<bool>) -> Result<(u64, String)> {
    let mut file = File::open(path)?;
    let mut digest = HashState::new(Some(64), None)?;
    let mut bytes = vec![0u8; 64 * 1024];
    let mut size = 0;
    loop {
        ensure!(!*cancel.borrow(), super::Cancelled);
        let read = file.read(&mut bytes)?;
        if read == 0 {
            break;
        }
        digest.update(&bytes[..read])?;
        size += read as u64;
    }
    Ok((size, b64::encode(&digest.finalize()?)))
}

pub fn directory(root: &Path, relative: &str) -> Result<()> {
    let path = names::check(root, relative)?;
    match fs::symlink_metadata(&path) {
        Ok(meta) => ensure!(
            meta.is_dir(),
            super::Conflict(format!("expected directory at {}", path.display()))
        ),
        Err(error) if error.kind() == io::ErrorKind::NotFound => create_directory(&path)?,
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

pub fn create_directory(path: &Path) -> Result<()> {
    let mut missing = Vec::new();
    for directory in path.ancestors() {
        if directory.try_exists()? {
            break;
        }
        missing.push(directory);
    }
    fs::create_dir_all(path)?;
    for directory in missing.into_iter().rev() {
        sync_parent(directory)?;
    }
    Ok(())
}

pub fn set_time(path: &Path, micros: i64) -> Result<Properties> {
    let duration = Duration::from_micros(micros.unsigned_abs());
    let time = if micros >= 0 {
        UNIX_EPOCH.checked_add(duration)
    } else {
        UNIX_EPOCH.checked_sub(duration)
    }
    .context("media timestamp is outside filesystem range")?;
    File::options().write(true).open(path)?.set_modified(time)?;
    Properties::read(path)
}

pub fn sync_parent(_path: &Path) -> Result<()> {
    #[cfg(unix)]
    if let Some(parent) = _path.parent() {
        File::open(parent)?.sync_all()?;
    }
    Ok(())
}

pub fn sync_move(source: &Path, destination: &Path) -> Result<()> {
    if destination.parent().is_some_and(Path::exists) {
        sync_parent(destination)?;
    }
    if source.parent() != destination.parent() && source.parent().is_some_and(Path::exists) {
        sync_parent(source)?;
    }
    Ok(())
}

pub struct Json {
    pub value: Value,
    pub bytes: Vec<u8>,
    pub hash: String,
}

impl Json {
    pub fn new(value: Value) -> Result<Self> {
        let mut bytes = serde_json::to_vec_pretty(&value)?;
        bytes.push(b'\n');
        let hash = b64::encode(&hash::hash(&bytes, Some(64), None)?);
        Ok(Self { value, bytes, hash })
    }
}

pub fn matches(path: &Path, size: u64, hash: &str, cancel: &watch::Receiver<bool>) -> Result<bool> {
    let actual = hash_cancellable(path, cancel)?;
    Ok(actual.0 == size && actual.1 == hash)
}

pub fn remove(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    if path.parent().is_some_and(Path::exists) {
        sync_parent(path)?;
    }
    Ok(())
}
