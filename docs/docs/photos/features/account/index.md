---
title: Account
description: Overview of Ente account features, security, and subscription management
---

# Account

Your Ente account is the foundation for securely storing and accessing your photos across all your devices. This page provides an overview of account management, security features, and subscription options.

## Using Ente accounts across products

Your Ente account works across both Ente Photos and Ente Auth. You can use the same account for both products, or create separate accounts for each.

> [!NOTE]
>
> If you use the same account for both Photos and Auth and enable 2FA for your Ente account (stored in Ente Auth), this creates a circular dependency. We recommend either:
>
> - Using separate accounts for Auth and Photos for security
> - Ensuring your recovery key is stored securely (written down on paper) as it can bypass 2FA if you're locked out
> - Using [Passkeys](/photos/features/account/passkeys) or [Legacy](/photos/features/account/legacy/) as additional recovery options
>
> Learn more about this scenario in the [Enteception guide](/auth/faq/enteception/).

## Account Creation

Creating an Ente account involves four steps:

1. **Enter and verify your email address** - Used for login and sharing with others
2. **Create a strong password** - The foundation of your end-to-end encryption
3. **Save your recovery key** - The only way to recover your account if you forget your password
4. **Choose a plan** - Start with 10 GB free or select a paid plan

Learn more in the [Creating an account guide](/photos/getting-started/signup).

## Security

### Password and encryption

Your password is used to encrypt all your photos before they're uploaded to Ente's servers. Only you know your password, which means only you can decrypt and view your files.

**Important security practices:**

- Use a strong, unique password
- Never share your password with anyone
- Store your password in a password manager

You can change your password at any time in Settings without re-encrypting your entire library.

### Recovery key

Your **recovery key is a 24-word phrase** that is the only way to recover your account if you:

- Forget your password AND
- Are logged out of all devices

**How to save it:**

- Write it down on paper and store it securely
- Save it in a password manager
- Store it in any secure location you trust

Without your recovery key, losing your password means permanently losing access to your photos.

