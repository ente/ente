# Migration

Ente's original CLI was written in Go. The new CLI, written in Rust, was introduced in October 2026 starting with version 0.4.0. The previous CLI (the `cli-v0.3.x` releases) keeps working and stays supported during the transition, but new development happens only in the new CLI.

The two can be installed side by side, and nothing changes until you act: the new CLI does not read the previous CLI's settings or credentials, and it leaves your exports alone until you ask it to adopt them. Commands have changed; `ente help migration` prints each old command next to its replacement.

A typical switch, for someone whose previous CLI keeps a Photos export up to date:

1. [Install the new CLI](./install.md) next to the previous one.
2. Log in: `ente account login --app photos`.
3. Stop the previous CLI's export job, then let the new CLI adopt the existing export: `ente photos export "$HOME/Pictures/Ente" --adopt`. It takes over the folder in place, without downloading everything again. The previous CLI cannot continue that export afterwards, so keep a copy if you want a way back.
4. Point the scheduled job at the new CLI, then remove the previous one.

Each step, every command and option change, and scripts that parse output are covered below.

Instructions for the previous CLI remain available for [Photos exports](/photos/features/utilities/cli), [self-hosted servers](/self-hosting/administration/cli) and [keyring troubleshooting](/self-hosting/troubleshooting/cli).

## Identify which executable runs

```sh
ente --version
```

The new CLI prints `ente` followed by its version; the previous CLI printed its version with `ente version`. Run `which -a ente` on Linux or macOS, or `where.exe ente` on Windows, to see every `ente` on your PATH. Install the new CLI in its own directory (see [Install Ente CLI](./install.md)) and put that directory first in your PATH, or call it by its full path in scripts. A previous-CLI command typed by mistake prints the replacement:

```
error: 'account add' has been replaced by 'account login'.

For Photos:
  ente account login --app photos

See all command changes with:
  ente help migration
```

## Log in again

```sh
ente account login --app photos
ente account login --app auth
```

Each app needs its own login. Commands use the selected account. Use `--account NAME` to choose another saved account by its local name. The CLI home replaces the previous configuration directory: set `ENTE_CLI_HOME` where you used `ENTE_CLI_CONFIG_DIR`. `ENTE_CLI_SECRETS_PATH` has no equivalent; for a headless machine, use `ENTE_CLI_VAULT_KEY` as described in [Accounts](./accounts.md#set-up-a-headless-machine). Learn more in [Accounts](./accounts.md).

## Replace saved export jobs

The previous CLI stored an export directory per account (`account update --dir`) and exported every account with one `export` command. The new CLI takes the destination on each run, one command per account and app:

```sh
ente photos export "$HOME/Pictures/Ente"
ente auth export "$HOME/Backups/Auth"
```

Update your cron jobs or scheduled tasks accordingly. Learn more in [Automation](./automation.md).

## Take over a Photos export

The new CLI can adopt (`--adopt`) an export made by the previous CLI and keep maintaining it in place.

1. Stop the previous CLI's export job, and any schedule that runs it.
2. Keep a copy of the export directory if you want a way back.
3. Log in: `ente account login --app photos`.
4. Run `ente photos export "$HOME/Pictures/Ente" --adopt`. Pass the same album filters the previous job used (`--album` for each album, `--exclude-album`, `--exclude-shared`, `--exclude-hidden`), or none when it exported everything. The CLI checks the existing files before taking over.
5. Check the summary line: every album copy should be complete with no failures, and the previous CLI's files should be in place under their album folders.
6. Point your schedule at the new command without `--adopt` but with the same album filters; a run without them exports every album.

Album filters are now exact and case-sensitive; the previous CLI matched album names ignoring case. Learn more in [Photos](./photos.md#reconnect-or-adopt-an-export).

## Command changes

| Previous CLI                | New CLI                                                              |
| --------------------------- | -------------------------------------------------------------------- |
| `account add`               | `account login --app APP [--account NAME] [--host URL]`              |
| `account list`              | `account list`; select with `account switch NAME`                    |
| `account update --dir DIR`  | Pass `DIR` to `photos export DIR` or `auth export DIR`               |
| `account get-token`         | `account token --app APP [--account NAME]`                           |
| `export`                    | `photos export DIR --account NAME`, `auth export DIR --account NAME` |
| `auth decrypt INPUT OUTPUT` | `auth decrypt INPUT --output OUTPUT`                                 |
| `version`                   | `--version`                                                          |

Account creation and Paste are new in this CLI; see [Accounts](./accounts.md) and [Paste](./paste.md). The CLI does not export Locker.

## Option changes

| Previous option                   | New CLI                                                    |
| --------------------------------- | ---------------------------------------------------------- |
| `endpoint.api` in `config.yaml`   | `--host` on login; saved with the account                  |
| `--albums`                        | `--album A --album B` (exact names or IDs)                 |
| `--exclude-albums`                | `--exclude-album A --exclude-album B`                      |
| `--shared=false`                  | `--exclude-shared` (shared albums are included by default) |
| `--hidden=false`                  | `--exclude-hidden` (hidden albums are included by default) |
| `--emails`                        | One export per account with `--account NAME`               |
| `--password`, `-p` (auth decrypt) | Prompt, or `ENTE_CLI_PASSWORD`                             |
| `--admin-user`, `-a` (admin)      | `--account NAME`; the target user is a positional argument |

## Administrator commands

| Previous CLI                | New CLI                                                                                         |
| --------------------------- | ----------------------------------------------------------------------------------------------- |
| `admin get-user-id`         | `admin user view EMAIL\|ID`                                                                     |
| `admin list-users`          | `admin user list --all`                                                                         |
| `admin delete-user`         | `admin user delete EMAIL [--yes]`                                                               |
| `admin disable-2fa`         | `admin user disable-totp EMAIL\|ID [--yes]`                                                     |
| `admin disable-passkey`     | `admin user remove-passkeys EMAIL\|ID [--yes]`                                                  |
| `admin update-subscription` | `admin user update-subscription EMAIL\|ID --no-limit`, or `--storage SIZE` and `--expires DATE` |
| `admin send-mail`           | `admin email test --to EMAIL --from EMAIL --from-name NAME`                                     |

Learn more in [Administration](./admin.md).

## Update scripts that parse output

The previous CLI's output formats are not preserved. Use `--json` and the field names in [Photos](./photos.md#read-as-json), [Auth](./auth.md) and [Administration](./admin.md); check the exit status before parsing; and expect raw bytes from the commands listed in [Automation](./automation.md#commands-that-write-raw-bytes). Add `--no-input` so a script fails instead of waiting for a prompt.
