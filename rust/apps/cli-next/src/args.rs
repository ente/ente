use std::{io::IsTerminal, num::NonZeroUsize, path::PathBuf};

use clap::{Arg, ArgAction, Args, CommandFactory, Parser, Subcommand, ValueEnum};
use clap_complete::Shell;
use serde::{Deserialize, Serialize};

#[derive(Parser)]
#[command(version, about = "Ente client for terminals and agents")]
pub struct Cli {
    #[command(flatten, next_help_heading = "Global options")]
    pub options: Options,
    #[command(subcommand)]
    pub command: Command,
}

pub fn command() -> clap::Command {
    let command = Cli::command().disable_help_subcommand(true);
    let help = help_command(&command)
        .name("help")
        .about("Print help for a command or topic")
        .disable_help_flag(false)
        .arg(
            Arg::new("all")
                .long("all")
                .action(ArgAction::SetTrue)
                .help("Print help for all commands"),
        )
        .subcommand(clap::Command::new("migration").about("Show changes from earlier CLI versions"))
        .subcommand(clap::Command::new("help").about("Show help options and topics"));
    command
        // Restore nested help after Clap propagates the root's setting.
        .mut_subcommands(|child| child.defer(|child| child.disable_help_subcommand(false)))
        .subcommand(help)
}

fn help_command(command: &clap::Command) -> clap::Command {
    clap::Command::new(command.get_name().to_owned())
        .about(command.get_about().cloned().unwrap_or_default())
        .aliases(command.get_all_aliases().map(str::to_owned))
        .hide(command.is_hide_set())
        .display_order(command.get_display_order())
        .disable_help_subcommand(true)
        .disable_help_flag(true)
        .subcommands(command.get_subcommands().map(help_command))
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
        !self.no_input
            && std::io::stderr().is_terminal()
            && (cfg!(unix) || std::io::stdin().is_terminal())
    }
}

pub const DEFAULT_LIST_LIMIT: u32 = 100;

#[derive(Args)]
pub struct ListArgs {
    #[arg(
        long,
        default_value_t = DEFAULT_LIST_LIMIT,
        value_parser = clap::value_parser!(u32).range(1..),
        help = "Maximum number of results shown"
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
    #[command(about = "Manage Ente Locker")]
    Locker {
        #[command(flatten)]
        selector: AccountSelector,
        #[command(subcommand)]
        command: LockerCommand,
    },
    #[command(about = "Manage Ente Auth")]
    Auth {
        #[command(flatten)]
        selector: AccountSelector,
        #[command(subcommand)]
        command: AuthCommand,
    },
    #[command(about = "Share text through one-time encrypted links")]
    Paste {
        #[command(subcommand)]
        command: PasteCommand,
    },
    #[command(about = "Manage Ente accounts", alias = "accounts")]
    Account {
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
    #[command(
        about = "Print a shell completion script",
        after_help = "Enable completion in the current shell, or add the commands to its startup file:
  Bash (~/.bashrc):
    eval \"$(ente-cli-next completion bash)\"
  Zsh (~/.zshrc):
    autoload -Uz compinit; compinit
    source <(ente-cli-next completion zsh)
  PowerShell ($PROFILE):
    ente-cli-next completion powershell | Out-String | Invoke-Expression
  Elvish (~/.config/elvish/rc.elv):
    eval (ente-cli-next completion elvish | slurp)

Fish loads a saved script on demand. Write it once, and again after upgrading:
  mkdir -p ~/.config/fish/completions
  ente-cli-next completion fish > ~/.config/fish/completions/ente-cli-next.fish

Prints the script to stdout, including when --json is set."
    )]
    Completion { shell: Shell },
    #[command(about = "Administer an Ente server", after_long_help = ADMIN_HELP)]
    Admin {
        #[command(flatten)]
        selector: AccountSelector,
        #[arg(
            long,
            global = true,
            value_enum,
            help = "Saved app login; defaults to the only app, otherwise Photos"
        )]
        app: Option<App>,
        #[command(subcommand)]
        command: AdminCommand,
    },
}