Learn more in the [Account Creation FAQ](/photos/faq/account-creation#recovery-key).

### Two-factor authentication (2FA)

Ente supports multiple 2FA methods for additional security:

- **TOTP** (Time-based One-Time Passwords)
- **WebAuthn/FIDO2** for hardware security keys
- **Passkeys** as an alternative 2FA mechanism

Enable 2FA in `Settings > Security` on mobile or desktop apps.

Warning: if you use the same account in Ente Auth, enabling 2FA in Ente Photos also enables it for Ente Auth, which can be a problem if you store your Ente account's 2FA code inside Ente Auth itself. See [Enteception](/auth/faq/enteception/).

Learn more about [Passkeys](/photos/features/account/passkeys).

### End-to-end encryption

Ente uses end-to-end encryption, which means:

- Files are encrypted on your device before upload
- Ente's servers store only encrypted data
- Only you have the keys to decrypt your files
- Even Ente cannot access your photos

**Encryption algorithms:**

- Encryption: XChaCha20 and XSalsa20
- Authentication: Poly1305 MAC
- Key derivation: Argon2id with high parameters

Learn more in the [Security and Privacy FAQ](/photos/faq/security-and-privacy#data-encryption).

## Subscription Plans

### Free plan

Ente offers **10 GB of storage for free, forever**. The free plan includes:

- ✅ Unlimited devices
- ✅ End-to-end encryption
- ✅ Machine learning features
- ✅ Map view and location tags
- ✅ Background sync
- ✅ Creating /receiving shared albums
- ✅ Public links ([device limit](https://ente.com/help/photos/features/sharing-and-collaboration/public-links#device-limits) of 5)

**Free plan limitations:**

- ❌ Cannot create family plans

### Paid plans

Paid plans unlock additional features and storage:

- Multiple storage tiers from 50 GB to multiple TBs
- Monthly and annual billing (annual plans offer better value)
- Ability to create public links with no device limit
- Family plan capability to share storage with 5 family members
- Priority support

See the [pricing page](https://ente.com#pricing) for current plans and pricing.

### Student discounts

Students receive **30% off** subscription plans. Email [students@ente.com](mailto:students@ente.com) from your school email address or provide proof of enrollment.

Discounts are valid for one year and can be renewed.

Learn more in the [Storage and Plans FAQ](/photos/faq/storage-and-plans#student-discount).

## Family Plans

Share your storage with up to 5 family members without paying extra. Each member gets:

- Their own private, encrypted space
- Access to the shared storage pool
- Independent photo libraries (photos aren't shared automatically)

**Key features:**

- Invite up to 5 family members (6 total including you)
- Set individual storage limits per member
- Each member maintains complete privacy
- Share storage, not photos (use sharing features for that)

Learn more in the [Family Plans guide](/photos/features/account/family-plans).

## Payment Methods

Ente accepts multiple payment methods:

**Credit/debit cards** (via Stripe):

- All major card providers
- Available on web, desktop, and Android
- Most secure and recommended method

**PayPal**:

- Annual plans only
- Email [paypal@ente.com](mailto:paypal@ente.com) to request an invoice

**App Store payments**:

- iOS App Store
- Managed by Apple

Ente does not store your payment information. All payments are processed securely through Stripe or the respective payment provider.

Learn more in the [Storage and Plans FAQ](/photos/faq/storage-and-plans#supported-payment-methods).

## Managing Your Account

### Multi-device access

Use the same account across all your devices:

- Install Ente on multiple phones, tablets, and computers
- Use the web app at [photos.ente.com](https://photos.ente.com)
- All devices stay in sync automatically
- Configure backup separately on each device

Learn more in the [Account Creation FAQ](/photos/faq/account-creation#multi-device-login).

### Changing your email

You can change the email address associated with your account at any time in Settings. Your photos and data remain unchanged.

### Subscription management

**Upgrading:**

- Takes effect immediately
- You pay the difference (minus credit for unused time on old plan)
- New renewal date starts from upgrade date

**Downgrading:**

- Takes effect immediately
- Difference is credited to your account
- Credit applied to future renewals

**Canceling:**

- 30-day grace period to export your data
- Data permanently deleted after grace period
- Can renew anytime during grace period

Learn more in the [Storage and Plans FAQ](/photos/faq/storage-and-plans#upgrade-plan).

## Storage Management

### How storage is calculated

Ente calculates storage using GibiBytes (GiB):

- Divides total bytes by `1024 x 1024 x 1024` (not `1000 x 1000 x 1000`)
- This means files appear to use less storage compared to providers using GB
- We display it as "GB" without the "i" for simplicity

### Automatic deduplication

Ente automatically detects and handles duplicates:

- Skips identical files uploaded to the same album
- Creates symlinks for files in multiple albums (storage counted only once)
- Works across all your albums automatically
- No manual action required

Learn more in the [Duplicate detection guide](/photos/features/backup-and-sync/duplicate-detection).

### Storage optimization

Free up space with built-in tools:

- **Free up device space** - Remove backed-up photos from your phone
- **Remove exact duplicates** - Find and delete duplicate files
- **Remove similar images** - Use ML to find visually similar photos

Learn more in the [Storage optimization guide](/photos/features/albums-and-organization/storage-optimization).

## Referral Program

Earn free storage by inviting friends:

- Share your referral code from `Settings > Referrals`
- When friends upgrade to a paid plan, both of you get **10 GB free**
- Maximum earned storage equals your plan size (double your storage)
- Earned storage lasts as long as your subscription is active

Learn more in the [Referral program guide](/photos/features/account/referral-program/).

## Account Recovery and Legacy

### Recovery options

If you lose access to your account:

- Use a logged-in device to reset your password
- Use your recovery key if logged out of all devices
- Contact support if you lose access to your email

### Legacy (Trusted Contacts)

Ente offers a legacy feature that allows you to designate trusted contacts who can access your account if something happens to you.

Learn more in the [Legacy guide](/photos/features/account/legacy/).

## Related topics

- [Passkeys](/photos/features/account/passkeys) - Use passkeys for two-factor authentication
- [App lock](/photos/features/account/app-lock) - Add a lock screen for the Ente Photos app
- [Family Plans](/photos/features/account/family-plans) - Share storage with family members
- [Referral Program](/photos/features/account/referral-program/) - Earn free storage by inviting friends
- [Legacy](/photos/features/account/legacy/) - Designate trusted contacts for account recovery

## Related FAQs

**Getting Started:**

- [How do I create a new Ente account?](/photos/faq/account-creation#create-account)
- [How do I log in on multiple devices?](/photos/faq/account-creation#multi-device-login)
- [What is the recovery key and why is it important?](/photos/faq/account-creation#recovery-key)

**Security:**

- [Can Ente see my photos?](/photos/faq/security-and-privacy#can-ente-see-photos)
- [How is my data encrypted?](/photos/faq/security-and-privacy#data-encryption)
- [Does Ente support two-factor authentication (2FA)?](/photos/faq/account-creation#2fa)

**Plans and Storage:**

- [What plans does Ente offer?](/photos/faq/storage-and-plans#available-plans)
- [What are the limitations of the free plan?](/photos/faq/storage-and-plans#free-plan-limits)
- [Does Ente have Family Plans?](/photos/faq/storage-and-plans#family-plans-faq)
- [How can I earn free storage?](/photos/faq/storage-and-plans#earn-storage-referrals)
