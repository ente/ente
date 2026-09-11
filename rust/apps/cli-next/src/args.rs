use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};

#[derive(Parser)]
#[command(
    version,
    about = "Use Ente from the command line",
    after_help = "Start with: ente-cli-next photos login"
)]
pub struct Cli {
    #[arg(long, global = true, help = "Print the result as JSON")]
    pub json: bool,
    #[command(subcommand)]
    pub command: Command,
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
    #[command(about = "Manage Ente Locker")]
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
        command: SessionCommand,
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
pub enum PhotosCommand {
    #[command(flatten)]
    Session(SessionCommand),
    #[command(about = "Manage albums")]
    Album {
        #[command(subcommand)]
        command: AlbumCommand,
    },
}

#[derive(Subcommand)]
pub enum SessionCommand {
    #[command(
        about = "Log in",
        after_help = "Non-interactive login reads JSON from --input:
  {\"email\": \"...\", \"password\": \"...\", \"otp\": \"123456\", \"totp\": \"654321\"}

otp is the email code. totp is the authenticator code. Include them only when required."
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

#[derive(Subcommand)]
pub enum AlbumCommand {
    #[command(about = "List your albums, including shared and hidden ones")]
    List,
}

#[derive(Subcommand)]
pub enum AccountCommand {
    #[command(about = "List accounts on this device")]
    List,
    #[command(about = "Show an account")]
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
