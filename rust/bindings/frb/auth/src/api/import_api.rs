use ente_auth::import as core;
use flutter_rust_bridge::frb;

pub struct ImportDisplay {
    pub pinned: bool,
    pub trashed: bool,
    pub last_used_at: i64,
    pub tap_count: i64,
    pub tags: Vec<String>,
    pub note: String,
    pub position: i64,
    pub icon_src: String,
    pub icon_id: String,
}

pub struct ImportedCode {
    pub uri: String,
    pub display: Option<ImportDisplay>,
}

pub struct ImportBatch {
    pub codes: Vec<ImportedCode>,
    pub skipped: u32,
}

pub struct GoogleMigration {
    pub codes: Vec<ImportedCode>,
    pub batch_id: i32,
    pub batch_size: i32,
    pub batch_index: i32,
}

pub enum ImportError {
    Invalid {
        message: String,
        entry: Option<String>,
    },
    PasswordRequired,
    IncorrectPassword,
    FileTooLarge {
        max_bytes: u64,
    },
}

#[frb(sync)]
pub fn parse_plain_text(content: String) -> Result<ImportBatch, ImportError> {
    core::parse_plain_text(&content)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_aegis(database: String) -> Result<ImportBatch, ImportError> {
    core::parse_aegis(&database)
        .map(Into::into)
        .map_err(Into::into)
}

pub fn import_aegis(input: String, password: Option<String>) -> Result<ImportBatch, ImportError> {
    core::import_aegis(&input, password.as_deref())
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_andotp(entries: String) -> Result<ImportBatch, ImportError> {
    core::parse_andotp(&entries)
        .map(Into::into)
        .map_err(Into::into)
}

pub fn import_andotp(input: Vec<u8>, password: Option<String>) -> Result<ImportBatch, ImportError> {
    core::import_andotp(&input, password.as_deref())
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_bitwarden(export: String) -> Result<ImportBatch, ImportError> {
    core::parse_bitwarden(&export)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_lastpass(export: String) -> Result<ImportBatch, ImportError> {
    core::parse_lastpass(&export)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_proton(export: String) -> Result<ImportBatch, ImportError> {
    core::parse_proton(&export)
        .map(Into::into)
        .map_err(Into::into)
}

pub fn import_proton(input: String, password: Option<String>) -> Result<ImportBatch, ImportError> {
    core::import_proton(&input, password.as_deref())
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_raivo(export: String) -> Result<ImportBatch, ImportError> {
    core::parse_raivo(&export)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_two_fas(
    export: String,
    decrypted_services: Option<String>,
) -> Result<ImportBatch, ImportError> {
    core::parse_two_fas(&export, decrypted_services.as_deref())
        .map(Into::into)
        .map_err(Into::into)
}

pub fn import_two_fas(input: String, password: Option<String>) -> Result<ImportBatch, ImportError> {
    core::import_two_fas(&input, password.as_deref())
        .map(Into::into)
        .map_err(Into::into)
}

pub fn import_open_authenticator(
    input: String,
    password: String,
) -> Result<ImportBatch, ImportError> {
    core::import_open_authenticator(&input, &password)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn validate_open_authenticator(input: String) -> Result<(), ImportError> {
    core::validate_open_authenticator(&input).map_err(Into::into)
}

pub fn import_otp_auth(input: Vec<u8>, password: String) -> Result<ImportBatch, ImportError> {
    core::import_otp_auth(&input, &password)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn parse_google_migration(input: String) -> Result<GoogleMigration, ImportError> {
    let migration = core::parse_google_migration(&input)?;
    Ok(GoogleMigration {
        codes: migration.batch.codes.into_iter().map(Into::into).collect(),
        batch_id: migration.batch_id,
        batch_size: migration.batch_size,
        batch_index: migration.batch_index,
    })
}

pub fn decrypt_ente_backup(input: Vec<u8>, password: String) -> Result<ImportBatch, ImportError> {
    core::decrypt_ente_backup(&input, &password)
        .map(Into::into)
        .map_err(Into::into)
}

#[frb(sync)]
pub fn validate_ente_backup(input: Vec<u8>) -> Result<(), ImportError> {
    core::validate_ente_backup(&input).map_err(Into::into)
}

impl std::fmt::Debug for ImportError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Invalid { message, entry } => formatter
                .debug_struct("Invalid")
                .field("message", message)
                .field("has_entry", &entry.is_some())
                .finish(),
            Self::PasswordRequired => formatter.write_str("PasswordRequired"),
            Self::IncorrectPassword => formatter.write_str("IncorrectPassword"),
            Self::FileTooLarge { max_bytes } => formatter
                .debug_struct("FileTooLarge")
                .field("max_bytes", max_bytes)
                .finish(),
        }
    }
}

impl From<core::Display> for ImportDisplay {
    fn from(display: core::Display) -> Self {
        Self {
            pinned: display.pinned,
            trashed: display.trashed,
            last_used_at: display.last_used_at,
            tap_count: display.tap_count,
            tags: display.tags,
            note: display.note,
            position: display.position,
            icon_src: display.icon_src,
            icon_id: display.icon_id,
        }
    }
}

impl From<core::ImportedCode> for ImportedCode {
    fn from(code: core::ImportedCode) -> Self {
        Self {
            uri: code.uri,
            display: code.display.map(Into::into),
        }
    }
}

impl From<core::Batch> for ImportBatch {
    fn from(batch: core::Batch) -> Self {
        Self {
            codes: batch.codes.into_iter().map(Into::into).collect(),
            skipped: batch.skipped,
        }
    }
}

impl From<core::Error> for ImportError {
    fn from(error: core::Error) -> Self {
        match error.kind() {
            core::ErrorKind::Invalid => Self::Invalid {
                message: error.message().to_owned(),
                entry: error.entry_text().map(ToOwned::to_owned),
            },
            core::ErrorKind::PasswordRequired => Self::PasswordRequired,
            core::ErrorKind::IncorrectPassword => Self::IncorrectPassword,
            core::ErrorKind::FileTooLarge { max_bytes } => Self::FileTooLarge { max_bytes },
        }
    }
}
