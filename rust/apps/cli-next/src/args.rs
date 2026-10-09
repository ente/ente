use std::{io::IsTerminal, num::NonZeroUsize, path::PathBuf};

use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};

#[derive(Parser)]
#[command(
    version,
    about = "Use Ente from the command line",
    override_usage = "ente-cli-next [OPTIONS] <COMMAND>",
    after_help = "Photos:
  ente-cli-next photos login
  ente-cli-next photos album list
  ente-cli-next photos file list --album <ID>
  ente-cli-next photos export <DIR>
Auth backups:
  ente-cli-next auth login
  ente-cli-next auth export <DIR>"
)]
pub struct Cli {
    #[command(flatten)]
    pub options: Options,
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Args)]
pub struct Options {
    #[arg(long, global = true, help = "Print the result as JSON")]
    pub json: bool,
    #[arg(long, global = true, help = "Use local data without network access")]
    pub offline: bool,
    #[arg(long, global = true, help = "Disable interactive prompts")]
    pub no_input: bool,
}

impl Options {
    pub fn can_prompt(&self) -> bool {
        !self.no_input && std::io::stdin().is_terminal() && std::io::stderr().is_terminal()
    }
}

pub const DEFAULT_LIST_LIMIT: u32 = 100;

#[derive(Args)]
pub struct ListArgs {
    #[arg(
        long,
        default_value_t = DEFAULT_LIST_LIMIT,
        value_parser = clap::value_parser!(u32).range(1..),
        help = "Maximum number of results; does not limit metadata refresh"
    )]
    pub limit: u32,
    #[arg(long, conflicts_with = "limit", help = "List every result")]
    pub all: bool,
}

impl ListArgs {
    pub fn limit(&self) -> Option<u32> {
        (!self.all).then_some(self.limit)
    }
}

#[derive(Args)]
pub struct AccountSelector {
    #[arg(
        long,
        global = true,
        value_name = "NAME",
        help = "Use this account instead of the selected one"
    )]
    pub account: Option<String>,
}

#[derive(Subcommand)]
pub enum Command {
    #[command(about = "Manage Ente Photos")]
    Photos {
        #[command(flatten)]
        selector: AccountSelector,
        #[command(subcommand)]
        command: PhotosCommand,
    },
    #[command(about = "Manage Locker sessions and make API requests")]
    Locker {
        #[command(flatten)]
        selector: AccountSelector,
        #[command(subcommand)]
        command: SessionCommand,
    },
    #[command(about = "Manage Ente Auth")]
    Auth {
        #[command(flatten)]
        selector: AccountSelector,
        #[command(subcommand)]
        command: AuthCommand,
    },
    #[command(about = "Manage accounts on this device", alias = "account")]
    Accounts {
        #[command(subcommand)]
        command: AccountCommand,
    },
    #[command(
        about = "Generate a vault key for unattended use",
        after_help = "Environment:
  ENTE_CLI_HOME       Directory containing the encrypted vault.
  ENTE_CLI_VAULT_KEY  Base64 key from `vault key generate`; bypasses the OS keychain.

Keep the same home and key across unattended invocations."
    )]
    Vault {
        #[command(subcommand)]
        command: VaultCommand,
    },
}

#[derive(Subcommand)]
pub enum AuthCommand {
    #[command(flatten)]
    Session(SessionCommand),
    #[command(about = "Export your Auth codes; encrypted by default")]
    #[command(
        after_long_help = "Refreshes Auth data first; --offline uses previously synced data.
Set ENTE_CLI_EXPORT_PASSWORD for encrypted export with --no-input.
DIR receives dated backups. --output writes a new file, or backup bytes to stdout with -.
--json formats file/directory summaries; stdout backups contain only the artifact."
    )]
    Export(AuthExportArgs),
    #[command(about = "Decrypt an Auth export without an account")]
    #[command(
        after_long_help = "Reads a backup without network access. Set ENTE_CLI_EXPORT_PASSWORD with --no-input.
Writes readable URI lines to stdout, or a new --output file. --json only formats the file summary."
    )]
    Decrypt {
        #[arg(value_name = "PATH", help = "Encrypted Auth backup to decrypt")]
        input: PathBuf,
        #[arg(
            long,
            value_name = "PATH|-",
            help = "Write to a new file; defaults to stdout"
        )]
        output: Option<PathBuf>,
    },
}

