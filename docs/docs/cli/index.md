# Ente CLI

`ente` is Ente's client for terminals and agents. Use it from a shell or a script for things like keeping a copy of your Photos library on your own disk, backing up your Auth codes, or administering your own server.

## Export your Photos library

[Install the CLI](./install.md), then log in and export:

```sh
ente account login --app photos
ente photos export "$HOME/Pictures/Ente"
```

Login asks for your email and password, and for a verification code when your account requires one. The export prints progress while it runs and ends with a summary:

```
/home/alice/Pictures/Ente: 1200/1200 album copies complete, 1200 exported, 0 moved to Trash, 0 failures (0 conflicts).
```

Run the same command again whenever you want to pick up new photos. Learn more in [Photos](./photos.md).

## Find your task

| I want to…                                                            | Page                                    |
| --------------------------------------------------------------------- | --------------------------------------- |
| Download the CLI, verify it, add it to my PATH, enable completion     | [Install Ente CLI](./install.md)        |
| Log in, use a self-hosted server, keep several accounts, run headless | [Accounts](./accounts.md)               |
| Export my library, keep the export updated, find and download a file  | [Photos](./photos.md)                   |
| Back up my Auth codes or show a current code                          | [Auth](./auth.md)                       |
| Share text through a one-time link                                    | [Paste](./paste.md)                     |
| Manage users on my own server                                         | [Administration](./admin.md)            |
| Schedule exports and read results from a script or an agent           | [Automation](./automation.md)           |
| Switch from the previous CLI                                          | [Migration](./migration.md)             |
| Fix an error                                                          | [Troubleshooting](./troubleshooting.md) |

## Help and output

- `ente help <command>` prints help for one command, for example `ente help photos export`. `ente help --all` prints help for every command. `ente help migration` lists what changed from the previous CLI.
- `--json` prints the result as JSON. `--no-input` disables prompts, so a script fails instead of waiting. `--offline` reads data the CLI has already synced.
- `--account NAME` after a subcommand picks a saved account: `ente photos album list --account personal`.

The CLI keeps its data in the CLI home, a directory described in [Accounts](./accounts.md#cli-home). `ente help`, `ente --version` and `ente completion` never create it.
