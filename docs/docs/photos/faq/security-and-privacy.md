---
title: Security and Privacy FAQ
description: Comprehensive information about security and privacy measures in Ente Photos
---

# Security and Privacy FAQ

Welcome to Ente Photos' Security and Privacy FAQ. This document provides detailed information about our security practices, privacy measures, and how we protect your data. We are committed to maintaining the highest standards of data protection and transparency.

## Data Encryption and Storage

### Can Ente see my photos and videos? {#can-ente-see-photos}

No. Your files are encrypted on your device before being uploaded to our servers. The encryption keys are derived from your password using advanced key derivation functions. Since only you know your password, only you can decrypt your files. For technical details, please see our [architecture document](https://ente.com/architecture).

### Can Ente see the metadata of my photos and videos? {#can-ente-see-metadata}

No. Just like the photos and videos, all metadata (including exif creation time, location, description etc) is also end-to-end encrypted.

### How is my data encrypted? {#data-encryption}

We use the following encryption algorithms:

- Encryption: `XChaCha20` and `XSalsa20`
- Authentication: Poly1305 message authentication code (MAC)
- Key derivation: Argon2id with high memory and computation parameters

These algorithms are implemented using [libsodium](https://libsodium.gitbook.io/doc/), a externally audited cryptographic library. Our [architecture document](https://ente.com/architecture) provides full technical specifications.

### Where is my data stored? {#data-storage-location}

Your encrypted data is stored redundantly across multiple providers in the EU:

- Amsterdam, Netherlands
- Paris, France
- Frankfurt, Germany

We use a combination of object storage and distributed databases to ensure high availability and durability. Our [reliability document](https://ente.com/reliability) provides in-depth information about our storage infrastructure and data replication strategies.

In short, we store 3 copies of your data, across 3 different providers, in 3 different countries. One of them is in an underground fall-out shelter in Paris.

### How does Ente's encryption compare to industry standards? {#encryption-comparison}

Our encryption model goes beyond industry standards. While many services use server-side encryption, we implement end-to-end encryption. This means that even in the unlikely event of a server breach, your data remains protected.

## Account Security

### What happens if I forget my password? {#account-recovery}

If you are logged into Ente on any of your existing devices, you can use that device to reset your password and use your new password to log in.

If you are logged out of Ente on all your devices, you can reset your password using your recovery key that was provided to you during account creation.

If you are logged out of Ente on all your devices and you have lost both your password and recovery key, we cannot recover your account or data due to our end-to-end encrypted architecture.

If you wish to delete your account in such scenarios, please reach out to support@ente.com and we will help you out.

### What is my recovery key and why is it critical? {#recovery-key-importance}

Your **recovery key is a 24-word phrase** that is the ONLY way to recover your account if you:

- Forget your password AND
- Are logged out of all devices

**Critical information about recovery keys:**

⚠️ **Ente support CANNOT provide or regenerate your recovery key**. Due to end-to-end encryption, we never have access to your recovery key or your encrypted data.

⚠️ **Without your recovery key, losing your password means permanently losing access** to all your photos if you're logged out everywhere.

⚠️ **Your recovery key is different from verification codes**. Verification codes are temporary 6-digit numbers sent to your email. Your recovery key is a permanent 24-word phrase.

The same Ente account uses the same recovery key in Photos, Auth, and Locker. Separate accounts have separate keys. Backup-code lists issued by other websites belong to those websites and cannot be used as your Ente recovery key. Learn [which recovery key or backup codes you need](/auth/faq/#recovery-key-or-backup-codes).

### How do I find my recovery key? {#find-recovery-key}

If you previously downloaded your recovery key, search your Downloads folder for `ente-recovery-key.txt` (or search for `recovery-key.txt`). If you saved it elsewhere, check that folder too. Keep the file private.

**If you're still logged in to Ente on any device:**

Open `Settings > Account > Recovery key`, enter your password to view your 24-word recovery key, and save it in a secure location. Keep that device signed in while you resolve any access problems.

**If you're logged out of all devices:**

If you still know your password and can complete the required sign-in checks, sign in and save your recovery key. If you have lost access to a second factor, see [recovering access to 2FA](#two-factor-auth).

If you have lost both your password and recovery key, Ente support cannot reconstruct your encryption keys or decrypt your data. See [account recovery](#account-recovery) for the available recovery options.

### How should I store my recovery key? {#store-recovery-key}

**Recommended methods:**

1. **Password manager**: Store it in a reputable password manager (1Password, Bitwarden, etc.)
2. **Physical paper**: Write it down and store it in a safe place (fireproof safe, safety deposit box)
3. **Encrypted notes**: Save it in an encrypted notes app with a different password
4. **Multiple locations**: Store copies in 2-3 different secure locations

**DO NOT:**

- Store it in an unencrypted file on your computer
- Email it to yourself
- Share it with anyone (not even Ente support)
- Take a screenshot and leave it in your photos
- Store it only in one location

**Best practice**: When you first create your Ente account, immediately save your recovery key before uploading any photos.

### How do I use my recovery key to reset my password? {#use-recovery-key}

If you've forgotten your password and are logged out everywhere:

1. Open the login page.
2. Enter your email address.
3. Choose **Forgot Password** and complete the sign-in checks shown by the app.
4. Enter the 24 words of your recovery key in their original order.
    - Separate words with a single space.
    - Use lowercase letters without punctuation or manually inserted line breaks.
    - The field may wrap text automatically; do not press Enter between words.
5. Create a new password.
6. Sign in with the new password.

**Common issues:**

- **Invalid recovery key:** Check for typos, missing or reordered words, extra spaces, and manually inserted line breaks. Use the key for this Ente account and server.
- **Wrong kind of code:** Your Ente recovery key is a 24-word phrase. An email verification code or another website's backup codes cannot replace it.
- **Error after submitting:** A generic error can also involve a connection problem. See [verification troubleshooting](/auth/faq/#sync-password-recovery-failures) before repeating the reset.
- **Still unable to continue:** Contact [support@ente.com](mailto:support@ente.com) with the error text and app version. Never send the recovery words or your password. Support cannot reconstruct your recovery key or decrypt your data.

### Can I change my password? {#change-password}

Yes, you can change your password at any time from our apps. Our architecture allows password changes without re-encrypting your entire library.

The privacy of your account is a function of the strength of your password, please choose a strong one.

### Do you support two-factor authentication (2FA)? {#two-factor-auth}

Yes, we recommend enabling 2FA for an additional layer of security. We support:

- Time-based One-Time Passwords (TOTP)
- WebAuthn/FIDO2 for hardware security keys

You can set up 2FA in the settings of our mobile or desktop apps.

Warning: if you use the same account in Ente Auth, enabling 2FA in Ente Photos also enables it for Ente Auth, which can be a problem if you store your Ente account's 2FA code inside Ente Auth itself. See [Enteception](/auth/faq/enteception/).

If you lose access to your authenticator or passkey, use your Ente recovery key through the recovery option shown during sign-in. If you also cannot find the recovery key but still know your password, contact [support@ente.com](mailto:support@ente.com) from your registered email address. After verifying account ownership, support may be able to help with the lost second factor. Email access alone is not sufficient, and assistance is not guaranteed.

Tell support whether you are being asked for an authenticator code, a passkey, or both, since these can be separate sign-in checks. Never send your password, recovery key, authenticator setup key, or current codes. Support cannot decrypt your data or replace a forgotten password without an available recovery method.

### Can I use app lock to protect Ente Photos? {#app-lock}

Yes. You can protect the Ente Photos app with an additional lock screen.

- Choose **Device lock**, **PIN lock**, or **Password lock**
- Configure **Auto lock** to lock the app automatically after a chosen delay
- Enable **Hide content** in the mobile app to hide app previews in the app switcher

Open `Settings > Security > App lock` on mobile, or `Settings > Preferences > App lock` on desktop.

Learn more in the [App lock guide](/photos/features/account/app-lock).

### Can I let someone browse my photos without giving them access to my whole library? {#guest-view}

Yes. Use guest view to hand your phone to someone else and let them browse a single photo, a set of selected photos, or an entire album, without reaching the rest of your library, settings, or actions like edit, share, or delete.

Guest view can only be exited with device authentication (Face Recognition, Fingerprint, or your device passcode/password), so the person can't leave guest view on their own.

Guest view is available on mobile only.

Learn more in the [Guest view guide](/photos/features/utilities/guest-view).

### Can I contact support using PGP? {#support-pgp}

Yes. You can send encrypted messages to [pgp@ente.com](mailto:pgp@ente.com). The public key is published on [openpgp.org](https://keys.openpgp.org/) and is also available at [ente.com/pgp/pgp.asc](https://ente.com/pgp/pgp.asc). The fingerprint is `D71B F781 998B 4AED 01A2  0AF6 02BD D83A 56EA 68E2`.

## Sharing and Collaboration

### How does sharing work? {#sharing-encryption}

The information required to decrypt an album is encrypted with the recipient's public key such that only they can decrypt them.

You can read more about this [here](https://ente.com/architecture#sharing).

In case of sharable links, the key to decrypt the album is appended by the client as a [fragment to the URL](https://en.wikipedia.org/wiki/URI_fragment), and is never sent to our servers.

Please note that only users on the paid plan are allowed to share albums. The receiver just needs a free Ente account.

## Security Audits

## Has the Ente Photos app been audited by a credible source?

Yes, Ente Photos has undergone multiple thorough security audits.

Our first assessment was carried out by Cure53 in collaboration with Symbolic Software. Cure53 is a prominent German cybersecurity firm, while Symbolic Software specializes in applied cryptography. Please find the full report here: https://ente.com/blog/cryptography-audit/

A second more recent audit was completed on behalf of CERN. Details of that are available here: https://ente.com/blog/cern-audit/

## Machine Learning and Privacy {#ml-privacy}

### Is my face data used to train AI models? {#face-data-privacy}

No. All machine learning (face recognition and magic search) happens entirely on your device. Your photos are downloaded to your device, indexed locally, and the indexes are encrypted before being synced across your devices.

Ente's servers never receive:

- Your unencrypted photos
- Face recognition data
- Search indexes
- Any information about what's in your photos

Your photos and ML data are never used to train any AI models, neither by Ente nor by any third parties.

### How does on-device ML maintain privacy? {#ml-privacy-details}

Machine learning in Ente maintains the same end-to-end encryption guarantees as the rest of the app:

- **Local processing**: All face detection, recognition, and magic search analysis happens on your device
- **Encrypted indexes**: ML-generated indexes are encrypted before syncing to other devices
- **Zero server knowledge**: Ente's servers cannot see your photos, faces, or search data
- **No third-party services**: ML models run entirely within the Ente app - no external AI services are used

Your machine learning data receives the same end-to-end encryption as your photos, ensuring complete privacy.

Learn more about [Machine learning features](/photos/features/search-and-discovery/machine-learning).

### Are my location tags encrypted? {#location-tags-encrypted}

Yes! Location tags are stored end-to-end encrypted, just like your photos. When you create a location tag, all the location data (coordinates, radius, and tag name) is encrypted on your device before being synced.

Ente's servers cannot see your location tags or where your photos were taken. All location-based searches happen locally on your device.

## Account Management

### How can I delete my account? {#delete-account}

You can delete your account at any time by using the "Delete account" option in the settings. For security reasons, we request you to delete your account on your own instead of contacting support to ask them to delete your account.

Note that Ente Photos, Ente Auth, and Ente Locker data will be deleted when you delete your account (irrespective of which app you delete it from) since Photos, Auth, and Locker use the same underlying account.

To know details of how your data is deleted, including when you delete your account, please see https://ente.com/blog/how-ente-deletes-data/.

### Will deleting my Ente Auth or Locker account also delete my Photos account? {#shared-account-deletion}

Yes, if you use the same Ente account in those apps. **Delete account** deletes that account and its Photos, Auth, and Locker data, no matter which app you select it from.

If you want to stop using just one app:

1. Check which Ente account you are signed in to in each app.
2. Sign out of or uninstall the app you no longer want to use. Do not select **Delete account**.

Your account and data in the other apps stay available. If you created separate Ente accounts, deleting one does not delete the others.

## Trust and Reliability

### Why should I trust Ente for long-term data storage? {#trust}

**Our mission**: Unlike large tech companies with multiple products, we have one focused mission - to build a safe space where you can easily archive your personal memories for the long term.

**Financial sustainability**: Our pricing model allows us to profitably provide this service without relying on advertising or selling your data. This means we can focus entirely on serving our users.

**Security and transparency**:

- Your data is preserved with end-to-end encryption
- Our open-source apps have been [externally audited](https://ente.com/blog/cryptography-audit/) by Cure53
- We store 3 copies of your data across 3 different providers in 3 different EU countries
- Our [reliability documentation](https://ente.com/reliability) transparently details our data replication and disaster recovery plans

**Long-term commitment**: We love what we do, have no reasons to be distracted by other ventures, and are committed to being as reliable as any service can be.

If you'd like to support this project, please consider [subscribing](https://ente.com/download).

## Additional Support

For any security or privacy questions not covered here, please contact our team at security@ente.com. We're committed to addressing your concerns and continuously improving our security measures.

## Security

If you believe you have found a security vulnerability, please responsibly disclose it by emailing security@ente.com or [using this link](https://github.com/ente/ente/security/advisories/new) instead of opening a public issue. We will investigate all legitimate reports. To know more, please see our [security policy](https://github.com/ente/ente/blob/main/SECURITY.md).