#[derive(Subcommand)]
pub enum PasteCommand {
    #[command(
        about = "Create a one-time encrypted paste",
        after_long_help = "Supply TEXT or --input PATH; --input - reads stdin verbatim.
With neither, reads piped stdin.
Text cannot be blank. Limit: 4,000 characters; some emoji count as more than one.
Pastes expire after 24 hours.
With --password, uses ENTE_CLI_PASSWORD when set; otherwise prompts for a paste password and confirmation.
With --password --no-input, ENTE_CLI_PASSWORD is required.
Prints the paste URL. With --json: {\"url\": \"...\"}. Requires network access.

Example:
  ente-cli-next paste create --input notes.txt"
    )]
    Create {
        #[arg(
            conflicts_with = "input",
            help = "Literal paste text; defaults to piped stdin"
        )]
        text: Option<String>,
        #[arg(
            long,
            value_name = "PATH|-",
            help = "Read plain UTF-8 text from a file, or stdin with -"
        )]
        input: Option<PathBuf>,
        #[arg(long, help = "Require a password to decrypt the paste")]
        password: bool,
        #[arg(long, help = "Ente API server; defaults to api.ente.com")]
        host: Option<String>,
        #[arg(
            long,
            default_value = "https://paste.ente.com",
            value_name = "URL",
            help = "Website used in the returned link"
        )]
        paste_origin: url::Url,
    },
    #[command(
        about = "Read a paste and delete it from the server",
        after_long_help = "Supply a URL including its #key fragment, or TOKEN --key KEY.
Protected pastes use ENTE_CLI_PASSWORD when set; otherwise prompt for the paste password.
Deletes the server copy before decryption, even if the password or key is wrong.
A wrong ENTE_CLI_PASSWORD fails immediately; prompted retries work only while this command stays running.
Prints the text without adding a newline. Terminal controls are escaped except tabs and newlines.
With --json: {\"text\": \"...\"}. --raw affects plain terminal output only. Requires network access."
    )]
    Consume {
        #[arg(value_name = "URL|TOKEN", help = "Paste URL or access token")]
        link_or_token: String,
        #[arg(long, help = "Decryption key when passing an access token")]
        key: Option<String>,
        #[arg(long, help = "Print text verbatim even on a terminal")]
        raw: bool,
        #[arg(long, help = "Ente API server; defaults to api.ente.com")]
        host: Option<String>,
    },
}

#[derive(Subcommand)]
pub enum AuthCommand {
    #[command(about = "Make an authenticated API request", after_help = API_HELP)]
    Api(ApiArgs),
    #[command(about = "Find saved Auth codes and show their current values")]
    Code {
        #[command(subcommand)]
        command: CodeCommand,
    },
    #[command(about = "Export your Auth codes; encrypted by default")]
    #[command(
        after_long_help = "Refreshes Auth data first; --offline uses previously synced data.
Encrypted export uses ENTE_CLI_PASSWORD when set; otherwise prompts for an export password.
With --no-input, encrypted export requires ENTE_CLI_PASSWORD.
DIR receives dated backups. --output writes a new file, or backup bytes to stdout with -.
JSON summary fields: output, codes, failures.total. --json does not change backup contents.
Backups written to stdout have no summary.

Examples:
  ente-cli-next auth export ~/Backups/Auth
  ente-cli-next auth export --plaintext --output codes.txt"
    )]
    Export(AuthExportArgs),
    #[command(about = "Decrypt an Auth export without an account")]
    #[command(after_long_help = "Reads a backup without network access.
Uses ENTE_CLI_PASSWORD as the export password when set; otherwise prompts.
With --no-input, ENTE_CLI_PASSWORD is required.
Writes the decrypted backup to stdout, or a new --output file. --json only formats the file summary.")]
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

#[derive(Subcommand)]
pub enum CodeCommand {
    #[command(about = "List saved codes without their secrets or current values")]
    #[command(
        after_long_help = "Refreshes Auth data first; --offline uses previously synced data.
Search matches an ID, a displayed name, or words across issuer and account name, ignoring case.
Codes in Trash are not listed.
JSON fields: id, name, issuer, accountName, type (totp, hotp or steam)."
    )]
    List {
        #[arg(
            long,
            value_name = "TEXT",
            help = "Find codes by ID, displayed name or search words",
            value_parser = nonempty_query
        )]
        search: Option<String>,
        #[command(flatten)]
        list: ListArgs,
    },
    #[command(about = "Show one current TOTP or Steam code and its expiry")]
    #[command(
        after_long_help = "Refreshes Auth data first; --offline uses previously synced data.
