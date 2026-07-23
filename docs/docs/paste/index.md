---
title: Ente Paste
description: Share sensitive text with one-time, end-to-end encrypted links that auto-expire after 24 hours
---

# Ente Paste

Ente Paste is a web app for sharing short sensitive text over a one-time, end-to-end encrypted link. Use it to hand someone an API key, a recovery code, a server password, a snippet, or a private note without leaving a copy lying around in chat history or email.

Open [paste.ente.com](https://paste.ente.com), type or paste your text, and share the link that appears. The first person to open the link reads the text and the paste is destroyed. If nobody opens it, it self-destructs after 24 hours.

No account is required to create or open a paste.

## How it works

1. Type your text into [paste.ente.com](https://paste.ente.com).
2. Click the send button. Ente generates a random key in your browser, encrypts the text with it, and uploads only the ciphertext.
3. Ente returns a link that combines an access token (which the server recognizes) with the encryption key, placed after a `#`.
4. Share the link.
5. When the recipient opens the link, their browser fetches the ciphertext, takes the key out of the URL fragment, and decrypts the text locally. The paste is then deleted from Ente's servers.

The key after `#` is the [URL fragment](https://en.wikipedia.org/wiki/URI_fragment). Browsers never send it to servers, so Ente only ever sees the ciphertext.

You can also [password-protect](/paste/getting-started#password-protection) a paste, in which case the recipient needs both the link and the password to decrypt it. Useful when the link will travel over a channel that you do not fully trust.

## What Paste is for

- One-off secrets: API keys, recovery codes, app passwords, signing keys
- Hand-offs between teammates: a connection string, a short config snippet
- Short instructions you do not want preserved in chat
- Anything you would otherwise paste into chat and immediately regret

If you need durable storage for the same kinds of secrets, use [Ente Locker](/locker/) instead. Paste is for transit.

## Limits

- Up to 4,000 characters per paste.
- One open per link.
- 24 hours to live, after which the paste is deleted whether anyone read it or not.
- One sender or recipient at a time. The paste is consumed by the first successful open.

## Get started

- [Send your first paste](/paste/getting-started): walks through creating, sharing, and opening a paste, including password protection and the share / QR options.
- [How encryption works](/paste/features/security): the cryptographic guarantees behind a Paste link.
- [FAQ](/paste/faq): common questions and what to do when something goes wrong.
