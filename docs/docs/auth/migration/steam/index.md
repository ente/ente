---
title: Migrating from Steam Authenticator
description: Guide for importing from Steam Authenticator to Ente Auth
---

# Migrating from Steam Authenticator

> [!WARNING]
>
> Steam Authenticator code is only supported after auth-v3.0.3, check the app's version number before migration.

One way to migrate is to [use this tool by dyc3][releases] to simplify the process and skip directly to generating a qr code to Ente Authenticator.

## Download/Install steamguard-cli

### Windows

1. Download `steamguard.exe` from the [releases page][releases].
2. Place `steamguard.exe` in a folder of your choice. For this example, we will use `%USERPROFILE%\Desktop`.
3. Open Powershell or Command Prompt. The prompt should be at `%USERPROFILE%` (eg. `C:\Users\<username>`).
4. Use `cd` to change directory into the folder where you placed `steamguard.exe`. For this example, it would be `cd Desktop`.
5. You should now be able to run `steamguard.exe` by typing `.\steamguard.exe --help` and pressing enter.

### Linux

#### Ubuntu/Debian

1. Download the `.deb` from the [releases page][releases].
2. Open a terminal and run this to install it:

```sh
sudo dpkg -i ./steamguard-cli_<version>_amd64.deb
```

#### Other Linux

1. Download `steamguard` from the [releases page][releases]
2. Make it executable, and move `steamguard` to `/usr/local/bin` or any other directory in your `$PATH`.

```sh
chmod +x ./steamguard
sudo mv ./steamguard /usr/local/bin
```

3. You should now be able to run `steamguard` by typing `steamguard --help` and pressing enter.

## Login to Steam account

Set up a new account with steamguard-cli

```sh
steamguard setup # set up a new account with steamguard-cli
```

## Generate & importing QR codes

steamguard-cli can then generate a QR code for your 2FA secret.

```sh
steamguard qr # print QR code for the first account in your maFiles
steamguard -u <account name> qr # print QR code for a specific account
```

Open Ente Auth, press the '+' button, select `Scan a QR code`, and scan the qr code.

You should now have your steam code inside Ente Auth

[releases]: https://github.com/dyc3/steamguard-cli/releases/latest