An ID selects exactly. Otherwise match a name shown by list, or search words across issuer and account name.
Matching ignores case, and every search word must occur in either field.
Several matches fail and list candidates; narrow the search or use an ID.
Quote queries containing spaces.
A code in Trash must be restored in Ente Auth first.
JSON fields: id, name, issuer, accountName, type, otp, validUntil (UTC).
HOTP values are not supported yet.
Codes use your computer's clock. Make sure its date and time are correct.

Examples:
  ente-cli-next auth code view github
  ente-cli-next auth code view \"GitHub (alice@example.com)\""
    )]
    View {
        #[arg(
            help = "Code ID, displayed name or search words",
            value_parser = nonempty_query
        )]
        code: String,
    },
}

fn nonempty_query(query: &str) -> Result<String, String> {
    if query.trim().is_empty() {
        Err("supply a code ID or search text".into())
    } else {
        Ok(query.to_owned())
    }
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
    #[arg(long, help = "Export unencrypted otpauth:// links, one per line")]
    pub plaintext: bool,
}

#[derive(Subcommand)]
pub enum PhotosCommand {
    #[command(about = "Make an authenticated API request", after_help = API_HELP)]
    Api(ApiArgs),
    #[command(about = "Maintain an independent copy of your Photos library")]
    #[command(
        after_long_help = "Refreshes metadata and downloads originals to DESTINATION; requires network access.
Progress goes to stderr; the result goes to stdout. Use --json for a structured result.
JSON fields: output, complete, files, copies, changes, failures.
files counts distinct photos and videos; copies counts album copies (expected, completed, pending).
files and copies are null when the full export size could not be determined.
changes contains exported, metadataUpdated, renamed and movedToTrash counts; failures contains total and conflicts.

Examples:
  ente-cli-next photos export ~/Pictures/Ente
  ente-cli-next photos export ~/Pictures/Ente --album Holidays --account personal"
    )]
    Export(PhotosExportArgs),
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
pub struct PhotosExportArgs {
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
        help = "Exclude albums owned by other accounts",
        long_help = "Exclude albums owned by other accounts, including albums explicitly included with --album. Albums you own remain included when shared with others. Existing files in excluded albums are left unchanged. For removed albums, uses their last known ownership; if unknown, reports the export as incomplete. Applies only to this invocation."
    )]
    pub exclude_shared: bool,
    #[arg(
        long,
        help = "Exclude hidden albums, including the Hidden album",
        long_help = "Exclude albums hidden for this account, including the Hidden album and albums explicitly included with --album. Archived albums and individually hidden files in included albums remain included. Existing files in excluded albums are left unchanged. For removed albums, uses whether they were last seen as hidden; if unknown, reports the export as incomplete. Applies only to this invocation."
    )]
    pub exclude_hidden: bool,
    #[arg(
        long,
        help = "Take over an export from an earlier CLI or Ente Desktop, or reconnect one",
        long_help = "Take over an export made by an earlier CLI version or Ente Desktop, or reconnect an export after moving it or losing this CLI's local data. Taking over an earlier export requires filters to select exactly its recorded albums. Reconnecting checks the whole export before applying filters."
    )]
    pub adopt: bool,
    #[arg(
        long,
        help = "Share originals across albums using hard links",
        long_help = "Share originals across albums using hard links. Replace unchanged copies in selected albums with links, reusing originals elsewhere in this export, including unselected albums and Trash. Linked files share contents, timestamps and permissions. Later runs without this flag keep existing links. Requires a filesystem that supports hard links. Otherwise, omit this flag to use copies."
    )]
    pub hardlinks: bool,
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
pub enum LockerCommand {
    #[command(about = "Make an authenticated API request", after_help = API_HELP)]
    Api(ApiArgs),
}

#[derive(Args)]
pub struct LoginArgs {
    #[arg(
        long = "account",
        value_name = "NAME",
        help = "Local account name; creates an entry if it does not exist"
    )]
    pub name: Option<String>,
    #[arg(long, help = "Email address to log in with")]
    pub email: Option<String>,
    #[arg(long, value_enum, help = "App to log in to")]
    pub app: App,
    #[arg(
        long,
        help = "Ente server; defaults to the saved account's server or api.ente.com"
    )]
    pub host: Option<String>,
    #[arg(
        long,
        help = "Read login credentials as JSON from this file, or from stdin with -"
    )]
    pub input: Option<PathBuf>,
}

