# Automation

Schedule a nightly export. Set up the CLI home and vault key first, as described in [Set up a headless machine](./accounts.md#set-up-a-headless-machine), and log in once with `--input`.

**With cron:** save this as `$HOME/.config/ente-cli/export.sh` and make it executable.

```sh
#!/bin/sh
export ENTE_CLI_HOME="$HOME/.local/share/ente-cli-jobs"
export ENTE_CLI_VAULT_KEY="$(cat "$HOME/.config/ente-cli/vault-key")"
exec "$HOME/.local/opt/ente-cli/bin/ente" photos export "$HOME/Pictures/Ente" --account personal --no-input --json \
    > "$HOME/.config/ente-cli/last-export.json" 2>> "$HOME/.config/ente-cli/export.log"
```

Then add a line with `crontab -e`:

```
30 2 * * * "$HOME/.config/ente-cli/export.sh"
```

**With Windows Task Scheduler:** prepare the job's CLI home and key once, in PowerShell:

```powershell
New-Item -ItemType Directory -Force $env:LOCALAPPDATA\ente-cli | Out-Null
ente vault key generate | Out-File $env:LOCALAPPDATA\ente-cli\vault-key -Encoding ascii -NoClobber
$env:ENTE_CLI_HOME = "$env:LOCALAPPDATA\ente-cli\home"
$env:ENTE_CLI_VAULT_KEY = (Get-Content $env:LOCALAPPDATA\ente-cli\vault-key -Raw).Trim()
ente account login --account personal --app photos --input credentials.json --no-input
```

Then save this as `%LOCALAPPDATA%\ente-cli\export.ps1`:

```powershell
$env:ENTE_CLI_HOME = "$env:LOCALAPPDATA\ente-cli\home"
$env:ENTE_CLI_VAULT_KEY = (Get-Content $env:LOCALAPPDATA\ente-cli\vault-key -Raw).Trim()
& "$env:LOCALAPPDATA\Programs\EnteCLI\ente.exe" photos export D:\Pictures\Ente --account personal --no-input --json `
    2>> $env:LOCALAPPDATA\ente-cli\export.log | Out-File -Encoding utf8 $env:LOCALAPPDATA\ente-cli\last-export.json
exit $LASTEXITCODE
```

Register it to run daily at 02:30:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$env:LOCALAPPDATA\ente-cli\export.ps1`""
$trigger = New-ScheduledTaskTrigger -Daily -At 02:30
Register-ScheduledTask -TaskName "Ente export" -Action $action -Trigger $trigger
```

Each run exits with status 0 when the export is complete, writes the summary to `last-export.json`, and appends progress and errors to `export.log`.

## Read results safely

- Exit status 0 means success, 1 means failure or incomplete work, and 2 means the command line was wrong.
- stdout carries the result. stderr carries progress, prompts and errors.
- `--json` formats results, not errors. An error is still a line on stderr starting with `Error:`.
- A failed command can have written part of its result to stdout. Check the exit status before parsing.
- Lists are JSON arrays; `view` commands and actions are JSON objects.

Capture first, then parse:

```sh
result=$(ente photos export "$HOME/Pictures/Ente" --account personal --no-input --json) ||
    { echo "export failed with status $?" >&2; exit 1; }
echo "$result" | jq '.changes.exported'
```

## Export summary

```json
{
    "output": "/home/alice/Pictures/Ente",
    "complete": true,
    "files": 1180,
    "copies": { "expected": 1200, "completed": 1200, "pending": 0 },
    "changes": {
        "exported": 20,
        "metadataUpdated": 3,
        "renamed": 0,
        "movedToTrash": 1
    },
    "failures": { "total": 0, "conflicts": 0 }
}
```

`files` counts distinct photos and videos; `copies` counts album copies, a photo placed in an album. Both are `null` when the full size of the export could not be determined. `failures.conflicts` counts paths the CLI left alone: files you changed locally, or your own files sitting where the export needs to write. `complete` is `false` whenever `pending` or `failures.total` is above zero, and the exit status is then 1.

## Commands that write raw bytes

These write their payload to stdout unchanged, even with `--json`:

- `ente auth export --output -`
- `ente auth decrypt FILE` without `--output`
- `ente photos api`, `ente auth api`, `ente locker api`
- `ente completion SHELL`

## Back up Auth codes

```sh
#!/bin/sh
export ENTE_CLI_HOME="$HOME/.local/share/ente-cli-jobs"
export ENTE_CLI_VAULT_KEY="$(cat "$HOME/.config/ente-cli/vault-key")"
export ENTE_CLI_PASSWORD="$(cat "$HOME/.config/ente-cli/auth-backup-password")"
exec "$HOME/.local/opt/ente-cli/bin/ente" auth export "$HOME/Backups/Auth" --account personal --no-input --json
```

`ENTE_CLI_PASSWORD` supplies the password for an encrypted backup and is required with `--no-input`; a `--plaintext` export needs none. The result is `{"output": "/home/alice/Backups/Auth/ente-auth-2026-10-22.json", "codes": 12, "failures": {"total": 0}}`. Test a backup by decrypting it: `ente auth decrypt FILE --output -` with the same variable set.

## Make an API request

```sh
ente photos api /collections/v2 --query sinceTime=0
ente auth api /authenticator/key
```

The CLI adds your token and sends the request to the account's server. The response body is written unchanged; a response status outside 2xx exits with status 1 after the body. `--body PATH` and `--headers PATH` read a request body or a JSON object of headers from a file, or from stdin with `-`.

## Handle a failed job

- Run the export again. It resumes and reuses what is already on disk.
- Read `export.log` for lines containing `conflict:` (a local edit or an occupied path, see [Photos](./photos.md#keep-an-export-updated)) and lines starting with `album:ID:` or `file:ALBUM:FILE:` (an item that could not be refreshed or downloaded).
- `HTTP 401` means the login is no longer valid. Log in again with `--input`.
- `cannot unlock CLI vault` or `no saved vault key` means the job runs with a different key or CLI home than the login did.

## For agents

Run `ente help --all` once to learn every command and flag, then call commands with `--json --no-input` and read stdout only after checking the exit status. Supply credentials through `--input PATH` rather than on the command line, and use `--offline` for repeated reads of data that was synced moments ago. The CLI never asks a question when `--no-input` is set; it fails with a message on stderr instead.
