---
title: Exporting your data from Ente Auth
description: Guide for exporting your 2FA codes out from Ente Auth
---

# Exporting your data out of Ente Auth

## Auth Encrypted Export format

### Overview

When we export the auth codes, the data is encrypted using a key derived from the user's password. This document describes the JSON structure used to organize exported data, including versioning and key derivation parameters.

### Export JSON Sample

```json
{
    "version": 1,
    "kdfParams": {
        "memLimit": 4096,
        "opsLimit": 3,
        "salt": "example_salt"
    },
    "encryptedData": "encrypted_data_here",
    "encryptionNonce": "nonce_here"
}
```

The main object used to represent the export data. It contains the following key-value pairs:

- `version`: The version of the export format.
- `kdfParams`: Key derivation function parameters.
- `encryptedData"`: The encrypted authentication data.
- `encryptionNonce`: The nonce used for encryption.

#### Version

Export version is used to identify the format of the export data.

##### Ver: 1

- KDF Algorithm: `ARGON2ID`
- Decrypted data format: `otpauth://totp/...`, separated by a new line.
- Encryption Algo: `XChaCha20-Poly1305`

##### Key Derivation Function Params (KDF)

This section contains the parameters that were using during KDF operation:

- `memLimit`: Memory limit for the algorithm.
- `opsLimit`: Operations limit for the algorithm.
- `salt`: The salt used in the derivation process.

##### Encrypted Data

As mentioned above, the auth data is encrypted using a key that's derived by using user provided password & kdf params. For encryption, we are using `XChaCha20-Poly1305` algorithm.

## Automated backups

You can use [Ente's CLI](https://github.com/ente/ente/tree/main/cli#readme) to automatically backup your Auth codes.

To export your data, add an account using `ente account add` command. In the first step, specify `auth` as the app name. At a later point, CLI will also ask you specify the path where it should write the exported codes.

You can change the export directory using following command

```
ente account update --app auth --email <email> --dir <path>
```

## Local backups

Ente Auth supports continuous on-device local backups to protect your codes even when offline. This feature creates encrypted backups on your device automatically.

**How it works:**

- **Automatic daily backups:** When enabled, Ente Auth creates one local backup per day when you open the app.
- **Password-protected:** All local backups are encrypted with a password you set. Keep this password safe, because Ente cannot recover it for you.
- **Custom backup location:** Choose where to store your backups on your device.
- **Backup retention:** The app keeps up to 5 most recent backups and automatically removes older ones.

If you use Ente Auth in offline mode, encrypted exports and local backups are the supported recovery path. Device transfers and OS backups should not be treated as a backup for offline codes. Store the backup or export file in a separate location you can access after a reset or device change. Learn more about [using offline mode safely](/auth/features/offline-mode).

**Setting up local backups:**

1. Open `Settings > Data > Local backup`.
2. Enable **Automatic backups**.
3. Set a backup password (minimum 8 characters).
4. Select a folder where backups will be stored.

**Manual backups:**

You can trigger a manual backup at any time using the **Create backup now** button. Manual backups are useful before making significant changes to your codes.

## How to use the exported data

- **Ente Authenticator app**: You can directly import the codes in the Ente Authenticator app.

    > Settings -> Data -> Import Codes -> Ente Encrypted export.

- **Decrypt using Ente CLI** : Download the latest version of [Ente CLI](https://github.com/ente/ente/releases?q=tag%3Acli-v0), and run the following command

```
  ./ente auth decrypt <export_file> <output_file>
```