#[derive(Args)]
pub struct AuthExportArgs {
    #[arg(
        value_name = "DIR",
        required_unless_present = "output",
        conflicts_with = "output",
        help = "Directory for dated backups"
    )]
    pub directory: Option<PathBuf>,
    #[arg(
        long,
        value_name = "PATH|-",
        help = "Write to a new file, or stdout with -"
    )]
    pub output: Option<PathBuf>,
    #[arg(long, help = "Export readable URI lines without encryption")]
    pub plaintext: bool,
}

#[derive(Subcommand)]
pub enum PhotosCommand {
    #[command(flatten)]
    Session(SessionCommand),
    #[command(flatten)]
    Library(PhotosLibraryCommand),
}

#[derive(Subcommand)]
pub enum PhotosLibraryCommand {
    #[command(about = "Maintain an independent copy of your Photos library")]
    #[command(
        after_long_help = "Refreshes metadata and downloads originals to DESTINATION; requires network access.
Progress goes to stderr; the result goes to stdout. Use --json for a structured result."
    )]
    Export(ExportArgs),
    #[command(about = "Manage albums")]
    Album {
        #[command(subcommand)]
        command: AlbumCommand,
    },
    #[command(about = "Manage files")]
    File {
        #[arg(
            long,
            global = true,
            value_name = "ALBUM",
            help = "Limit to an album ID or exact name"
        )]
        album: Option<String>,
        #[command(subcommand)]
        command: FileCommand,
    },
}

#[derive(Args)]
pub struct ExportArgs {
    #[arg(
        long,
        value_name = "ALBUM",
        help = "Include an album ID or exact name; repeat for multiple albums"
    )]
    pub album: Vec<String>,
    #[arg(long, value_name = "ALBUM", help = "Exclude an album ID or exact name")]
    pub exclude_album: Vec<String>,
    #[arg(
        long,
        help = "Take over an old CLI/Desktop export or reconnect an existing one"
    )]
    pub adopt: bool,
    #[arg(
        long,
        short = 'j',
        value_name = "N",
        default_value = "16",
        help = "Maximum number of files processed concurrently"
    )]
    pub jobs: NonZeroUsize,
    #[arg(value_name = "DESTINATION", help = "Directory for the Photos export")]
    pub destination: PathBuf,
}

#[derive(Subcommand)]
pub enum SessionCommand {
    #[command(
        about = "Log in",
        after_help = "Non-interactive login reads JSON from --input:
  {\"email\": \"...\", \"password\": \"...\", \"otp\": \"123456\", \"totp\": \"654321\"}

All fields are strings. otp is the email code; totp is the authenticator code. Supply them when required.
With --no-input, supply email and password through --input PATH or --input -.
For unattended vault access, set ENTE_CLI_VAULT_KEY (see vault --help)."
    )]
    Login(LoginArgs),
    #[command(about = "Log out")]
    Logout,
    #[command(
        about = "Make an authenticated API request",
        after_help = "The response body is written unchanged, including when --json is set."
    )]
    Api(ApiArgs),
}

#[derive(Args)]
pub struct LoginArgs {
    #[arg(
        long,
        conflicts_with = "account",
        help = "Ente server to log in to; defaults to api.ente.com"
    )]
    pub host: Option<String>,
    #[arg(
        long,
        conflicts_with = "account",
        help = "Name for a new account on this device; defaults to the account's email"
    )]
    pub name: Option<String>,
    #[arg(
        long,
        help = "Read login credentials as JSON from this file, or from stdin with -"
    )]
    pub input: Option<PathBuf>,
}

#[derive(Args)]
pub struct ApiArgs {
    #[arg(help = "API path or URL at the selected account's server")]
    pub path: String,
    #[arg(long, default_value = "GET", help = "HTTP method")]
    pub method: String,
    #[arg(
        long,
        value_name = "NAME=VALUE",
        help = "Append a query parameter; repeat for multiple values"
    )]
    pub query: Vec<String>,
    #[arg(
        long,
        help = "Read a JSON object of headers from this file, or from stdin with -"
    )]
    pub headers: Option<PathBuf>,
    #[arg(
        long,
        help = "Read the request body from this file, or from stdin with -"
    )]
    pub body: Option<PathBuf>,
}

