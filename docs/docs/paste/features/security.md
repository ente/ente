---
title: How encryption works
description: The cryptographic guarantees behind a one-time Ente Paste link
---

# How encryption works

A Paste link is end-to-end encrypted: the plaintext is encrypted in the sender's browser, only the ciphertext is uploaded, and only the recipient's browser ever sees the plaintext again. This page describes how that works at a level a privacy-conscious non-cryptographer can follow.

## The link format

A Paste link has two parts:

```
https://paste.ente.com/<access-token>#<key-fragment>
```

- The **access token** identifies the paste on Ente's servers. It is what the server uses to find the ciphertext.
- The **key fragment** carries the decryption key. It sits after `#`, which makes it a [URL fragment](https://en.wikipedia.org/wiki/URI_fragment). Browsers never send the fragment portion of a URL to the server, so Ente cannot see it.

For a password-protected paste, the fragment is prefixed with `p-` so the consumer page knows to prompt for a password before attempting decryption.

## Creating a paste

When you click send:

1. The browser generates a fresh 256-bit random key. This is the **paste key**, used to encrypt the text itself.
2. The text is encrypted under the paste key using libsodium's `secretstream` API, which is [XChaCha20-Poly1305](https://doc.libsodium.org/secret-key_cryptography/secretstream) authenticated encryption.
3. The browser generates a 12-character random **fragment secret** that will live in the URL.
4. A second key, the **key-encryption key**, is derived from the fragment secret using [Argon2id](https://en.wikipedia.org/wiki/Argon2) (a memory-hard password hash) with interactive-cost parameters. For password-protected pastes, the input to Argon2id combines the fragment secret with the password the sender entered, and moderate-cost parameters are used.
5. The paste key is encrypted under the key-encryption key using libsodium's `secretbox` (XSalsa20-Poly1305).
6. The browser uploads to Ente: the encrypted text, the encrypted paste key, the Argon2id salt, and the Argon2id ops/memory parameters. The plaintext text, the paste key, the fragment secret, and the password are never sent.

The server hands back an access token. The page constructs the link by concatenating the access token and the fragment secret (with a `p-` prefix if password protection is on).

## Opening a paste

When the recipient opens the link:

1. The browser parses the URL fragment. If it starts with `p-`, the page shows a password prompt and waits for input.
2. The browser asks the server for the ciphertext using the access token. The server deletes the paste in the same step that returns the ciphertext, so it can only ever be served once.
3. The browser re-runs Argon2id locally on the fragment secret (and password, if applicable) using the salt and parameters stored alongside the ciphertext. This produces the same key-encryption key as during creation.
4. The encrypted paste key is decrypted with the key-encryption key, yielding the original paste key.
5. The paste key is used to decrypt the text.

For a wrong password, step 3 produces the wrong key-encryption key, step 4 fails the authentication tag check, and the page shows "Incorrect paste password". The page keeps the encrypted paste in memory, so the recipient can retry in the same tab. If the page is closed or reloaded, the sender needs to create a new paste.

## What Ente's servers store

The server only ever sees ciphertext and KDF parameters:

- The encrypted text and its `secretstream` header.
- The encrypted paste key and its nonce.
- The Argon2id salt and the ops/memory parameters used at creation time.

None of these can be turned back into plaintext without the fragment secret (and, for password-protected pastes, the password). Both live exclusively in the recipient's browser.

## One-time consumption

A Paste link is meant to be opened exactly once. This is enforced on the server, not in the browser.

Before consuming, the consumer page makes a "guard" request that asks the server to issue a short-lived, signed cookie tied to the access token and the recipient's browser. Only then does it make the actual consume request, which the server requires to carry both a custom header (`X-Paste-Consume: 1`) and the matching guard cookie. The consume call deletes the paste from the database in the same transaction that returns the ciphertext, so a paste can never be returned twice.

If the link is never opened, Ente deletes the paste 24 hours after creation.

## Preview-bot protection {#preview-protection}

Chat apps, search engines, and browsers routinely fetch URLs to generate previews or pre-warm caches. For a one-time link, an automated fetch would consume the paste before the human got a chance to read it.

Ente Paste recognizes and refuses these requests on the server side:

- Requests carrying `Purpose: prefetch`, `Sec-Purpose: prefetch`, or `Sec-Purpose: prerender` are treated as preview attempts.
- User agents containing tokens like `bot`, `crawler`, `spider`, `preview`, `slackbot`, `discordbot`, `whatsappbot`, `telegrambot`, `twitterbot`, `facebookexternalhit`, `linkedinbot`, `skypeuripreview`, or `googlebot` are treated as preview attempts.

These requests get back a generic "Paste is unavailable" response and the paste stays intact for the real recipient.

The custom `X-Paste-Consume` header is an additional layer: even a request that does not match a known preview-bot pattern cannot consume a paste unless it sends that header, which only the Paste web app does. This makes accidental consumption by a typical `curl`, `wget`, or browser-prefetch effectively impossible.

## Trust model and limits

A Paste link is as secret as the channel you send it over. Anyone who sees the full link, including the fragment, can open the paste. The threats Paste defends against are:

- A malicious or compromised Ente server: it sees only ciphertext.
- A passive network observer between the recipient and Ente: TLS protects the transport, and the URL fragment is not in the request anyway.
- Link-preview bots and crawlers fetching the link automatically.
- Long-term exposure: every paste self-destructs in 24 hours, opened or not.

The threats Paste does _not_ defend against:

- Someone forwarding the link to a third party before the recipient opens it.
- A screenshot, scrollback, or copy of the plaintext on the recipient's machine after they open it.
- A compromised browser on either side (a malicious extension, for example, could read the plaintext as it is displayed).

For pastes where the channel itself might be compromised (for example, a long-lived chat thread or an email trail), [enable password protection](/paste/getting-started#password-protection) so the link alone is not enough to open the paste.

## Related topics

- [Send your first paste](/paste/getting-started): including password protection and the QR / share options.
- [FAQ](/paste/faq)
