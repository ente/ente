# Accounts

Log in to Photos:

```sh
ente account login --app photos
```

The CLI asks for your email and password, then for an email verification code or an authenticator code when your account requires one. When it works, it prints the saved account:

```
Name       alice@example.com
Email      alice@example.com
Host       https://api.ente.com
Logged in  photos
Selected   yes
ID         1580559962386438
```

`--account NAME` is the local name for this account on this computer. Without it, the login goes to the selected account, or, when there is none yet, to a new account named after its email. `--app` is `photos`, `auth` or `locker`.

If your account uses a passkey, the CLI opens your browser, or prints the link if it cannot. Approve the login there, return to the terminal, and press Enter. When both a passkey and an authenticator are set up, the CLI asks which to use. Passkey login needs a terminal; it does not work with `--input` or `--no-input`.

## Add a second app

Each app has its own login. Log the same account into Auth:

```sh
ente account login --app auth
```

`Logged in` now shows `photos,auth`.

## Use a self-hosted server

```sh
ente account login --account home-server --app photos --host https://api.example.org
```

The server is saved with the account, and every later command uses it. A saved name keeps its server; to log in to another server, use a new name.

## Pick and rename accounts

```sh
ente account list
```

```
SELECTED  NAME               EMAIL              HOST                     LOGGED IN    ID
          alice@example.com  alice@example.com  https://api.ente.com     photos,auth  1580559962386438
*         home-server        alice@example.com  https://api.example.org  photos       3
```

Commands use the selected account. Adding an account selects it; logging in to an existing one keeps the selection. Change the selection with `ente account switch home-server`, or pick an account for one command with `--account NAME` after the subcommand. `ente account rename alice@example.com personal` changes a local name.

## Create an account

```sh
ente account create --app photos
```

The CLI asks for your email, consent to the terms, the verification code it emails you, and a password. It prints `Created alice@example.com and signed into Ente Photos.` Then print and store your recovery key:

```sh
ente account recovery-key
```

If creation is interrupted, run the same `account create` command again with the same CLI home and password; it resumes with its saved keys. If the server already has the account, run `ente account login` instead; it completes the login and clears the unfinished creation.

## Log in without prompts

Write the credentials as JSON. All fields are strings:

```json
{
    "email": "alice@example.com",
    "password": "correct horse battery staple",
    "otp": "123456",
    "totp": "654321"
}
```

Include `otp` only when the server asks for an email code; request it first with `ente account request-otp --email alice@example.com --app photos --purpose login`. Include `totp` only when authenticator protection is enabled. Then:

```sh
ente account login --account personal --app photos --input credentials.json --no-input
```

`--input -` reads the JSON from stdin. Creation works the same way with `--accept-terms`, an `otp` from `ente account request-otp --email alice@example.com`, and no `totp`.

## Protect login with an authenticator

```sh
ente account totp enable
```

The CLI prints a secret to add to your authenticator app, asks for a code from it, and prints `Authenticator protection is enabled.` Without prompts, run `ente account totp setup` to get the secret, then `ente account totp enable --input -` with `{"secret": "...", "totp": "..."}`. `ente account totp status` shows the current setting. This protects your account login and is separate from the codes stored in Auth.

## Get a token

```sh
ente account token --app photos
```

Prints the saved API token for that app login. It is a secret. With `--json` the result is `{"token": "..."}`.

## Log out

```sh
ente account logout --app auth
```

Prints `Logged out of Ente Auth for "alice@example.com".` Without `--app`, the CLI logs out of every app and removes the account and its local data: `Logged out of Ente Photos and Ente Auth. Removed account "alice@example.com" from this device.` `ente account logout --local` forgets the account on this computer without contacting the server; it cannot be combined with `--app`.

## CLI home

The CLI home is the directory where the CLI keeps its data: an encrypted vault with your accounts and keys, and a database per account with synced metadata.

| System  | CLI home                                                               |
| ------- | ---------------------------------------------------------------------- |
| macOS   | `~/Library/Application Support/ente-cli`                               |
| Linux   | `$XDG_DATA_HOME/ente-cli`, which defaults to `~/.local/share/ente-cli` |
| Windows | `%LOCALAPPDATA%\ente-cli`                                              |

Set `ENTE_CLI_HOME` to use another directory. The key that unlocks the vault is stored in your operating system's credential store under the service name `io.ente.cli`, keyed by the path of the CLI home. A CLI home that has been moved cannot find its key; move it back, or supply the original key through `ENTE_CLI_VAULT_KEY`.

## Set up a headless machine

A server or container has no credential store. Generate a key once, keep it in a file outside the CLI home that only the job can read, and supply it on every run:

```sh
umask 077
mkdir -p "$HOME/.config/ente-cli"
(set -C; ente vault key generate > "$HOME/.config/ente-cli/vault-key")
export ENTE_CLI_HOME="$HOME/.local/share/ente-cli-jobs"
export ENTE_CLI_VAULT_KEY="$(cat "$HOME/.config/ente-cli/vault-key")"
ente account login --account personal --app photos --input credentials.json --no-input
```

`set -C` makes the shell refuse to overwrite an existing key file; a replaced key cannot open the vault it was not used to create. Use the same CLI home and key for every later run. Learn more in [Automation](./automation.md).