#[derive(Args)]
pub struct CreateArgs {
    #[arg(
        long = "account",
        value_name = "NAME",
        help = "Local name for the new account; defaults to its email"
    )]
    pub name: Option<String>,
    #[arg(long, help = "Email address for the new account")]
    pub email: Option<String>,
    #[arg(long, value_enum, default_value = "photos", help = "App to log in to")]
    pub app: App,
    #[arg(long, help = "Ente server; defaults to api.ente.com")]
    pub host: Option<String>,
    #[arg(
        long,
        value_name = "PATH|-",
        help = "Read creation credentials as JSON from a file or stdin"
    )]
    pub input: Option<PathBuf>,
    #[arg(long, help = "Accept Ente's terms and privacy policy")]
    pub accept_terms: bool,
}

#[derive(Clone, Copy, ValueEnum, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum VerificationPurpose {
    Create,
    Login,
}

const API_HELP: &str = "The response body is written unchanged, including when --json is set.";

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
dateTime and offsetTime retain the stored metadata strings.
hash comes from Ente's stored metadata. For Live Photos, it can contain the image and video hashes separated by a colon.";

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
Fields: id, name, email, host (strings); apps (string array); selected (boolean).";

#[derive(Subcommand)]
pub enum AccountCommand {
    #[command(
        about = "Log an account into an app",
        after_long_help = "An existing name requires matching credentials; a new name creates a local entry.
Omit --account to use the selected account, or the only saved account.
With no saved accounts, creates an entry named after the authenticated email.
With several accounts and none selected, supply --account or use account switch.
A new entry becomes selected; logging into an existing entry keeps the selection.

Non-interactive login reads JSON from --input:
  {\"email\": \"...\", \"password\": \"...\", \"otp\": \"123456\", \"totp\": \"654321\"}

All fields are strings. Supply password and email; --email can supply the email instead.
Supply otp (email code) or totp (authenticator code) only when required.
Request an email code with account request-otp --email EMAIL --app APP --purpose login [--host URL].
Use the same email, app and server as login.
With --no-input, supply credentials through --input PATH or --input -.
For unattended vault access, set ENTE_CLI_VAULT_KEY (see vault --help).

Examples:
  ente-cli-next account login --app photos
  ente-cli-next account login --app auth --account personal"
    )]
    Login(LoginArgs),
    #[command(
        about = "Request an email verification code",
        after_long_help = "Requests one email and returns; success means the server accepted the request.
Use the same email, app and server when completing creation or login.
Defaults to creation; use --purpose login for an existing account."
    )]
    RequestOtp {
        #[arg(long, help = "Email address to verify")]
        email: Option<String>,
        #[arg(
            long,
            value_enum,
            default_value = "photos",
            help = "App requesting verification"
        )]
        app: App,
        #[arg(long, help = "Ente server; defaults to api.ente.com")]
        host: Option<String>,
        #[arg(
            long,
            value_enum,
            default_value = "create",
            help = "Reason for verification"
        )]
        purpose: VerificationPurpose,
    },
    #[command(
        about = "Create an Ente account",
        after_long_help = "Creates and selects a new account, named after its email unless --account is supplied.
Prompts for email, consent, verification code and password.
Unattended creation requires --accept-terms and --input with email, password and otp strings.
--email can supply the email instead.
Request the code first with account request-otp --email EMAIL [--app APP] [--host URL], using the same app and server as creation.
Repeating an unfinished creation resumes with its saved keys and the same password.
Terms: https://ente.io/terms  Privacy: https://ente.io/privacy
Print the recovery key later with account recovery-key."
    )]
    Create(CreateArgs),
    #[command(about = "List accounts on this device")]
    #[command(after_long_help = ACCOUNT_HELP)]
    List,
    #[command(about = "Show an account")]
    #[command(after_long_help = ACCOUNT_HELP)]
    View {
        #[arg(
            long = "account",
            value_name = "NAME",
            help = "Account name; defaults to the selected or only saved account"
        )]
        name: Option<String>,
    },
    #[command(about = "Print the saved API token for an account")]
    #[command(
        after_long_help = "Uses --account, otherwise the selected account, otherwise the only saved account.
