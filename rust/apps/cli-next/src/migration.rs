use std::{ffi::OsString, io::Write};

use clap::{
    Command, Error,
    error::{ContextKind, ContextValue, ErrorKind},
};

struct Change {
    commands: &'static [&'static str],
    hint: Option<&'static str>,
    flags: &'static [(&'static [&'static str], &'static str)],
    guide: &'static str,
}

const CHANGES: &[Change] = &[
    Change {
        commands: &["account add", "account login"],
        hint: Some("'{command}' has been replaced by 'account login'.

For Photos:
  {binary} account login --app photos"),
        flags: &[
            (&["--password", "--otp", "--totp-code"], "Supply passwords and verification codes through prompts or --input PATH|-.
The JSON fields are email, password, otp (email code) and totp (authenticator code)."),
            (&["--endpoint"], "Use --host instead of --endpoint."),
            (&["--export-dir"], "Choose the destination when running {binary} photos export DIR or {binary} auth export DIR."),
            (&["--second-factor"], "Choose the second factor interactively, or supply totp in --input JSON. Passkey login is interactive."),
        ],
        guide: "Use {binary} account login --app APP [--email EMAIL] [--host URL].
Supply passwords and verification codes through prompts or --input PATH|-.

Use --account NAME to name a new local account or choose an existing one.",
    },
    Change {
        commands: &["account signup", "account create"],
        hint: Some("'{command}' has been replaced by 'account create'.

  {binary} account create"),
        flags: &[
            (&["--password", "--otp"], "Supply credentials through prompts or --input PATH|- with --accept-terms.
The JSON fields are email, password and otp (email code)."),
            (&["--endpoint"], "Use --host instead of --endpoint."),
            (&["--export-dir"], "Choose the destination when running {binary} photos export DIR or {binary} auth export DIR."),
            (&["--setup-2fa", "--totp-code"], "Run {binary} account totp enable after creation to set up authenticator protection.
For automation, run {binary} account totp setup, then {binary} account totp enable --input PATH|- with secret and totp strings."),
            (&["--show-recovery-key"], "Print the recovery key with {binary} account recovery-key."),
            (&["--source"], "--source has no equivalent."),
        ],
        guide: "Use {binary} account create [--email EMAIL] [--app APP] [--host URL]; the default app is Photos.
Supply credentials through prompts or --input PATH|- with --accept-terms.

For automation:
  {binary} account request-otp --email EMAIL
  {binary} account create --input PATH --accept-terms
The input JSON contains email, password and otp.",
    },
    Change {
        commands: &["account list"],
        hint: None,
        flags: &[],
        guide: "{binary} account list lists accounts saved on this computer.
Use {binary} account switch NAME to select one, or --account NAME on individual commands.",
    },
    Change {
        commands: &["account update"],
        hint: Some("export destinations are now supplied with each export command.

  {binary} photos export DIR --account NAME
  {binary} auth export DIR --account NAME"),
        flags: &[],
        guide: "Export destinations are now supplied on each invocation:
  {binary} photos export DIR --account NAME
  {binary} auth export DIR --account NAME
There is no saved export-directory setting.",
    },
    Change {
        commands: &["account get-token"],
        hint: Some("'{command}' has been replaced by 'account token'.

For Photos:
  {binary} account token --app photos"),
        flags: &[],
        guide: "Use {binary} account token --app APP [--account NAME].

--app is required. --account selects a local name, not an email lookup.
Omit --account to use the selected or only saved account.",
    },
    Change {
        commands: &["account two-factor", "account 2fa"],
        hint: Some("'{command}' has been replaced by 'account totp enable'.

  {binary} account totp enable"),
        flags: &[],
        guide: "Use {binary} account totp enable [--account NAME] [--app APP] interactively.

For automation, run {binary} account totp setup, then {binary} account totp enable --input PATH|-.
The input JSON contains secret and totp strings. Check progress with {binary} account totp status.
Print the recovery key separately with {binary} account recovery-key.",
    },
    Change {
        commands: &["export", "photos export"],
        hint: Some("export now requires an app and a destination.

  {binary} photos export DIR --account NAME
  {binary} auth export DIR --account NAME

Run a separate command for each account you want to export."),
        flags: &[
            (&["--albums"], "Use --album ALBUM instead of --albums, repeating --album for multiple albums."),
            (&["--exclude-albums"], "Use --exclude-album ALBUM instead of --exclude-albums, repeating it for multiple albums."),
            (&["--shared"], "Shared albums are included by default. Use --exclude-shared instead of --shared=false."),
            (&["--hidden"], "Hidden albums are included by default. Use --exclude-hidden instead of --hidden=false."),
            (&["--emails"], "Run a separate export for each account, selecting its local name with --account NAME instead of --emails."),
        ],
        guide: "Run a separate export for each app and account:
  {binary} photos export DIR --account NAME
  {binary} auth export DIR --account NAME

Saved export jobs are no longer used. Update scheduled commands with explicit destinations.
To take over an earlier Photos export, log in and run {binary} photos export DIR --adopt.
Stop the old export job first. Taking over covers all recorded albums; filters must match that set.
Auth: backups are dated and encrypted by default; use --plaintext for URI text.
For scheduled encrypted backups, set ENTE_CLI_PASSWORD. Locker export is not available.",
    },
    Change {
        commands: &["auth decrypt"],
        hint: Some("auth decrypt now takes its output path through --output.

  {binary} auth decrypt INPUT --output OUTPUT"),
        flags: &[
            (&["--password", "-p"], "Supply the password through the prompt or ENTE_CLI_PASSWORD instead of --password/-p."),
        ],
        guide: "Use {binary} auth decrypt INPUT --output OUTPUT instead of two positional paths.
The password is prompted or read from ENTE_CLI_PASSWORD.

Omitting --output writes to stdout. An existing output file is refused.",
    },
    Change {
        commands: &["paste create"],
        hint: None,
        flags: &[
            (&["--file", "-f"], "Use --input PATH|- instead of --file/-f."),
            (&["--endpoint"], "Use --host instead of --endpoint."),
        ],
        guide: "Use {binary} paste create [TEXT] [--input PATH|-] [--host URL].

--password and --paste-origin keep their meanings.",
    },
    Change {
        commands: &["paste read", "paste consume"],
        hint: Some("'{command}' has been replaced by 'paste consume'.

  {binary} paste consume URL"),
        flags: &[
            (&["--endpoint"], "Use --host instead of --endpoint."),
        ],
        guide: "Use {binary} paste consume URL|TOKEN [--key KEY] [--host URL].

--raw keeps its meaning.",
    },
    Change {
        commands: &["version"],
        hint: Some("'version' has been replaced by '--version'.

  {binary} --version"),
        flags: &[],
        guide: "Use {binary} --version.",
    },
    Change {
        commands: &["admin get-user-id"],
        hint: Some("'{command}' has been replaced by 'admin user view'.

  {binary} admin user view EMAIL"),
        flags: &[],
        guide: "Use {binary} admin user view EMAIL|ID.",
    },
    Change {
        commands: &["admin list-users"],
        hint: Some("'{command}' has been replaced by 'admin user list'.

  {binary} admin user list --all"),
        flags: &[],
        guide: "Use {binary} admin user list --all for every user; the default limit is 100.",
    },
    Change {
        commands: &["admin delete-user"],
        hint: Some("'{command}' has been replaced by 'admin user delete'.

  {binary} admin user delete EMAIL"),
        flags: &[],
        guide: "Use {binary} admin user delete EMAIL. Add --yes to approve without prompting.",
    },
    Change {
        commands: &["admin disable-2fa"],
        hint: Some("'{command}' has been replaced by 'admin user disable-totp'.

  {binary} admin user disable-totp EMAIL"),
        flags: &[],
        guide: "Use {binary} admin user disable-totp EMAIL|ID. Add --yes to approve without prompting.",
    },
    Change {
        commands: &["admin disable-passkey"],
        hint: Some("'{command}' has been replaced by 'admin user remove-passkeys'.

  {binary} admin user remove-passkeys EMAIL"),
        flags: &[],
        guide: "Use {binary} admin user remove-passkeys EMAIL|ID. Add --yes to approve without prompting.",
    },
    Change {
        commands: &["admin update-subscription"],
        hint: Some("'{command}' has been replaced by 'admin user update-subscription'.

  {binary} admin user update-subscription EMAIL --no-limit"),
        flags: &[],
        guide: "Use {binary} admin user update-subscription EMAIL|ID --no-limit for the old default preset.
For custom limits, use --storage SIZE and/or --expires DATE. Add --yes for automation.",
    },
    Change {
        commands: &["admin send-mail"],
        hint: Some("'{command}' has been replaced by 'admin email test'.

  {binary} admin email test --to EMAIL --from EMAIL --from-name NAME"),
        flags: &[],
        guide: "Use {binary} admin email test --to EMAIL --from EMAIL --from-name NAME.",
    },
];

pub fn print(binary: &str, output: &mut impl Write) -> anyhow::Result<()> {
    writeln!(output, "Command changes")?;
    writeln!(
        output,
        "
Log in again with {binary} account login; old saved logins and config.yaml are not imported.
APP is photos, auth or locker. NAME is a local account name.
Choose the server with --host on login or creation; later commands use the saved server.
Use the same app and server when requesting an email code and completing login or creation.
ENTE_CLI_HOME replaces ENTE_CLI_CONFIG_DIR for choosing this CLI's local storage.
For unattended access, see {binary} vault --help for ENTE_CLI_VAULT_KEY.
Admin commands use --account NAME instead of --admin-user/-a; USER is positional.
Use --json for structured results. Old output formats are not preserved."
    )?;
    for change in CHANGES {
        writeln!(output, "\n{}", change.commands.join(" / "))?;
        for line in change.guide.replace("{binary}", binary).lines() {
            if !line.is_empty() {
                write!(output, "  {line}")?;
            }
            writeln!(output)?;
        }
        for (flags, guidance) in change.flags {
            writeln!(output, "  {}:", flags.join(", "))?;
            for line in guidance.replace("{binary}", binary).lines() {
                writeln!(output, "    {line}")?;
            }
        }
    }
    Ok(())
}

pub fn hint(command: &Command, arguments: &[OsString], error: &mut Error) {
    let context = match error.kind() {
        ErrorKind::InvalidSubcommand => ContextKind::InvalidSubcommand,
        ErrorKind::UnknownArgument => ContextKind::InvalidArg,
        _ => return,
    };
    let Some(ContextValue::String(invalid)) = error.get(context) else {
        return;
    };
    let Ok(matches) = crate::args::command()
        .ignore_errors(true)
        .try_get_matches_from(arguments)
    else {
        return;
    };
    let mut path = Vec::new();
    let mut current = &matches;
    while let Some((name, child)) = current.subcommand() {
        path.push(name);
        current = child;
    }
    if context == ContextKind::InvalidSubcommand {
        path.push(invalid);
    }
    let path = path.join(" ");
    let Some(change) = CHANGES
        .iter()
        .find(|change| change.commands.contains(&path.as_str()))
    else {
        return;
    };
    if context != ContextKind::InvalidSubcommand
        && !(path == "auth decrypt" && !invalid.starts_with('-'))
    {
        return;
    }
    let Some(summary) = change.hint else {
        return;
    };
    let binary = command.get_bin_name().unwrap_or_else(|| command.get_name());
    let summary = summary
        .replace("{command}", &path)
        .replace("{binary}", binary);
    *error = Error::raw(
        error.kind(),
        format!("{summary}\n\nSee all command changes with:\n  {binary} help migration\n"),
    );
}
