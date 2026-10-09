use std::{
    env,
    fs::{self, File, OpenOptions},
    io,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail, ensure};
use uuid::Uuid;

use crate::vault::{Account, State};

pub struct AccountHome {
    pub path: PathBuf,
    _lock: File,
}

pub struct RemovalGuard {
    _lock: File,
    home: AccountHome,
}

pub fn open_account(selected: Option<&str>, create: bool) -> Result<(Account, AccountHome)> {
    let state = State::load()?;
    let id = state.accounts[state.resolve(selected)?].storage_id;
    let home = lock_account(id, create)?;
    let Some(account) = State::load()?
        .accounts
        .into_iter()
        .find(|account| account.storage_id == id)
    else {
        home.for_removal()?.remove()?;
        bail!("account was removed while waiting for access");
    };
    if create {
        self::create(&home.path)?;
    }
    Ok((account, home))
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
    let home = account_home(id, create)?;
    home._lock.lock().context("cannot lock the account home")?;
    Ok(home)
}

pub fn try_lock_account(id: Uuid) -> Result<AccountHome> {
    let home = account_home(id, true)?;
    try_lock(&home._lock)?;
    Ok(home)
}

fn account_home(id: Uuid, create: bool) -> Result<AccountHome> {
    let accounts = application_home()?.join("accounts");
    let path = accounts.join(id.to_string());
    let lock_path = accounts.join(format!("{id}.lock"));
    if create {
        self::create(&accounts)?;
    } else {
        ensure!(path.is_dir(), "no local data; run the command online first");
    }
    let lock = open_lock(&lock_path).context("cannot open the account lock")?;
    Ok(AccountHome { path, _lock: lock })
}

impl AccountHome {
    pub fn storage_use(&self) -> Result<File> {
        let lock = open_lock(&self.path.with_extension("use.lock"))
            .context("cannot open the account use lock")?;
        lock.lock_shared().context("cannot lock account storage")?;
        Ok(lock)
    }

    pub fn for_removal(self) -> Result<RemovalGuard> {
        let lock = open_lock(&self.path.with_extension("use.lock"))
            .context("cannot open the account use lock")?;
        try_lock(&lock)?;
        Ok(RemovalGuard {
            _lock: lock,
            home: self,
        })
    }
}

impl RemovalGuard {
    pub fn remove(self) -> Result<()> {
        if let Err(error) = fs::remove_dir_all(&self.home.path)
            && error.kind() != io::ErrorKind::NotFound
        {
            return Err(error.into());
        }
        // The vault must exclude this account before its lock is unlinked.
        for extension in ["use.lock", "lock"] {
            if let Err(error) = fs::remove_file(self.home.path.with_extension(extension))
                && error.kind() != io::ErrorKind::NotFound
            {
                return Err(error.into());
            }
        }
        Ok(())
    }
}

fn try_lock(lock: &File) -> Result<()> {
    match lock.try_lock() {
        Ok(()) => Ok(()),
        Err(fs::TryLockError::WouldBlock) => {
            bail!("account is in use; finish or cancel active commands before logging out")
        }
        Err(fs::TryLockError::Error(error)) => Err(error).context("cannot lock the account"),
    }
}

fn open_lock(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}
