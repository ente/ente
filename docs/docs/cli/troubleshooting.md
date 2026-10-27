# Troubleshooting

Errors are printed on stderr as one line starting with `Error:`, and the command exits with status 1. A wrong command line exits with status 2. Find the message below.

## The command is not recognised

```
error: 'account add' has been replaced by 'account login'.
```

You typed a previous-CLI command. The error names the replacement, and `ente help migration` lists all of them. Learn more in [Migration](./migration.md).

If `ente` is not found, the installation directory is not on your PATH; see [Install Ente CLI](./install.md#add-the-cli-to-your-path). If `ente --version` prints an error instead of `ente` and a version, another `ente` is running; see [Identify which executable runs](./migration.md#identify-which-executable-runs).

## The account or app cannot be selected

| Message                                                                                              | Fix                                                                     |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `no accounts; use account login --app <APP>`                                                         | Log in. Check `ENTE_CLI_HOME` if you expected saved accounts.           |
| `no account selected; use account switch <NAME> or name an account explicitly`                       | Run `ente account switch NAME`, or add `--account NAME` to the command. |
| `no account named "work"; use account list`                                                          | `ente account list` shows the saved names.                              |
| `account "personal" is not logged into Ente Auth; use account login --account "personal" --app auth` | Log that account into the app the command needs.                        |
| `multiple apps are saved without Photos; select one with --app`                                      | Add `--app auth` or `--app locker` to the `admin` or `totp` command.    |

## The vault cannot be unlocked

| Message                                                                 | Fix                                                                                                                                  |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `no saved vault key for this CLI home`                                  | The key is tied to the path of the CLI home. Move the directory back, or set the `ENTE_CLI_VAULT_KEY` you generated.                 |
| `access to system secret storage was denied`                            | Unlock the credential store, or use `ENTE_CLI_VAULT_KEY` as in [Set up a headless machine](./accounts.md#set-up-a-headless-machine). |
| `cannot unlock CLI vault: wrong key or damaged file`                    | `ENTE_CLI_VAULT_KEY` differs from the key used when the vault was created.                                                           |
| `ENTE_CLI_VAULT_KEY must be standard padded base64 of exactly 32 bytes` | Use the value printed by `ente vault key generate` without edits.                                                                    |

### "system vault key is invalid" with KeePassXC

CLI 0.4.0 could save an unreadable key in KeePassXC. Upgrade to 0.4.1, delete the `io.ente.cli` entry for your CLI home from KeePassXC, and delete the [CLI home folder](./accounts.md#cli-home) (`~/.local/share/ente-cli` by default; use your configured path if you set `XDG_DATA_HOME` or `ENTE_CLI_HOME`). Then log in again.

Your data in Ente and exported files are untouched. If you have an existing Photos export, run your usual export command with `--adopt` once to reconnect it.

## Login or creation did not finish

- `login requires otp in --input`: the server wants an email code. Request one with `ente account request-otp --email alice@example.com --purpose login`, then add it to the input JSON.
- `Code not accepted. Check the code and your computer's date and time, then try again.`: authenticator codes depend on the clock.
- `cannot create this account; use account login for an existing account`: the email is already registered. Log in instead.
- `unfinished creation uses Ente Auth; resume with --app auth`: rerun `account create` with the app you started with and the same password. If the server already has the account, `account login` completes it.
- `account already exists on this device; use account login`: the account is saved under another name. `ente account list` shows it.
- `passkey login requires an interactive terminal`: log in once from a terminal, or enable authenticator protection so `totp` can be supplied in JSON.

## Hosts, TLS and server compatibility

- `cannot reach the selected Ente server`: check the host and your network. The CLI trusts the certificates your operating system trusts.
- `account "home-server" uses https://api.example.org; supply a new account name to log in to another server`: a saved name keeps its server. Use a different `--account NAME`.
- `host must be an HTTP or HTTPS origin`: pass only the origin, such as `https://api.example.org`, with no path.
- `File downloads require the v3 API. Update your Ente server or check its proxy configuration.`: the server or its reverse proxy does not serve `/files/download/v3/`. Update the server, and make sure the proxy forwards that path.
- `HTTP 401`: the saved login is no longer valid; log in again.

## Offline data is missing

- `no local data; run the command online first` (also `no local Photos data` and `no local Auth data`): `--offline` only reads what an earlier online run synced. Run the command once without `--offline`.
- `files for album "Holidays" have not finished syncing; run the command online first`: the last online run did not finish that album.
- `download requires network access` and `export requires network access; remove --offline`: these commands always need the network.

## Export problems

| Message                                                                                                     | Fix                                                                                                                                        |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `This folder contains an export from the old CLI or Ente Desktop. Use --adopt if you want to take it over.` | Stop the other writer, then rerun with `--adopt`. See [Take over a Photos export](./migration.md#take-over-a-photos-export).               |
| `this export is not associated with this CLI home; use --adopt`                                             | The export was made from another CLI home. Rerun with `--adopt` to reconnect it.                                                           |
| `nonempty destination has no recognized export.json`                                                        | The directory holds other files. Use an empty directory or an existing export.                                                             |
| `another writer is maintaining this export`                                                                 | An export is already running on this directory.                                                                                            |
| `this export belongs to another source account`                                                             | Export with the account that created it, or choose another directory.                                                                      |
| `adoption filters must select exactly the recorded album IDs`                                               | Pass the same album filters the previous job used, or none.                                                                                |
| `no album matches "holidays"` or `album "Holidays" is ambiguous`                                            | Names are exact and case-sensitive. Use the album ID from `ente photos album list`.                                                        |
| `conflict: at .../IMG_0001.jpg: locally changed media`                                                      | You edited an exported file, or a file of yours occupies that path, and the CLI left it alone. Move it away to let the export write there. |
| `export is incomplete`                                                                                      | The summary line shows pending copies and failures. Read the lines above it, fix the cause, and rerun.                                     |

## The output path cannot be used

- `output already exists: codes.txt`: `--output` never overwrites. Choose a new name, or let `auth export DIR` pick a dated name.
- `output parent directory does not exist` and `cannot save download to ./IMG_0001.jpg`: create the directory, or pick a name that does not exist yet.

## Report a problem

Open an issue at [github.com/ente/ente/issues](https://github.com/ente/ente/issues) with the output of `ente --version`, your operating system, the command with secrets removed, and the error line.
