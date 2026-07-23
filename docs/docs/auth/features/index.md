---
title: Features - Auth
description: Features available in Ente Auth
---

# Features

This page outlines the key features available in Ente Auth.

### Icons

Ente Auth supports the icon pack provided by [simple-icons](https://github.com/simple-icons/simple-icons). If an icon you need is missing, please refer to the [docs/adding-icons](https://github.com/ente/ente/blob/main/mobile/apps/auth/docs/adding-icons.md) guide for instructions on how to contribute.

### Search

Quickly find your codes by searching based on issuer or account name. You can also configure the app to focus the search bar automatically on app start by going to **Settings → General → Focus search on app start**.

### Tags

Organize and filter your codes with ease using tags.

- **Creating a Tag:** When adding or editing a code, tap the orange (+) icon to create a new tag.
- **Adding an existing Tag:** When adding or editing a code, select the desired tag from the list.

### Pinning

Highlight your frequently used services by pinning them to the top of your code list. To pin a code, long-press (mobile) or right-click (desktop) the code and select "Pin". Pinned entries show a pin indicator in the list so you can quickly spot them.

### Multi-select

Select multiple codes to perform bulk operations and access additional options.

**On mobile:**

- Tap and hold on a code to enter multi-select mode
- Tap additional codes to add them to your selection
- Use the toolbar that appears at the bottom to perform actions on all selected codes

**On desktop:**

- Long-press on a code to enter multi-select mode
- Click additional codes to add them to your selection
- Use the toolbar that appears at the bottom to perform actions on all selected codes

Available actions in multi-select mode include sharing, tagging, pinning, copying, and trashing multiple codes at once.

### Notes

Add additional information to your codes using notes. Notes can be added during the process of creating or modifying a code.

### Sharing

Securely share codes temporarily with others.

- Long-press (mobile) or right-click (desktop) on a code and choose "Share".
- Select a duration for the shared link: 2 minutes, 5 minutes, or 10 minutes.
- This generates a unique, time-limited link. Recipients can view the codes for the specified duration without gaining access to the underlying secret key. After the link expires, the recipients will no longer be able to view new codes.

### Custom sorting

Customize the order in which your codes are displayed. Ente Auth provides several sorting options:

- Issuer name
- Account name
- Frequently used
- Recently used
- Manual (custom drag-and-drop order)

Access the sort menu in the top-right corner (next to the search icon) to change your sorting preference.

### Offline mode

Ente Auth can be used entirely offline. Choose "Use without backups" on the login screen. In this mode, your codes are stored locally on your device.

Unlike when using an account, data is not synced or backed up to the cloud. You are responsible for manually backing up your codes.

The local vault is encrypted using a key protected by your device's secure storage. Device transfers and OS backups are not supported recovery methods for offline-mode codes. Create an encrypted export or local backup and keep the backup password safe.

Learn more about [using offline mode safely](offline-mode).

### Display options

Customize how your codes are displayed for optimal usability.

- **Show large icons:** Display codes with larger icons for enhanced visibility.
- **Compact mode:** Switch to a more compact layout to view more codes on the screen simultaneously.
- **Hide codes:** Hide the actual code values for extra privacy. Double-tap a code to reveal it when needed.

### App lock

Add an additional layer of protection using the app lock. Choose from the following lock methods:

- **Device lock:** Use the existing lock configured on your device (e.g., Face ID, Touch ID, system password).
- **PIN lock:** Set up a 4-digit PIN code to unlock the app.
- **Password lock:** Set up a password to unlock the app.

Additionally, configure **Auto lock** to automatically lock the app after a specified period of time (options: Immediately, 5s, 15s, 1m, 5m, 30m).

App lock protects access to the app UI. It is not a recovery password for your codes and does not re-encrypt the stored Auth data.

### Import / Export

Ente Auth offers various import and export options for your codes.

- **Export:** Export your codes in plain text, as an encrypted file, or automatically via the CLI.
- **Import:** Import codes from various other authentication apps.

For detailed instructions, refer to the [migration guides](../migration/).

### Deduplicate codes

If you import codes and end up with duplicates, you can easily remove them. Go to **Settings → Data → Duplicate codes** to find and remove duplicate codes.

### Trash

Manage unwanted codes by moving them to the Trash. The Trash is not cleared automatically, giving you the flexibility to restore or permanently delete codes at any time.

- **Trashing a code:** Long-press (mobile) or right-click (desktop) on a code and select "Trash" to move it to the Trash.
- **Viewing trashed codes:** If you have trashed codes, you can view them by selecting the Trash tag.
- **Managing trashed codes:** In the Trash view, you can either permanently delete codes or restore them back to your main list.

### Scan QR

Easily add or share entries using QR codes:

- **Add by scanning (mobile):** On mobile (Android and iOS), you can add a new entry by scanning the QR code provided by the service. Access the QR scanner from the SpeedDial button (FAB) in the bottom-right corner.

    This quickly adds the entry to Ente Auth. You can also import QR codes from images saved on your device by using the "Import from Gallery" button available in the QR scanner page itself.

    > [!NOTE]
    >
    > The "Import from Gallery" feature is particularly useful when you have a screenshot or photo of a QR code. Simply save the QR code image to your device and use this feature to import it without needing to display it on another screen.

- **Show entry as QR code:** On all apps, you can long-press (mobile) or right-click (desktop) a code and select "QR". This allows you to easily share the complete entry (including the secret) with others by letting them scan the displayed QR code. This can also be used to easily add the same entry to another authenticator app or service.
