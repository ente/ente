use std::{
    collections::BTreeMap,
    env,
    fs::{self, File, OpenOptions},
    io::{self, ErrorKind},
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail, ensure};
use ente_core::{
    b64,
    crypto::{Key, blob},
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::{ZeroizeOnDrop, Zeroizing};

use crate::{args::Product, parse_json};

const SCHEMA_VERSION: u8 = 1;
const VAULT_FILE: &str = "vault.json";

pub struct Vault {
    pub state: State,
    home: PathBuf,
    key: Key,
    _lock: File,
}

pub(crate) struct VaultAccess {
    home: PathBuf,
    key: Key,
}

#[derive(Default, Serialize, Deserialize)]
pub struct State {
    pub accounts: Vec<Account>,
    pub selected: Option<Uuid>,
}

#[derive(Serialize, Deserialize)]
struct VersionedState<T> {
    schema_version: u8,
    state: T,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct EncryptedVault {
    data: String,
}

#[derive(Serialize, Deserialize)]
pub struct Account {
    pub storage_id: Uuid,
    pub name: String,
    pub email: String,
    pub origin: String,
    pub user_id: i64,
    pub identity: AccountKeys,
    pub sessions: BTreeMap<Product, StoredSession>,
}

#[derive(Serialize, Deserialize, ZeroizeOnDrop)]
pub struct AccountKeys {
    pub master_key: Vec<u8>,
    pub recovery_key: Vec<u8>,
    pub secret_key: Vec<u8>,
}

#[derive(Serialize, Deserialize, ZeroizeOnDrop)]
pub struct StoredSession {
    pub token: Vec<u8>,
}

impl Vault {
    pub fn open() -> Result<Self> {
        let override_key = environment_key()?;
        let home = application_home()?;
        create_home(&home).context("cannot create private CLI home")?;
        let home = fs::canonicalize(home)?;
        let lock = lock(&home)?;
        let encrypted = read_vault(&home)?;
        let key = load_key(override_key, encrypted.is_some(), || {
            keyring::Entry::new("io.ente.cli", &home.to_string_lossy())
        })?;
        let state = match encrypted {
            Some(bytes) => decrypt(&bytes, &key)?,
            None => State::default(),
        };
        Ok(Self {
            state,
            home,
            key,
            _lock: lock,
        })
    }

    pub fn into_state(self) -> State {
        self.state
    }

    pub fn release(self) -> (State, VaultAccess) {
        let Self {
            state,
            home,
            key,
            _lock,
        } = self;
        drop(_lock);
        (state, VaultAccess { home, key })
    }

    pub fn save(&self) -> Result<()> {
        let plaintext = Zeroizing::new(serde_json::to_vec(&VersionedState {
            schema_version: SCHEMA_VERSION,
            state: &self.state,
        })?);
        let encrypted = blob::encrypt_combined(&plaintext, &self.key)
            .map_err(|_| anyhow::anyhow!("cannot encrypt the CLI vault"))?;
        let mut file = tempfile::NamedTempFile::new_in(&self.home)?;
        serde_json::to_writer(
            &mut file,
            &EncryptedVault {
                data: b64::encode(&encrypted),
            },
        )?;
        file.as_file().sync_all()?;
        file.persist(self.home.join(VAULT_FILE))?;
        #[cfg(unix)]
        if let Err(error) = File::open(&self.home).and_then(|dir| dir.sync_all()) {
            eprintln!("Warning: vault saved, but could not sync its directory: {error}");
        }
        Ok(())
    }
}

impl VaultAccess {
    pub fn open(self) -> Result<Vault> {
        let Self { home, key } = self;
        let lock = lock(&home)?;
        let state = match read_vault(&home)? {
            Some(bytes) => decrypt(&bytes, &key)?,
            None => State::default(),
        };
        Ok(Vault {
            state,
            home,
            key,
            _lock: lock,
        })
    }
}

impl State {
    pub fn load() -> Result<Self> {
        let override_key = environment_key()?;
        let home = application_home()?;
        // Atomic replacement makes the file a complete snapshot without a read lock.
        let Some(bytes) = read_vault(&home)? else {
            return Ok(Self::default());
        };
        let home = fs::canonicalize(home)?;
        let key = load_key(override_key, true, || {
            keyring::Entry::new("io.ente.cli", &home.to_string_lossy())
        })?;
        decrypt(&bytes, &key)
    }

    pub fn named(&self, name: &str) -> Result<usize> {
        self.accounts
            .iter()
            .position(|a| a.name == name)
            .with_context(|| format!("no account named {name:?}; use accounts list"))
    }

    pub fn resolve(&self, name: Option<&str>) -> Result<usize> {
        if let Some(name) = name {
            return self.named(name);
        }
        if let Some(index) = self
            .accounts
            .iter()
            .position(|a| Some(a.storage_id) == self.selected)
        {
            return Ok(index);
        }
        match self.accounts.len() {
            0 => bail!("no accounts; use photos login, locker login, or auth login"),
            1 => Ok(0),
            _ => bail!("no account selected; use accounts switch <name> or --account <name>"),
        }
    }

    pub fn check_name(&self, name: &str) -> Result<()> {
        ensure!(!name.trim().is_empty(), "account name cannot be empty");
        ensure!(
            !self.accounts.iter().any(|a| a.name == name),
            "account name {name:?} is already in use; choose another --name"
        );
        Ok(())
    }
}

impl Account {
    pub fn token(&self, product: Product) -> Result<&[u8]> {
        self.sessions
            .get(&product)
            .map(|s| s.token.as_slice())
            .with_context(|| {
                format!(
                    "account {:?} has no {} session; use {} login --account {:?}",
                    self.name,
                    product.name(),
                    product.name(),
                    self.name
                )
            })
    }
}

fn read_vault(home: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(home.join(VAULT_FILE)) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error).context("cannot read the CLI vault"),
    }
}

