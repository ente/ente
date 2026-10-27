# Auth

Make an encrypted backup of your codes:

```sh
ente account login --app auth
ente auth export "$HOME/Backups/Auth"
```

> Login uses the selected account. Add `--account NAME` to choose another saved account or add one under a new name.

The CLI asks for an export password and its confirmation, refreshes your codes from the server, and prints:

```
Exported 12 codes to /home/alice/Backups/Auth/ente-auth-2026-10-22.json.
```

The file name carries the date. A second backup on the same day becomes `ente-auth-2026-10-22-2.json`, then `-3`; the CLI never overwrites a backup. The export password is separate from your account password, and nobody can recover it for you.

## Verify the backup

Import it into the Ente Auth app on another device: open `Settings > Data > Import codes`, choose **Ente encrypted export**, select the file, and enter the export password. Check that the number of codes matches.

## Decrypt a backup

```sh
ente auth decrypt "$HOME/Backups/Auth/ente-auth-2026-10-22.json" --output codes.txt
```

Prints `Decrypted to codes.txt.` The output is one `otpauth://` link per line. No account or network is needed. Without `--output`, the links go to stdout.

## Show a current code

```sh
ente auth code view github
```

```
GitHub (alice@example.com)
123456
Valid until 2026-10-22T10:30:30Z
```

The selector is a code ID, the displayed name, or words matched against the issuer and account name, ignoring case. When several codes match, the CLI lists them and you pick an ID. `ente auth code list --search github` finds codes without showing their values. Codes depend on your computer's clock, so keep its date and time correct.

## Work offline

Add `--offline` to `code list`, `code view` or `export` to use the codes synced by the last online run.

## Export plaintext or stream to stdout

```sh
ente auth export "$HOME/Backups/Auth" --plaintext
ente auth export --output - > backup.json
```

`--plaintext` writes unencrypted `otpauth://` links to a dated `.txt` file. `--output PATH` writes to that exact file and refuses to overwrite it; `--output -` writes the backup to stdout with no summary.

## Use from a script

Set `ENTE_CLI_PASSWORD` to the export password; an encrypted backup with `--no-input` requires it, a `--plaintext` export does not. With `--json`, export prints `{"output": "...", "codes": 12, "failures": {"total": 0}}`, `code list` returns objects with `id`, `name`, `issuer`, `accountName` and `type` (`totp`, `hotp` or `steam`), and `code view` adds `otp` and `validUntil` (UTC). `otp` is a string, so leading zeroes are kept. Learn more in [Automation](./automation.md#back-up-auth-codes).

## Limits

- TOTP and Steam codes are shown. HOTP codes are listed and backed up but not shown.
- Codes in Trash are not listed or shown, but backups include them. Restore them in the Ente Auth app to use them.
- The CLI does not add, edit or import codes; use the Ente Auth app.
