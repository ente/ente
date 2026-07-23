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

### I'm locked out and don't have my recovery key {#locker-locked-out}

Without your recovery key and password, your account cannot be recovered unless you previously set up [Legacy recovery](/locker/features/legacy/). This is an intentional security feature of end-to-end encryption.

To prevent this in the future, always save your recovery key in multiple secure locations when creating an account.

### 2FA is not accepting my code {#locker-2fa-issues}

1. **Check time sync**: Ensure your device's time is accurate
2. **Use correct app**: Use the authenticator app where you set up 2FA
3. **Try backup codes**: Use a backup code if available
4. **Wait for new code**: TOTP codes change every 30 seconds

## Lock Screen Issues

### Lock screen isn't working {#locker-lock-screen-not-working}

1. Check that lock screen is enabled in `Settings > Security`
2. Verify your device has biometric authentication configured
3. Try setting up a PIN as an alternative
4. Restart the app

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

1. Open `Settings > Support`
2. Tap **Export logs**
3. Share the exported file with [support@ente.com](mailto:support@ente.com)

Logs help us diagnose issues but contain no personal data.

## Connectivity

### Can I use Locker offline? {#locker-offline}

Yes, for items you choose to keep locally on your device.

Locker now supports keeping specific items available offline so you can open them without an internet connection after they have been downloaded.

You still need internet access for syncing changes, fetching items that are not already stored locally, and creating or refreshing shared links.

## Related Features

- [Lock screen](/locker/features/security/lock-screen)
- [Security FAQ](/locker/faq/security)
