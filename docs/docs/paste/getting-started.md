---
title: Send your first paste
description: Walk through creating, sharing, and opening an Ente Paste link
---

# Send your first paste

This page walks through both sides of a paste: creating a link as the sender, and opening it as the recipient.

## Create a paste

1. Open [paste.ente.com](https://paste.ente.com).
2. Click into the text area and enter your text. The counter at the bottom-left of the input shows characters used out of the 4,000 limit, and turns highlighted as you near the limit.
3. (Optional) Click the lock icon next to the counter to require a password. See [Password protection](#password-protection) below.
4. Click the send button (the arrow icon at the bottom-right of the input). If password protection is on, enter the password twice in the dialog that appears, then click "Create".

Ente encrypts the text in your browser and uploads only the ciphertext. The page then shows your one-time link.

> [!NOTE]
>
> The text is encrypted locally before any network request leaves your browser. Ente's servers never see the plaintext or the decryption key.

## Password protection

A password-protected paste requires the recipient to enter a password before the text is decrypted. The password is _not_ stored on Ente's servers and is _not_ embedded in the link. It travels separately, typically over a different channel from the link itself.

This is useful when you want the link and the secret needed to read it to live in different places. For example, send the link in email and the password in Signal, or read the password aloud over the phone.

**To enable it:** click the lock icon next to the character counter before sending. The icon switches from open to closed. After clicking send, Ente prompts for a password. Enter the same password twice and click "Create".

### How it strengthens the paste

A normal paste is protected by a 12-character random key in the URL fragment. Anyone with the full link can decrypt the paste. The link _is_ the secret.

A password-protected paste splits the secret in two:

- The 12-character fragment, in the link.
- The password, sent over a separate channel.

An attacker who intercepts only the link cannot decrypt the paste; they would also need the password. To resist offline brute-force guessing, Ente runs the password through [Argon2id](https://en.wikipedia.org/wiki/Argon2), a memory-hard key derivation function, with moderate-cost parameters (256 MB memory limit). This makes large-scale password guessing expensive even with custom hardware. Learn more in [How encryption works](/paste/features/security).

### Choosing a password

- Use a password the recipient does not already know, so an attacker who compromises one of your shared accounts does not get it for free.
- Send the password over a different channel from the link.
- The password is only meaningful within the 24-hour expiry window. After that, the ciphertext is gone and the password protects nothing.

> [!NOTE]
>
> If you forget the password, the paste cannot be recovered. Ente has no way to reset it. The password is part of the decryption key and was never sent to the server.

### When to skip it

A regular Paste link is already end-to-end encrypted. Password protection adds value when you cannot fully trust the channel you are sending the link over. If you are sending the link via Signal to one person and immediately deleting the message, password protection is usually overkill. If you are pasting the link somewhere other people might see it before the intended recipient opens it (a group chat thread, a ticket comment, or an email with multiple recipients), password protection meaningfully raises the bar.

## Share the link

After you create a paste, the link card on the page offers three ways to hand the link to someone.

### Copy

Click "Copy" to put the link on your clipboard. A "Copied to clipboard." confirmation appears underneath the button and fades out after about a second.

This is the most reliable option across devices and works well for pasting the link into chat, email, or a terminal.

### Share

Click "Share" to invoke your operating system's share sheet (the same picker you get when you share a webpage from your browser). This is convenient on phones for handing the link to a specific contact in Signal, Messages, or another app.

On devices or browsers that do not implement the Web Share API, "Share" falls back to copying the link to the clipboard, with no error.

### QR code

Click the QR icon to display a scannable QR code. The QR encodes the full link, key fragment included, so a phone scanning it goes straight to the paste.

Use QR for handing a paste to someone next to you without typing or messaging. For example, transferring a credential from a laptop to a colleague's phone.

- On desktop, the QR appears as a floating card in the bottom-right corner.
- On mobile, the QR opens in a centered dialog.
- Click the QR icon again, or close the dialog, to dismiss it.

Generating the QR happens entirely in the browser. Nothing about the link, including the decryption key, leaves your device just because you displayed the code.

### The "open once" confirmation

The link on the card is also clickable, but opening it consumes the paste. To prevent accidents, clicking the link on your own create page brings up an "Open One-Time Link?" confirmation with two buttons:

- **Copy link**: copies the link to the clipboard and dismisses the dialog. Use this whenever you click the link by reflex.
- **Open Link**: actually opens the paste in a new tab and consumes it.

This confirmation only appears for the sender on the create page. Recipients following the link from elsewhere open the paste directly.

## Open a paste

When the recipient opens the link:

1. Their browser fetches the ciphertext from Ente.
2. The browser pulls the decryption key out of the URL fragment (the part after `#`) and decrypts the text locally. While this happens they see "Opening secure paste... Decrypting in your browser."
3. The decrypted text appears in a read-only text area with a "Copy" button.
4. Ente's servers delete the paste. The message "This paste has been removed from Ente servers." appears below the text.

If the paste is password protected, the recipient sees an "Enter paste password" prompt before step 1. They enter the password and click "Open paste". Decryption only succeeds with the correct password. If they enter a wrong password, they can retry in the same tab.

## What can go wrong

- **"This paste has expired or was already opened."** The link has been consumed by someone else, or the 24-hour window has elapsed. The paste cannot be recovered. Create a new one.
- **"Incorrect paste password"** (password-protected pastes only). The password did not produce the right key. Retry in the same tab. If the page was closed or reloaded, ask the sender to create a new paste.
- **"Missing key in URL" / "Invalid key in URL"** The fragment after `#` is missing or malformed. This usually means the link was truncated when it was shared. Ask the sender to resend the full link, and prefer copying and pasting it exactly rather than retyping it.
- **"Paste is unavailable"** The link is being opened by a tool that looks like a link-preview bot or crawler, or the request was not made from `paste.ente.com`. Open the link directly in a regular browser tab.

The "Create new paste" button on the error screen takes you back to the create flow.

## Related topics

- [How encryption works](/paste/features/security)
- [FAQ](/paste/faq)
