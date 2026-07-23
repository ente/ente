---
title: Using offline mode safely - Auth
description: Guidelines for backing up and recovering Ente Auth codes when using offline mode
---

# Using offline mode safely

Ente Auth can be used without an account by choosing **Use without backups**. In offline mode, your codes are stored only on that device. They are not synced to Ente and cannot be restored from Ente's servers.

## How offline storage works

The local vault is encrypted using a key protected by the device's secure storage, such as the OS keychain, keyring, credential store, or secure storage service. If that secure-storage key becomes unavailable, Ente cannot recover the offline vault from the local database alone.

Device transfers and OS backups are not supported recovery methods for offline-mode codes. They may not include the secure-storage key, or the restored key may not be usable on the new system.

## Before device or OS changes

If you use Ente Auth in offline mode, create an encrypted export or local backup before resetting credentials, reinstalling your OS, transferring devices, restoring a device backup, or making major system changes. Verify that you know the backup password, and store the backup or export file in a separate location you can access after the change.

## App lock is not a recovery password

App lock protects access to the app UI. It is not a recovery password for your codes and does not re-encrypt the stored Auth data.

## Back up your codes

Open `Settings > Data > Local backup` to enable automatic local backups, or create an encrypted export from the Data settings. Keep your backup or export files and password somewhere safe.
