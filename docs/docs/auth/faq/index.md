---
title: FAQ - Auth
description: Frequently asked questions about Ente Auth
---

# Frequently Asked Questions

### How do I add a code to Ente Auth? {#add-code}

**If a service shows a QR code:**

1. Open Ente Auth.
2. Tap the + button.
3. Select "Scan a QR code".
4. Scan the QR code shown by the service.
5. Enter the generated code to verify setup.

**If a service shows a setup key:**

1. Open Ente Auth.
2. Tap the + button.
3. Choose "Enter details manually".
4. Enter the account name, issuer, and secret (setup key).
5. Save and verify the generated code.

### Why does Ente Auth say "No QR code found in image"? {#qr-code-not-scanning}

If the QR code is sharp and high-resolution but Ente Auth still won't scan it, the most likely cause is that the service is using a QR format Ente Auth doesn't recognise. Some sites embed proprietary or non-standard data instead of the standard `otpauth://` URI that authenticator apps expect.

The easiest workaround is to add the code manually:

1. Open Ente Auth.
2. Tap the + button.
3. Choose "Enter details manually".
4. Enter the account name, issuer, and secret (setup key) shown by the service alongside the QR code.

If the service only offers a QR code and no setup key, check its security settings for an option to "show setup key" or "can't scan?".

### How secure is Ente Auth?

All codes you backup via Ente is stored with end-to-end encryption. This means only you can access your codes. Our apps are open source and our cryptography has been externally audited.

### How can I delete or edit codes?

You can delete or edit a code by long pressing (or right clicking on desktop) on that item.

### How can I support this project?

