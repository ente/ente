# Changelog

## v0.4.3 - Nov 2026

- Photos export adoption now keeps its temporary database in the CLI home, respecting `ENTE_CLI_HOME`.
- List exact duplicate photos with `photos duplicate list`, preview cleanup, and select groups to move extra copies to trash using the same Rust logic as the web app.
- Added `ente feedback` to send feedback from the CLI.
- Filter `photos file list` by type, creation date, name or caption words, size, and missing location, and sort it by creation time or size. Files now show their size.
- Show Photos storage usage, plan status and file count with `photos usage`.
- List the cities and countries where your photos were taken with `photos place list`, and filter `photos file list` by `--place` and `--country`.

## v0.4.2 - Oct 2026

- The macOS and Windows downloads are now signed, and macOS downloads are notarized.
- macOS archive names now use `macos` instead of `darwin`.
- Fixed CLI authenticator (TOTP) setup to support recovery in web and mobile apps.

## v0.4.1 - Oct 2026

- Fixed saved logins becoming unreadable when using KeePassXC for system secret storage on Linux.

## v0.4.0 - Oct 2026

- Export your Photos library to a folder and keep it up to date. Take over an export made by the previous CLI or the desktop app with `--adopt`.
- Back up your Auth codes to an encrypted file, decrypt a backup, and show a current code.
- Share text through one-time encrypted Paste links.
- Manage users on a self-hosted server: list, change free subscriptions, reset login factors, test email.
- Use it from scripts and agents: `--json`, `--no-input`, shell completions, and a vault key for headless machines.
