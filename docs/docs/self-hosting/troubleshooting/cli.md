---
title: Ente CLI - Self-hosting
description: A quick hotfix for keyring errors while running Ente CLI.
---

# Ente CLI

## Secrets

Ente CLI makes use of your system keyring for storing sensitive information such as passwords.

There are 2 ways to address keyring-related error:

### Install system keyring

This is the recommended method as it is considerably secure than the latter.

If you are using Linux for accessing Ente CLI with, you can install a system keyring manager such as `gnome-keyring`, `kwallet`, etc. via your distribution's package manager.

For Ubuntu/Debian based distributions, you can install `gnome-keyring` via `apt`

```sh
sudo apt install gnome-keyring
```

Now you can use Ente CLI for adding account, which will trigger your system's keyring.

### Configure secrets path

In case of using Ente CLI on server environment, you may not be able to install system keyring. In such cases, you can configure Ente CLI to use a text file for saving the secrets.

Set `ENTE_CLI_SECRETS_PATH` environment variable in your shell's configuration file (`~/.bashrc`, `~/.zshrc`, or other corresponding file)

```sh
# Replace ./secrets.txt with the path to secrets file
# that you are using for saving.
# IMPORTANT: Make sure it is stored in a secure place.
export ENTE_CLI_SECRETS_PATH=./secrets.txt
```

When you run Ente CLI, and if the file doesn't exist, Ente CLI will create it and fill it with a random 32 character encryption key.

If you create the file, please fill it with a cryptographically generated 32 byte string.