With several accounts and none selected, supply --account or use account switch.
--app is required and selects that account's saved login.
Reads the saved token from the local vault without contacting the server or refreshing it.
This prints a secret and does not check whether the server still accepts it.
Plain output is padded URL-safe Base64 followed by a newline.
With --json, returns {\"token\":\"...\"}."
    )]
    Token {
        #[arg(
            long = "account",
            value_name = "NAME",
            help = "Account name; defaults to the selected or only saved account"
        )]
        name: Option<String>,
        #[arg(long, value_enum, help = "App whose token to print")]
        app: App,
    },
    #[command(about = "Make an account the selected one")]
    Switch {
        #[arg(help = "Account name")]
        name: String,
    },
    #[command(
        about = "Change an account's local name",
        after_help = "With one name, renames the selected or only account. With two, renames OLD_NAME to NEW_NAME."
    )]
    Rename {
        #[arg(
            value_name = "NAME",
            help = "New name, or current name when supplying two names"
        )]
        name: String,
        #[arg(value_name = "NEW_NAME", help = "New local name")]
        new_name: Option<String>,
    },
    #[command(
        about = "Log out of an app, or every app when --app is omitted",
        after_long_help = "Removes the local account and its cached data after its last app login is removed.
Without --app, logs out of all this account's saved app logins on this device.
--local removes the account and its cached data without contacting the server."
    )]
    Logout {
        #[arg(
            long = "account",
            value_name = "NAME",
            help = "Account name; defaults to the selected or only saved account"
        )]
        name: Option<String>,
        #[arg(
            long,
            value_enum,
            help = "App to log out of; defaults to every saved app"
        )]
        app: Option<App>,
        #[arg(
            long,
            conflicts_with = "app",
            help = "Forget the account on this device without logging out on the server"
        )]
        local: bool,
    },
    #[command(
        about = "Set up authenticator protection for your Ente account",
        after_long_help = "Protects account login, separate from codes stored in Ente Auth."
    )]
    Totp {
        #[command(flatten)]
        selector: AccountSelector,
        #[arg(
            long,
            global = true,
            value_enum,
            help = "Saved app login; defaults to the only app, otherwise Photos"
        )]
        app: Option<App>,
        #[command(subcommand)]
        command: TotpCommand,
    },
    #[command(
        about = "Print the saved 24-word recovery key",
        after_long_help = "Prints a secret from the local vault without network access.
With --json, returns {\"recoveryKey\":\"...\"}."
    )]
    RecoveryKey {
        #[arg(
            long = "account",
            value_name = "NAME",
            help = "Account name; defaults to the selected or only saved account"
        )]
        name: Option<String>,
    },
}

#[derive(Subcommand)]
pub enum TotpCommand {
    #[command(
        about = "Print a new authenticator setup secret",
        after_long_help = "Requires network access. The secret expires after ten minutes.
Add it to your authenticator, then run account totp enable --input PATH|- with secret and totp strings."
    )]
    Setup,
    #[command(
        about = "Confirm and enable authenticator protection",
        after_long_help = "Without --input, creates a setup secret and prompts for an authenticator code.
With --input, reads JSON containing secret from account totp setup and totp from your authenticator.
Requires network access. If confirmation is interrupted, run account totp status.
Verifying an authenticator code requires your computer's date and time to be correct."
    )]
    Enable {
        #[arg(
            long,
            value_name = "PATH|-",
            help = "Read secret and totp strings as JSON from a file or stdin"
        )]
        input: Option<PathBuf>,
    },
    #[command(
        about = "Show whether authenticator protection is enabled",
        after_long_help = "Checks the current setting on the server; requires network access.
JSON field: totpEnabled (boolean)."
    )]
    Status,
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

const ADMIN_HELP: &str =
    "Uses the selected account's server and saved login; the server grants administrator access.
Log in with: ente-cli-next account login --account NAME --app photos --host URL
--account selects a saved account by name; otherwise uses the selected or sole account.
--app selects its saved login; otherwise uses the only saved app, then Photos.
With multiple apps and no Photos login, supply --app.
Changes to users require confirmation; --yes approves them, --no-input only disables prompts.
All admin commands require network access. --json prints results, not prompts or errors.";

#[derive(Subcommand)]
pub enum AdminCommand {
    #[command(about = "Inspect and manage users")]
    User {
        #[command(subcommand)]
        command: AdminUserCommand,
    },
    #[command(about = "Test server email")]
    Email {
        #[command(subcommand)]
        command: AdminEmailCommand,
    },
}

