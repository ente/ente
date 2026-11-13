---
title: Offline codes unavailable - Auth
description: Recover or reset Ente Auth when the key for offline codes is unavailable
---

# Offline codes unavailable

Ente Auth shows **Unable to access your codes** when an offline-only installation no longer has access to its encryption key in the operating system's secure storage.

## When this can happen

**On Android:**

- After a device-transfer or restore tool copies Ente Auth's data without its Android Keystore key.
- If the Keystore key is lost while the app's local data remains.

**On iOS:**

- After restoring or transferring Ente Auth to another iPhone. The device-only Keychain key does not transfer with the app's data.

**On macOS:**

- After restoring application data without the corresponding login Keychain.
- If Ente Auth loses access to its existing Keychain entry.

**On Linux:**

- After an update or restart changes which service provides Secret Service.
- If the original GNOME Keyring, KWallet, KeePassXC, or other provider is locked, disabled, missing, or damaged.

**On Windows:**

- After moving or restoring Ente Auth data to another computer or Windows user profile.
- After reinstalling Windows or recreating the user profile.
- After an administrative or offline password reset performed without the old password. A normal password change should not usually cause this.
- If access to Ente Auth's secure-storage file is blocked or the file is damaged.

## Recover or reset Ente Auth

Choose the first case that applies.

### Your codes were already synced to Ente

Reset Ente Auth using the steps below, then select **Log in**. Signing in restores the codes already stored in that Ente account. It does not recover codes that existed only in the inaccessible offline database.

### You have a local backup or encrypted export

Before resetting Ente Auth, confirm that the backup file is stored outside the app's data and that you know its encryption password.

After resetting the app, select **Use without backups**, then open `Settings > Data > Import codes > Ente encrypted`. Automatic local backups use the Ente encrypted format. For an export from another authenticator, select its importer instead.

### You do not have a synced copy or usable backup

> [!WARNING]
>
> Do not reset, uninstall, or clear Ente Auth's data yet. Try to restore access to the original secure storage first. If its key has been permanently lost, the encrypted offline database cannot be recovered.

- **On Android:** Try the original device and Android profile. A Keystore key cannot be recovered from app data copied without it.
- **On iOS:** Try the original iPhone. A device-only key cannot be recovered from data restored to another device.
- **On macOS:** Restore access to the original login Keychain or a system backup containing both the Keychain and Ente Auth data.
- **On Linux:** Unlock or restore the Secret Service provider that Ente Auth originally used.
- **On Windows:** Use the original Windows profile. If an administrator reset a domain account's password, contact the administrator before changing app data because its protected keys may still be recoverable.

## Reset the app

Reset only after confirming that your codes are synced to Ente or that you have a usable backup and its password. Keep a copy of the existing app data until recovery or import succeeds.

**On Android:** Open `Settings > Apps > Ente Auth > Storage & cache` and select **Clear storage** or **Clear data**. Menu names vary by device.

**On iOS:** Delete Ente Auth rather than offloading it, then reinstall it.

**On macOS:** Quit Ente Auth, move `~/Library/Containers/io.ente.auth.mac` to a safe location, and run `defaults delete io.ente.auth.mac` in Terminal.

**On Linux:** Quit Ente Auth and move the `io.ente.auth` directory under `$XDG_DATA_HOME` to a safe location. The default location is `~/.local/share/io.ente.auth`. Move legacy `ente_auth` or `enteauth` directories in the same location if they exist.

**On Windows:** Quit Ente Auth and rename `%APPDATA%\Ente Technologies, Inc\Ente Auth` in File Explorer. If an `ente` or `enteauth` folder from an older installation exists in Documents, rename it too.

Open Ente Auth again, then log in or import the backup. Remove the saved app data only after confirming that all codes have been restored.
