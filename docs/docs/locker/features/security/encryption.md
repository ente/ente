---
title: Encryption
description: How Ente Locker protects your data with end-to-end encryption so only you can access it
---

# Encryption

Ente Locker uses end-to-end encryption to protect your data. Your information is encrypted on your device before being sent to our servers - we can't see your data, and neither can anyone else.

## What this means for you

- **Your data is private**: Only you (and people you share with) can see your information
- **We can't access your data**: Even Ente employees cannot read your content
- **Your data is safe if we're breached**: Attackers would only get encrypted data they can't read

## How it works

1. You create or edit an item
2. Your device encrypts the data using your encryption keys
3. The encrypted data is uploaded to Ente's servers
4. When you need the data, it's downloaded to your device
5. Your device decrypts the data for you to view

## What is encrypted

Everything in Locker is encrypted:

- Item titles and content
- Uploaded files
- Collection names
- Metadata
- Sharing information

## Your keys

### Password

Your password protects your account. Choose a strong, unique password.

### Recovery key

Your recovery key is a 24-word phrase that can recover your account if you forget your password. Store it securely. If you lose it, you can recover the account only if you previously set up [Legacy recovery](/locker/features/legacy/).

### Collection keys

Each collection has its own encryption key. This allows secure sharing without exposing your main keys.

## Security audits

Ente's encryption has been audited by Cure53, a prominent German cybersecurity firm. Read more about our [security audits](https://ente.com/blog/cryptography-audit/).

## Technical details

For those interested in the specifics:

- **Encryption**: XChaCha20 and XSalsa20
- **Authentication**: Poly1305 MAC
- **Key derivation**: Argon2id

These algorithms are implemented using [libsodium](https://libsodium.gitbook.io/doc/), an externally audited cryptographic library.

## Related FAQs

- [How is my data encrypted?](/locker/faq/security#locker-encryption-method)
- [Can Ente see my data?](/locker/faq/security#locker-zero-knowledge)
- [Is my data safe if Ente is breached?](/locker/faq/security#locker-breach-safety)