fn create_home(path: &Path) -> io::Result<()> {
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

fn lock(home: &Path) -> Result<File> {
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let lock = options.open(home.join("vault.lock"))?;
    lock.lock().context("cannot lock the CLI vault")?;
    Ok(lock)
}

fn application_home() -> Result<PathBuf> {
    if let Some(home) = env::var_os("ENTE_CLI_HOME") {
        ensure!(!home.is_empty(), "ENTE_CLI_HOME cannot be empty");
        return Ok(home.into());
    }
    Ok(dirs::data_local_dir()
        .context("cannot find the application data directory; set ENTE_CLI_HOME")?
        .join("ente-cli"))
}

fn environment_key() -> Result<Option<Key>> {
    match env::var("ENTE_CLI_VAULT_KEY") {
        Ok(value) => decode_key(&Zeroizing::new(value)).map(Some),
        Err(env::VarError::NotPresent) => Ok(None),
        Err(env::VarError::NotUnicode(_)) => {
            bail!("ENTE_CLI_VAULT_KEY must be standard padded base64 of exactly 32 bytes")
        }
    }
}

fn decode_key(value: &str) -> Result<Key> {
    let bytes = Zeroizing::new(b64::decode(value).map_err(|_| {
        anyhow::anyhow!("ENTE_CLI_VAULT_KEY must be standard padded base64 of exactly 32 bytes")
    })?);
    Key::try_from_slice(&bytes).context("ENTE_CLI_VAULT_KEY must decode to exactly 32 bytes")
}

fn load_key(
    override_key: Option<Key>,
    exists: bool,
    entry: impl FnOnce() -> keyring::Result<keyring::Entry>,
) -> Result<Key> {
    if let Some(key) = override_key {
        return Ok(key);
    }
    let entry = entry().map_err(|error| keyring_error(error, exists))?;
    match entry.get_secret() {
        Ok(bytes) => Key::try_from_slice(&Zeroizing::new(bytes))
            .context("system vault key is invalid; restore the original key"),
        Err(keyring::Error::NoEntry) if !exists => {
            let key = Key::generate();
            entry
                .set_secret(key.as_bytes())
                .map_err(|error| keyring_error(error, false))?;
            Ok(key)
        }
        Err(error) => Err(keyring_error(error, exists)),
    }
}

fn keyring_error(error: keyring::Error, exists: bool) -> anyhow::Error {
    let reason = match error {
        keyring::Error::NoEntry => "the vault key is missing".to_owned(),
        keyring::Error::NoStorageAccess(error) => {
            format!("access to system secret storage was denied: {error}")
        }
        keyring::Error::PlatformFailure(error) => format!("system secret storage failed: {error}"),
        keyring::Error::Ambiguous(_) => "multiple system vault keys match".to_owned(),
        _ => "system secret storage returned an invalid vault-key entry".to_owned(),
    };
    if exists {
        anyhow::anyhow!(
            "{reason}; restore system storage access or supply the original ENTE_CLI_VAULT_KEY"
        )
    } else {
        anyhow::anyhow!(
            "{reason}; use vault key generate, retain the key securely, and supply it through ENTE_CLI_VAULT_KEY"
        )
    }
}

fn decrypt(bytes: &[u8], key: &Key) -> Result<State> {
    let unlock_error =
        || anyhow::anyhow!("cannot unlock CLI vault: wrong key or damaged ciphertext");
    let encrypted: EncryptedVault =
        parse_json(bytes).context("unsupported or invalid CLI vault format")?;
    let ciphertext = b64::decode(&encrypted.data)
        .map_err(|_| anyhow::anyhow!("unsupported or invalid CLI vault format"))?;
    let plaintext =
        Zeroizing::new(blob::decrypt_combined(&ciphertext, key).map_err(|_| unlock_error())?);
    let version: VersionedState<serde::de::IgnoredAny> =
        parse_json(&plaintext).context("invalid CLI vault contents")?;
    ensure!(
        version.schema_version == SCHEMA_VERSION,
        "unsupported CLI vault schema"
    );
    let stored: VersionedState<State> =
        parse_json(&plaintext).context("invalid CLI vault contents")?;
    Ok(stored.state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_selection_never_replaces_an_existing_vault_key() {
        for exists in [false, true] {
            let key = Key::generate();
            let expected = Key::try_from_slice(key.as_bytes()).unwrap();
            assert_eq!(
                load_key(Some(key), exists, || panic!(
                    "environment override touched keyring"
                ))
                .unwrap(),
                expected
            );

            let entry = keyring::Entry::new_with_credential(Box::new(
                keyring::mock::MockCredential::default(),
            ));
            entry.set_secret(expected.as_bytes()).unwrap();
            assert_eq!(load_key(None, exists, || Ok(entry)).unwrap(), expected);
        }
        let entry = || {
            Ok(keyring::Entry::new_with_credential(Box::new(
                keyring::mock::MockCredential::default(),
            )))
        };
        assert!(load_key(None, false, entry).is_ok());
        let error = load_key(None, true, entry).unwrap_err().to_string();
        assert!(error.contains("original ENTE_CLI_VAULT_KEY"));
        assert!(!error.contains("generate"));

        for exists in [false, true] {
            let error = load_key(None, exists, || {
                Err(keyring::Error::NoStorageAccess(Box::new(
                    std::io::Error::from(ErrorKind::PermissionDenied),
                )))
            })
            .unwrap_err()
            .to_string();
            assert!(error.contains("denied"));
            assert_eq!(error.contains("generate"), !exists);
        }
    }
}