const ALBUM_HELP: &str = "Refreshes album metadata first; --offline reads previously synced data.
With --json, list returns an array and view returns one object.
Fields: id, name, type, visibility, ownerId (strings); updatedAt (RFC3339 timestamp string).";

#[derive(Subcommand)]
pub enum AlbumCommand {
    #[command(about = "List your albums, including shared and hidden ones")]
    #[command(after_long_help = ALBUM_HELP)]
    List(ListArgs),
    #[command(about = "Show an album")]
    #[command(after_long_help = ALBUM_HELP)]
    View {
        #[arg(help = "Album ID or exact name")]
        album: String,
    },
}

const FILE_HELP: &str = "Refreshes file metadata first; --offline reads previously synced data.
Use --album to limit the albums read. With --json, list returns an array and view returns one object.
Fields: id, name, type, ownerId (strings); albumIds (string array);
createdAt, updatedAt (RFC3339 timestamp strings).
Nullable fields: modifiedAt (RFC3339 string); location ({latitude, longitude}, numbers);
caption, hash, dateTime, offsetTime, visibility (strings); durationSeconds, width, height (integers).
dateTime and offsetTime retain the stored metadata strings.";

#[derive(Subcommand)]
pub enum FileCommand {
    #[command(about = "List files, including shared and hidden ones")]
    #[command(after_long_help = FILE_HELP)]
    List(ListArgs),
    #[command(about = "Show a file's metadata")]
    #[command(after_long_help = FILE_HELP)]
    View {
        #[arg(help = "File ID or exact name")]
        file: String,
    },
    #[command(about = "Download an original; Live Photos are saved as ZIP archives")]
    #[command(
        after_long_help = "Refreshes metadata and downloads to a new --output file; requires network access."
    )]
    Download {
        #[arg(help = "File ID or exact name")]
        file: String,
        #[arg(long, value_name = "PATH", help = "Write to this new file")]
        output: PathBuf,
    },
}

const ACCOUNT_HELP: &str = "Reads accounts stored on this device without network access.
With --json, list returns an array and view returns one object.
Fields: id, name, email, host (strings); products (string array); selected (boolean).";

#[derive(Subcommand)]
pub enum AccountCommand {
    #[command(about = "List accounts on this device")]
    #[command(after_long_help = ACCOUNT_HELP)]
    List,
    #[command(about = "Show an account")]
    #[command(after_long_help = ACCOUNT_HELP)]
    View {
        #[arg(help = "Account name")]
        name: String,
    },
    #[command(about = "Make an account the selected one")]
    Switch {
        #[arg(help = "Account name")]
        name: String,
    },
    #[command(about = "Change an account's local name")]
    Rename {
        #[arg(help = "Account name")]
        name: String,
        #[arg(help = "New local name")]
        new_name: String,
    },
    #[command(about = "Log out of every product and remove the account from this device")]
    Logout {
        #[arg(help = "Account name")]
        name: String,
        #[arg(
            long,
            help = "Forget the account on this device without logging out on the server"
        )]
        local: bool,
    },
}

#[derive(Subcommand)]
pub enum VaultCommand {
    #[command(about = "Work with the vault key")]
    Key {
        #[command(subcommand)]
        command: KeyCommand,
    },
}

#[derive(Subcommand)]
pub enum KeyCommand {
    #[command(about = "Print a new vault key for ENTE_CLI_VAULT_KEY")]
    Generate,
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Product {
    Photos,
    Locker,
    Auth,
}

impl Product {
    pub fn name(self) -> &'static str {
        match self {
            Self::Photos => "photos",
            Self::Locker => "locker",
            Self::Auth => "auth",
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Photos => "Ente Photos",
            Self::Locker => "Ente Locker",
            Self::Auth => "Ente Auth",
        }
    }

    pub fn client_package(self) -> &'static str {
        match self {
            Self::Photos => "io.ente.photos",
            Self::Locker => "io.ente.locker",
            Self::Auth => "io.ente.auth",
        }
    }
}
