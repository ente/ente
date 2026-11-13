---
title: Legacy FAQ
description: Common questions about digital inheritance, trusted contacts, and Legacy Kits in Ente Locker
---

# Legacy FAQ

Answers to common questions about Legacy recovery in Ente Locker.

## General

### What is Legacy? {#locker-legacy-what-is}

Legacy is Ente's digital inheritance and account recovery system. It helps someone you trust recover your Ente account if you lose access, are incapacitated, or are no longer around.

Ente Locker supports two Legacy options:

- **Trusted contacts**: Another Ente user can recover your account after a waiting period.
- **Legacy Kits**: Physical recovery sheets can be combined in a browser to start account recovery.

### What happens after the waiting period? {#locker-legacy-waiting-period}

After the waiting period passes without the account owner blocking recovery, the recovery flow can reset the account password. After the password reset, the person completing recovery can access the recovered Ente account.

### What happens to 2FA during recovery? {#locker-legacy-2fa-recovery}

During the recovery password reset flow, Ente removes two-factor authentication and passkey second factors so the recovered account can be accessed with the new password.

### Does Legacy work across all Ente apps? {#locker-legacy-all-apps}

Legacy recovers your Ente account. It is not limited to a single Locker item, collection, or app-specific vault.

## Trusted Contacts

### How do I add a trusted contact? {#locker-legacy-add-contact}

**On mobile:**

1. Open Ente Locker.
2. Open the Locker menu.
3. Tap **Legacy**.
4. Tap **Add Trusted Contact**.
5. Enter their Ente email address.
6. Wait for them to accept the invite.

The contact must already have an Ente account.

### Do trusted contacts need an Ente account? {#locker-legacy-need-account}

Yes. Trusted contacts must have their own Ente account. They do not need an active subscription, but they must have an account to participate in trusted contact recovery.

### Why do trusted contacts need to accept the invite? {#locker-legacy-accept-invite}

Accepting the invite confirms that the trusted contact understands their responsibility and agrees to participate. They can decline if they do not want the responsibility.

### Can I customize the trusted contact waiting period? {#locker-legacy-custom-waiting-period}

Yes. Choose from three trusted contact waiting periods:

- **7 days**
- **14 days**
- **30 days** (default)

Configure this from the Legacy page in Ente Locker.

### Can I have multiple trusted contacts? {#locker-legacy-multiple-contacts}

Yes. Add multiple trusted contacts. Each accepted trusted contact can independently initiate recovery, and any one of them can complete recovery after the waiting period if you do not block the attempt.

### How does a trusted contact initiate recovery? {#locker-legacy-initiate-recovery}

**On mobile:**

1. Open Ente Locker.
2. Open the Locker menu.
3. Tap **Legacy**.
4. Find the account under **Legacy accounts**.
5. Tap the account and confirm recovery.

The account owner is notified immediately.

### Can I block a trusted contact recovery attempt? {#locker-legacy-block-recovery}

Yes. During the waiting period, open **Legacy**, open the recovery warning, and block the attempt.

Blocking is immediate and stops that recovery attempt. Consider removing the trusted contact if the attempt was unauthorized.

### How do I remove a trusted contact? {#locker-legacy-remove-contact}

**On mobile:**

1. Open Ente Locker.
2. Open the Locker menu.
3. Tap **Legacy**.
4. Tap the trusted contact.
5. Select **Remove**.

They immediately lose the ability to initiate recovery.

### Can I change who my trusted contacts are? {#locker-legacy-change-contacts}

Yes. Add and remove trusted contacts at any time.

### What happens if I remove a trusted contact during recovery? {#locker-legacy-remove-during-recovery}

Removing a trusted contact who has initiated recovery blocks that recovery attempt. They lose the ability to complete it.

### What notifications are sent during trusted contact recovery? {#locker-legacy-notifications}

When trusted contact recovery is initiated:

- The account owner receives an email notification.
- The account owner sees an alert in the app.
- The trusted contact can see the recovery status.

