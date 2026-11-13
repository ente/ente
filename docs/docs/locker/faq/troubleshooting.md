---
title: Troubleshooting FAQ
description: Solutions to common issues with Ente Locker
---

# Troubleshooting FAQ

Solutions to common problems and issues with Ente Locker.

## App Issues

### The app is crashing. What should I do? {#locker-app-crash}

Try these steps:

1. **Update the app**: Install the latest version from your app store
2. **Restart your device**: A fresh start can resolve many issues
3. **Clear app cache** (Android): Settings > Apps > Ente Locker > Clear Cache
4. **Reinstall the app**: Uninstall and reinstall (your data is safe in the cloud)
5. **Contact support**: If crashes continue, email [support@ente.com](mailto:support@ente.com) with details

### The app is running slowly {#locker-app-slow}

To improve performance:

1. Close other apps to free memory
2. Ensure adequate storage space on your device
3. Update to the latest app version
4. Restart the app

### Locker won't open on GrapheneOS. What should I do? {#locker-graphene-exploit-protection}

On GrapheneOS, Locker may fail to open unless exploit protection compatibility mode is enabled for it.

**On GrapheneOS:**

1. Open device `Settings > Apps > Ente Locker`.
2. Tap **Exploit protection compatibility mode** (under the app's settings).
3. Turn it on.
4. Force-close and reopen Locker.

### Why isn't my item appearing in search? {#locker-search-missing}

Items may not appear in search because:

- **Search scope**: Search matches item titles and names, not the full content within items
- **Recently created**: Wait a moment for indexing
- **In Trash**: Search doesn't include trashed items
- **Spelling**: Check your search query for typos

Try searching for the item's title or name. Use descriptive titles to make items easier to find.

## Login Issues

### I can't log in to my account {#locker-login-issues}

1. **Check credentials**: Verify your email and password are correct
2. **Check email**: Ensure you're using the email registered with Ente
3. **Reset password**: Use your recovery key if you forgot your password, or use Legacy recovery if you set it up earlier
4. **Check 2FA**: If enabled, enter your 2FA code correctly
5. **Try another device**: Test if you can log in elsewhere

### I'm signed in, but uploads fail with an invalid-session error. What should I do? {#locker-invalid-session-uploads}

If Locker or support identifies an invalid-session or invalid-token error during uploads, signing out and back in may refresh the session. Check the following before signing out:

1. Preserve any files or newly created items that have not finished syncing in a safe location outside Locker, and check that those copies can be opened
2. Verify which items are already available from your account on another device or on [Locker web](https://locker.ente.com)
3. Make sure you can sign in again with the correct account, password, and any required two-factor authentication. Keep your recovery key safely available
4. [Export debug logs](#locker-share-logs) if support needs them to investigate the failure

> [!WARNING]
>
> Signing out clears Locker's local offline copies. Do not sign out, reinstall the app, or clear its data if you cannot verify that all unsynced items are safely preserved outside Locker. [Contact support](#locker-contact-support) first.

Once these checks are complete, sign out of Locker and sign back in to the same account, then retry an upload. If it still fails, contact support with the error and logs. Other upload problems may have a different cause.

### I'm locked out and don't have my recovery key {#locker-locked-out}

Without your recovery key and password, your account cannot be recovered unless you previously set up [Legacy recovery](/locker/features/legacy/). This is an intentional security feature of end-to-end encryption.

To prevent this in the future, always save your recovery key in multiple secure locations when creating an account.

### 2FA is not accepting my code {#locker-2fa-issues}

1. **Check time sync:** Ensure your device's date and time are accurate, preferably using automatic time settings.
2. **Use the correct entry:** Open the authenticator where you set up two-factor authentication for this Ente account. A code for another website or another Ente account will not work.
3. **Wait for a new code:** Try the next code before it expires.
4. **Use your Ente recovery key:** If you cannot access your second factor, use the recovery option shown during sign-in and the 24-word recovery key for this Ente account. Backup codes from another website cannot recover Ente access.

If you have lost both the second factor and recovery key but still know your password, see [lost second-factor help](/photos/faq/security-and-privacy#two-factor-auth). Keep any working session signed in. Never send your password, recovery key, or authenticator codes to support.

## Lock Screen Issues

### Lock screen isn't working {#locker-lock-screen-not-working}

1. Make sure a passcode or screen lock is enabled in your phone's system settings
2. Open `Settings > Security > App lock` in Locker and authenticate when prompted
3. Turn on **App lock** and choose **Device lock**, **Pin lock**, or **Password**
4. If you use Device lock, check your device's authentication settings

See the [Lock screen guide](/locker/features/security/lock-screen) for setup details. If setup still fails, [contact support](#locker-contact-support) with your device model, OS version, and Locker version.

### I forgot my Locker PIN {#locker-forgot-pin}

If you configured biometric authentication, use that to access the app, then change your PIN in `Settings > Security`.

If you only have a PIN and forgot it, you may need to reinstall the app and log in again with your Ente credentials.

## Getting Help

### How do I report a bug? {#locker-report-bug}

Report bugs on GitHub: [github.com/ente/ente/issues](https://github.com/ente/ente/issues)

Include:

- Device model and OS version
- App version
- Steps to reproduce the issue
- Screenshots if helpful

### How do I contact support? {#locker-contact-support}

Email [support@ente.com](mailto:support@ente.com) for personalized help.

Include:

- Your Ente email (for account-related issues)
- Description of the problem
- Steps you've already tried

### How do I share debug logs with support? {#locker-share-logs}

1. Open `Settings > Help & Support` in the Locker mobile app
2. Tap **Export logs**
3. Send the exported file privately to [support@ente.com](mailto:support@ente.com), along with a description of the problem

Logs help us diagnose issues. Review the exported file before sharing it, and avoid posting logs publicly.

## Connectivity

### Can I use Locker offline? {#locker-offline}

Yes, for items you choose to keep locally on your device.

Locker now supports keeping specific items available offline so you can open them without an internet connection after they have been downloaded.

You still need internet access for syncing changes, fetching items that are not already stored locally, and creating or refreshing shared links.

## Related Features

- [Lock screen](/locker/features/security/lock-screen)
- [Security FAQ](/locker/faq/security)