#[derive(Subcommand)]
pub enum AdminUserCommand {
    #[command(
        about = "List users",
        after_long_help = "Requires a login less than ten minutes old.
Lists users in creation order. Fetches all users matching --since before applying --limit.
--since accepts YYYY-MM-DD (midnight UTC) or RFC3339 with a timezone.
JSON returns an array: id and email (strings), createdAt (RFC3339).

Example:
  ente-cli-next admin --account home user list --all --no-input --json"
    )]
    List {
        #[command(flatten)]
        list: ListArgs,
        #[arg(long, value_name = "WHEN", value_parser = crate::admin::parse_date, help = "Include users created strictly after this instant")]
        since: Option<i64>,
    },
    #[command(
        about = "Show a user's ID and subscription",
        after_long_help = "JSON returns id, email, createdAt and subscription.
subscription contains productId, storageBytes and expiresAt, or null when unavailable.
IDs are strings; timestamps are RFC3339; storageBytes is an integer.

Example:
  ente-cli-next admin --account home user view alice@example.com"
    )]
    View {
        #[arg(value_name = "USER", help = "User email or numeric ID")]
        user: String,
    },
    #[command(
        about = "Delete an account and schedule its data cleanup",
        after_long_help = "Deletes the account registered to the supplied email when the server processes the request.
Requires a login less than ten minutes old. Reports the deleted account's ID and whether the server cancelled the subscription."
    )]
    Delete {
        #[arg(help = "Email address of the account to delete")]
        email: String,
        #[arg(long, help = "Approve this change without prompting")]
        yes: bool,
    },
    #[command(
        about = "Disable authenticator-code two-factor authentication",
        after_long_help = "Requires a login less than ten minutes old. Does not change passkeys."
    )]
    DisableTotp(AdminTarget),
    #[command(
        about = "Remove all of a user's passkeys",
        after_long_help = "Does not change authenticator-code two-factor authentication."
    )]
    RemovePasskeys(AdminTarget),
    #[command(
        about = "Change a free plan's storage or expiry",
        after_long_help = "--no-limit sets 100 TB (100 × 1024^4 bytes) and expiry 100 calendar years from now.
Alternatively supply --storage, --expires or both; omitted values stay unchanged.
With neither, prompts to choose the preset or custom values. --no-input requires explicit values and --yes.
Sizes accept MB, GB and TB, case-insensitive, using powers of 1024; fractions are allowed.
Dates accept YYYY-MM-DD (00:00 UTC at the start of that date) or RFC3339 with a timezone.
Shows old and new limits before confirmation. Paid plans are rejected.

Example:
  ente-cli-next admin --account home user update-subscription alice@example.com --no-limit"
    )]
    UpdateSubscription(SubscriptionArgs),
}

#[derive(Args)]
pub struct AdminTarget {
    #[arg(value_name = "USER", help = "User email or numeric ID")]
    pub user: String,
    #[arg(long, help = "Approve this change without prompting")]
    pub yes: bool,
}

#[derive(Args)]
pub struct SubscriptionArgs {
    #[command(flatten)]
    pub target: AdminTarget,
    #[arg(long, conflicts_with_all = ["storage", "expires"], help = "Set 100 TB of storage and another 100 years")]
    pub no_limit: bool,
    #[arg(long, value_name = "SIZE", value_parser = crate::admin::parse_size, help = "Storage limit, e.g. 500GB or 1.5TB")]
    pub storage: Option<i64>,
    #[arg(long, value_name = "WHEN", value_parser = crate::admin::parse_date, help = "Expiry date or timestamp")]
    pub expires: Option<i64>,
}

#[derive(Subcommand)]
pub enum AdminEmailCommand {
    #[command(
        about = "Send a fixed test message through the server",
        after_long_help = "Reports request acceptance, not delivery. An unconfigured server may accept without sending.
The server's SMTP configuration can override the supplied sender."
    )]
    Test {
        #[arg(long, help = "Recipient email")]
        to: String,
        #[arg(long, help = "Sender email")]
        from: String,
        #[arg(long, default_value = "Ente", help = "Sender name")]
        from_name: String,
    },
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum App {
    Photos,
    Locker,
    Auth,
}

impl App {
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
