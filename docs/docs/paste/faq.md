---
title: Ente Paste FAQ
description: Common questions about Ente Paste, one-time encrypted text sharing
---

# Ente Paste FAQ

Common questions about [Ente Paste](https://paste.ente.com).

## Using Paste

### Do I need an Ente account to use Paste? {#paste-account-required}

No. Both creating and opening a paste are anonymous. Paste does not have a sign-in flow.

### How long does a paste last? {#paste-expiry}

A paste lasts until Ente serves the ciphertext to a browser, or 24 hours from creation, whichever comes first. Once consumed, the ciphertext is deleted from Ente's servers and cannot be retrieved.

### Can I open the same paste twice? {#paste-open-twice}

No. A paste can be served only once.

More precisely, the paste is consumed when Ente serves the ciphertext to a browser: for a regular link, on the first open; for a password-protected link, when the recipient first enters a password, even an incorrect one.

> [!NOTE]
>
> If the password is wrong, they can try again in the same tab, because the encrypted paste stays in memory there. Reloading the page, opening the link on a second device, or sharing it onward all result in "This paste has expired or was already opened."

If you need the recipient to be able to refer back to the text, ask them to copy it once they have opened the paste, or use [Ente Locker](/locker/) for durable storage.

### Can I edit or delete a paste after creating it? {#paste-edit-delete}

There is no edit or delete UI. The closest equivalent to delete is to open the link yourself, which consumes it. Otherwise, the paste self-destructs after 24 hours on its own.

### What is the character limit? {#paste-character-limit}

4,000 characters per paste. The counter at the bottom-left of the input shows your current count out of the limit.

### Can I paste binary data or files? {#paste-binary-files}

No. Paste is text-only. For files and durable secrets, use [Ente Locker](/locker/).

### What if I open my own link by accident? {#paste-self-opened}

If you click the link from the create page, Ente shows an "Open One-Time Link?" confirmation with a "Copy link" option, so you can back out without consuming the paste.

If you opened it from elsewhere (for example, by clicking it in your own chat history), the paste is gone. Create a new one.

## Sharing

### How do I share the link? {#paste-share-link}

The link card has three options:

- **Copy** copies the link to your clipboard.
- **Share** opens your operating system's share sheet, falling back to copy if your browser does not support it.
- The QR icon shows a scannable QR code that encodes the full link.

Learn more in [Share the link](/paste/getting-started#share-the-link).

### Will the link show a preview in chat? {#paste-link-preview}

No, by design. If chat apps were allowed to fetch the link for a preview, they would consume the paste before the human recipient saw it. Ente Paste detects link-preview bots and returns "Paste is unavailable" to them without consuming the paste. The recipient still opens the link normally.

Learn more in [Preview-bot protection](/paste/features/security#preview-protection).

### Why does the link have a `#` in the middle? {#paste-fragment-why}

Everything after the `#` is the decryption key. Browsers do not send URL fragments to servers, so Ente cannot see the key. The decryption happens locally in the recipient's browser.

If the `#` portion is missing when the recipient opens the link, decryption is impossible and they see "Missing key in URL". The most common cause is the link getting truncated when it was shared. Copy and paste the link rather than retyping it.

## Security

### Is Paste end-to-end encrypted? {#paste-e2ee}

Yes. The text is encrypted in the sender's browser using [XChaCha20-Poly1305](https://doc.libsodium.org/secret-key_cryptography/secretstream) (via libsodium). Only the ciphertext leaves the device. Ente's servers cannot read the paste.

Learn more in [How encryption works](/paste/features/security).

### Who can read my paste? {#paste-who-can-read}

Anyone who has the full link (including the part after `#`) and, if the paste is password protected, the password. Ente cannot read pastes. The decryption key never reaches Ente's servers.

### What happens if someone intercepts the link? {#paste-intercepted-link}

A regular Paste link is the secret. Anyone with the full link can open the paste. If you are sending the link over a channel you do not fully trust, [enable password protection](/paste/getting-started#password-protection) and send the password separately. A password-protected paste cannot be opened with the link alone.

### Does password protection re-encrypt the paste? {#paste-password-encryption}

Yes. The password is used as input to [Argon2id](https://en.wikipedia.org/wiki/Argon2), a memory-hard key derivation function, alongside the link fragment. The resulting key wraps the actual paste encryption key. Without the right password, decryption fails. The ciphertext cannot be opened by the link alone.

Learn more in [Password protection](/paste/getting-started#password-protection).

### What if I forget the paste password? {#paste-forgot-password}

The paste cannot be recovered. The password is part of the decryption key and was never sent to Ente. Create a new paste with a password you can transmit reliably.

### Is Paste open source? {#paste-open-source}

Yes. The web app source lives in Ente's main monorepo on [GitHub](https://github.com/ente/ente), alongside Ente Photos, Auth, and Locker. The server code is also open source.

## Self-hosting

### Can I self-host Paste? {#paste-self-host}

Yes. The Paste server endpoints are part of [Museum](/self-hosting/), Ente's main backend. The web app endpoint is configured via `apps.public-paste` in `museum.yaml`. Learn more in [Configuration](/self-hosting/installation/config).

## Related topics

- [Introduction to Ente Paste](/paste/): what Paste is and how it works.
- [Send your first paste](/paste/getting-started): create, share, and open flows, including password protection.
- [How encryption works](/paste/features/security): the cryptographic guarantees behind a Paste link.