You can support the development of this project by subscribing to our Photos app at [ente.com](https://ente.com).

### How can I enable FaceID lock in Ente Auth?

You can enable FaceID lock under Settings → Security → Lockscreen.

### How secure is the lock screen provided by Ente Auth?

Auth's lock screen acts as a barrier to prevent an attacker from accessing the contents of the app. It does not introduce a layer of cryptographic security.

### Why do the desktop and mobile apps display different codes?

Please verify that the time on both your mobile and desktop is the same.

The codes depend on time. If the time is the same on both your browser and mobile, the codes you see will be the same.

Usually, this discrepancy occurs because the time in your browser might be incorrect. In particular, multiple users have reported that Firefox provides incorrect time when certain privacy settings are enabled.

> [!TIP]
>
> Newer Ente Auth clients (upcoming 4.4.0+) will automatically try to correct for incorrect system time, so you should be seeing correct codes even if your system time is out of sync. However, this automatic correction will not work if you're using Ente Auth in offline mode.
>
> If you've recently changed your system time and the codes are still incorrect, try to refresh / restart the app if needed.

### Why may TOTP verification fail with Google Workspace? {#google-workspace-totp-verification}

Google Workspace doesn't explicitly block Ente Auth, but its implementation of TOTP is more restrictive and can sometimes be incompatible with third-party authenticators. While Ente Auth follows the open TOTP standard, Google's system occasionally expects additional metadata or a specific app ID, which can cause verification to fail.

That said, many users are able to use Ente Auth with Google Workspace without issues, so this behavior can vary.

Also ensure that your system time is accurate, as any time drift can cause TOTP codes to be invalid. You can verify your time at https://time.is/

### Can I access my codes on web?

You can access your codes on the web at [auth.ente.com](https://auth.ente.com).

### Why doesn't auth.ente.com recognize my email when I try to log in? {#auth-web-email-not-recognized}

If the web app says no account exists for your email, even though you're logged in on the mobile or desktop app, it's usually a stale cached email from a previous attempt. Try the following in order:

1. On the login screen, click **Change email address** and re-enter your current email.
2. Clear your browser's site data for `auth.ente.com` (or the cache for that domain).
3. Open the page in an incognito or private window.

If you recently changed the email on your Ente account, make sure you're entering the new address, not the old one.

### Why don't I see my codes after logging in? {#auth-codes-not-showing}

A few common reasons and what to check:

- **Wrong account**: confirm you're signed into the same Ente account everywhere. Open `Settings` and check the registered email at the top, then compare across your devices.
- **Offline mode**: if you were using Ente Auth in **Use without backups** (offline mode), your codes live only on that one device and aren't synced to the cloud. They won't appear on a new device or on the web until you sign in on the original device and let it sync.
- **Sync check**: log in once on the web app at [auth.ente.com/login](https://auth.ente.com/login) to confirm whether your codes exist in your account at all. If they show up there, the issue is local to one device — try logging out and back in on that device.

If your codes were created offline and you've since lost access to that device, they cannot be recovered from the server because they were never uploaded.

### Does Ente Auth require an account?

No, Ente Auth does not require an account. You can choose to use the app without backups if you prefer.

### Will I lose my offline codes if I create an account later?

No. When you sign in after using Ente Auth offline, the desktop app migrates any remaining offline codes into the newly created account so you keep them.

> [!NOTE]
>
> The app will still recommend you to export your codes first before starting the sign in, so you have your own copy in case something unexpected happens during the sign-in.

### Can I use Ente Auth on multiple devices and sync them?

Yes, you can download Ente Auth on multiple devices and sync the codes with end-to-end encryption.

### Do you support exporting to Google Authenticator format? {#export-google-authenticator}

Yes, you can export your codes as HTML QR codes and then scan them in Google Authenticator to import them.

**To export for Google Authenticator:**

1. Open `Settings > Data > Export`
2. Select "Plain HTML"
3. Acknowledge the security warning (this export is unencrypted)
4. Save or share the HTML file
5. Open the HTML file in a browser
6. Use Google Authenticator's "Scan a QR code" feature to scan each QR code from the HTML page

The HTML export generates individual QR codes for each of your codes, making it easy to import them into Google Authenticator or other compatible authenticator apps.

> [!IMPORTANT]
>
> This export is unencrypted. Handle the exported HTML file carefully and delete it after importing your codes.

### What information about my codes is stored on Ente server?

Due to E2EE, the server doesn't know anything about your codes. Everything is encrypted, including the tags, type, account, issuer, notes, pinned or trash status, etc.

### Why do some Google Authenticator codes fail to import? {#google-authenticator-import-failed}

Google Authenticator exports some codes in a format that other authenticator apps may not be able to read correctly. This can happen especially with Google account entries.

If a code fails to import, re-add it directly from the original service:

1. Open that service's security or 2FA settings.
2. Remove the existing authenticator setup.
3. Set it up again.
4. Scan the new QR code using Ente Auth.
5. Save the backup or recovery codes provided by the service.

Codes that imported successfully continue working normally.

### What does it mean when I receive a message saying that my current device isn't powerful enough to verify my password?

This means that the parameters that were used to derive your master-key on your original device, are incompatible with your current device (likely because it's less powerful).

If you recover your account using your current device and reset the password, a new key will be generated with different parameters. This new key will be equally strong and compatible with both devices.

### Why do I get verification errors when signing in on a new device, but it works hours later? {#login-fails-low-ram}

When you sign in to Ente Auth, the app performs a deliberately heavy cryptographic step that needs around 1 GB of free RAM on the device. This is part of how we keep your password secure. If a lot of other apps are running in the background, there often isn't enough free memory available and the sign-in fails. After a few hours, the operating system clears out enough background apps to free up that memory, which is why it eventually works.

This is more likely on phones and tablets with 2-3 GB of RAM (older models such as iPhone 7, 8, SE, or older iPads).

Try the following:

1. Restart your device, then open Ente Auth immediately before other apps load.
2. Close other apps (swipe them away in the app switcher) and try again.
3. In the meantime, access your codes at [auth.ente.com](https://auth.ente.com) in a browser on another device.

### I can't change my app lock PIN. What do I do? {#cant-change-app-lock-pin}

If the option to change the PIN doesn't appear, log out by tapping the back arrow on the app lock screen. Once logged out, the app lock is no longer in effect and you can set it up again from scratch when you sign back in.

### Codes won't sync, password is rejected, or recovery key keeps failing. Where do I start? {#sync-password-recovery-failures}

Most of these failures come from network-level filtering between your device and our servers. Common causes:

- DNS-level blockers like NextDNS, AdGuard, or Pi-hole filtering one of `*.ente.io`, `*.ente.com`, or `*.backblazeb2.com`.
- A custom Private DNS server on your phone.
- A VPN routing traffic in a way that interferes with Ente endpoints.

If you use any of these, allowlist Ente's domains or temporarily disable the blocker and try again. After clearing the interference, signing in and syncing should work normally.
