use std::{
    env,
    fs::{self, File, OpenOptions},
    io,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, ensure};
use uuid::Uuid;

pub struct AccountHome {
    pub path: PathBuf,
    _lock: File,
}

pub fn application_home() -> Result<PathBuf> {
    if let Some(home) = env::var_os("ENTE_CLI_HOME") {
        ensure!(!home.is_empty(), "ENTE_CLI_HOME cannot be empty");
        return Ok(home.into());
    }
    Ok(dirs::data_local_dir()
        .context("cannot find the application data directory; set ENTE_CLI_HOME")?
        .join("ente-cli"))
}

pub fn create(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    use std::os::unix::fs::{DirBuilderExt, PermissionsExt};

    let mut builder = fs::DirBuilder::new();
    builder.recursive(true);
    #[cfg(unix)]
    builder.mode(0o700);
    builder.create(path)?;
    #[cfg(unix)]
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

pub fn lock_account(id: Uuid, create: bool) -> Result<AccountHome> {
    let accounts = application_home()?.join("accounts");
    let path = accounts.join(id.to_string());
    let lock_path = accounts.join(format!("{id}.lock"));
    if create {
        self::create(&accounts)?;
    } else {
        ensure!(path.is_dir(), "no local data; run the command online first");
    }
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let lock = options
        .open(lock_path)
        .context("cannot open the account lock")?;
    lock.lock().context("cannot lock the account home")?;
    Ok(AccountHome { path, _lock: lock })
}

impl AccountHome {
    pub fn remove(self) -> Result<()> {
        if let Err(error) = fs::remove_dir_all(&self.path)
            && error.kind() != io::ErrorKind::NotFound
        {
            return Err(error.into());
        }
        // The vault must exclude this account before its lock is unlinked.
        if let Err(error) = fs::remove_file(self.path.with_extension("lock"))
            && error.kind() != io::ErrorKind::NotFound
        {
            return Err(error.into());
        }
        Ok(())
    }
}
