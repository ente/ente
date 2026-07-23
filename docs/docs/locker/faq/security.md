---
title: Security FAQ
description: How Ente Locker protects your data with end-to-end encryption and zero-knowledge architecture
---

# Security FAQ

Answers to common questions about security, encryption, and privacy in Ente Locker.

## Encryption

### How is my data encrypted? {#locker-encryption-method}

Ente Locker uses industry-standard encryption:

- **Encryption**: XChaCha20 and XSalsa20
- **Authentication**: Poly1305 MAC
- **Key derivation**: Argon2id

Your data is encrypted on your device before upload. Only you can decrypt it.

Learn more about [Encryption](/locker/features/security/encryption).

### Can Ente see my data? {#locker-zero-knowledge}

No. Ente operates on a zero-knowledge model:

- Your encryption keys never leave your devices
- Data is encrypted before upload
- Ente's servers only store encrypted data
- We cannot decrypt your data even if required to

### Is my data safe if Ente is breached? {#locker-breach-safety}

Yes. In the event of a server breach:

- Attackers would only get encrypted data
- Without your password, the data cannot be decrypted
- End-to-end encryption protects your content

Your data is as safe as your password is strong.

### Where is my data stored? {#locker-data-location}

Your encrypted data is stored redundantly across multiple providers in the EU:

- Amsterdam, Netherlands
- Paris, France
- Frankfurt, Germany

We store 3 copies across 3 providers in 3 countries for reliability.

## Account Security

### What is the recovery key? {#locker-recovery-key}

Your recovery key is a 24-word phrase that can recover your account if you forget your password. It's generated when you create your account.

**Critical**: Store your recovery key securely. Without it, you cannot recover your account if you forget your password and are logged out of all devices, unless you previously set up [Legacy recovery](/locker/features/legacy/).

### I forgot my password. How do I recover my account? {#locker-forgot-password}

**If you're logged in on any device:**

1. Open `Settings > Account > Change password`
2. Follow the prompts to set a new password

**If you're logged out of all devices:**

1. Open the login screen
2. Tap **Forgot Password**
3. Enter your recovery key (24 words)
4. Create a new password

**If you've lost both your password and recovery key:**

Your account cannot be recovered unless you previously set up [Legacy recovery](/locker/features/legacy/). This is by design - it ensures no one else can access your data either.

### Does Locker support two-factor authentication? {#locker-2fa-support}

Yes. Enable 2FA in `Settings > Account > Two-factor authentication`.

We support:

- Time-based One-Time Passwords (TOTP)
- Hardware security keys (WebAuthn/FIDO2)

### Can I change my password? {#locker-change-password}

Yes. Open `Settings > Account > Change password`, enter your current password, then set a new one.

Your data does not need to be re-encrypted when you change your password.

### Is my account shared with Ente Photos? {#locker-shared-account}

Yes. Ente Locker, Ente Photos, and Ente Auth use the same account. Your password, recovery key, and 2FA settings apply to all Ente products.

Your data in each product remains separate.

## Lock Screen

### What happens if biometric authentication fails? {#locker-biometric-fail}

After multiple failed attempts:

- Your device may require its passcode instead
- If PIN is configured in Locker, you can use that as fallback
- The app remains locked until successful authentication

### Can I change my PIN? {#locker-change-pin}

Yes. Open `Settings > Security > Lock screen > Change PIN` and follow the prompts.

### Is lock screen available on all devices? {#locker-lock-screen-availability}

Lock screen is available on all iOS and Android devices. The specific biometric options depend on your device capabilities:

- **iOS**: Face ID, Touch ID
- **Android**: Fingerprint, face unlock (device dependent)

## Related Features

- [Encryption](/locker/features/security/encryption)
- [Lock screen](/locker/features/security/lock-screen)