### Can I initiate recovery if the account owner is alive? {#locker-legacy-alive-owner}

Technically yes, but the account owner is notified and can block recovery. Only initiate recovery when appropriate, such as when the owner is incapacitated, deceased, or has asked for help.

## Legacy Kits

### What is a Legacy Kit? {#locker-legacy-kit-what-is}

A Legacy Kit is a set of 3 physical recovery sheets for your Ente account. Any 2 sheets from the same kit can start account recovery in a browser. One sheet by itself is not enough.

Legacy Kit sheets do not contain your account recovery key and do not directly log anyone into your account. They reconstruct a separate kit secret that opens a scoped recovery session.

Learn more about [Legacy Kits](/locker/features/legacy/legacy-kits).

### How is a Legacy Kit different from a trusted contact? {#locker-legacy-kit-vs-trusted-contact}

A trusted contact is another Ente user who accepts responsibility for helping recover your account.

A Legacy Kit is physical. You create 3 recovery sheets and store or share them separately. The helper only needs any 2 sheets and a browser; they do not need an Ente account.

### Does a Legacy Kit helper need an Ente account? {#locker-legacy-kit-helper-account}

No. A helper using a Legacy Kit does not need Ente installed and does not need an Ente account. They use the recovery URL printed on the sheet.

### Can one recovery sheet recover my account? {#locker-legacy-kit-one-sheet}

No. A Legacy Kit uses 3 recovery sheets, and any 2 of the 3 are required. One sheet alone is not enough to start recovery.

### Which waiting periods are available for Legacy Kits? {#locker-legacy-kit-waiting-periods}

Choose one wait time for each kit:

- **Immediate**
- **1 day**
- **7 days** (default)
- **15 days**
- **30 days**

The selected wait time applies when recovery starts. Changes apply to future attempts only, and the wait time cannot be changed while a recovery attempt is active.

### What happens if I delete a kit or block recovery? {#locker-legacy-kit-delete-block}

Blocking recovery cancels the current active recovery attempt. The kit remains usable, so someone with 2 sheets can start another attempt later.

Deleting a kit disables those sheets for future recovery and blocks any pending active recovery attempt for that kit.

### How many Legacy Kits can I create? {#locker-legacy-kit-limit}

Create up to 5 non-deleted Legacy Kits. Deleted kits stop counting toward the limit.

Only one active recovery attempt is allowed per kit.

### Does a Legacy Kit work across all Ente apps? {#locker-legacy-kit-all-apps}

A Legacy Kit recovers your Ente account. It is not limited to Locker documents or one specific Ente app.

### Are Legacy Kit recovery details proof of identity? {#locker-legacy-kit-audit-hints}

No. Recovery details such as sheet numbers, IP address, and user agent are audit hints only. They do not prove who handled the sheets.

### What should I know before printing Legacy Kit sheets? {#locker-legacy-kit-printing}

Store sheets separately. Printed sheets may show the human-readable sheet name, so avoid sensitive names.

Legacy Kits do not currently have kit nicknames or a Verify kit flow. Kit labels are based on the 3 sheet names.

## Security

### Is Legacy secure? {#locker-legacy-security}

Legacy is designed around delayed, owner-notified recovery:

- Account owners are notified when recovery starts.
- Recovery can be blocked during the waiting period.
- Trusted contacts must be verified Ente users.
- Legacy Kits require any 2 of 3 sheets and do not embed the account recovery key.

### What if someone tries to recover my account without permission? {#locker-legacy-unauthorized}

You are notified when recovery starts. Open Ente Locker, open **Legacy**, and block the recovery attempt. If a trusted contact started the attempt without permission, consider removing them.

## Related Features

- [Legacy feature overview](/locker/features/legacy/)
- [Legacy Kits](/locker/features/legacy/legacy-kits)
- [Encryption](/locker/features/security/encryption)
- [Account security FAQ](/locker/faq/security)
