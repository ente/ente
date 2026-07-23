---
title: Lock Screen
description: Add an extra layer of security with Face ID, Touch ID, fingerprint, or PIN protection
---

# Lock Screen

Lock screen adds an extra layer of protection to your Locker app. Even if someone has access to your unlocked phone, they can't open Locker without authenticating.

## Available authentication methods

### Biometric

Use your device's biometric authentication:

- **Face ID** (iOS)
- **Touch ID** (iOS)
- **Fingerprint** (Android)
- **Face unlock** (Android, device dependent)

### PIN

Set a numeric PIN code as an alternative or backup to biometric authentication.

## Enabling lock screen

1. Open Ente Locker
2. Open `Settings > Security`
3. Tap **Lock screen**
4. Choose your authentication method:
    - **Biometric**: Uses your device's biometric settings
    - **PIN**: Set a numeric PIN
5. Confirm your choice

## Configuring lock screen

### Auto-lock timing

Set when Locker automatically locks:

1. Open `Settings > Security`
2. Tap **Auto-lock**
3. Choose a timing option:
    - **Immediately**: Locks when you leave the app
    - **After 1 minute**: Locks after 1 minute of inactivity
    - **After 5 minutes**: Locks after 5 minutes of inactivity
    - **Never**: Only locks when you manually lock or restart the app

### Lock on app switch

Lock Locker whenever you switch to another app:

1. Open `Settings > Security`
2. Enable **Lock on app switch**

## Using lock screen

### Unlocking

When Locker is locked:

1. Open the app
2. Authenticate with your chosen method (biometric or PIN)
3. The app unlocks and shows your content

### Manual locking

Lock Locker manually without closing the app:

1. Open `Settings > Security`
2. Tap **Lock now**

Or close and reopen the app (if auto-lock is set to "Immediately").

## Fallback options

If biometric authentication fails:

1. Most devices allow multiple attempts
2. After several failures, you may need to use your device passcode
3. If PIN is enabled as backup, you can use that instead

## Security considerations

- Lock screen protection only works when your device is unlocked
- For maximum security, also secure your device with a strong passcode
- Biometric data is handled by your device, not Ente

## Related FAQs

- [What happens if biometric authentication fails?](/locker/faq/security#locker-biometric-fail)
- [Can I change my PIN?](/locker/faq/security#locker-change-pin)
- [Is lock screen available on all devices?](/locker/faq/security#locker-lock-screen-availability)
