---
title: How it works
description: Shamir secret sharing over GF(256), the on-card share format, the offline recovery file, and the QR decoder
---

# How it works

This page explains what is actually happening when 2of3 splits a secret into three cards and what is on each card. None of this is required reading for using 2of3. If you just want to split a secret and recover it later, [Getting started](/2of3/getting-started) is enough. This page is for the people who want to understand the math, audit the format, or build their own recovery tool from the cards.

## Shamir secret sharing, briefly

2of3 is built on **Shamir secret sharing**, a classic cryptographic scheme from 1979. The version 2of3 uses is the simplest interesting case: split a secret into three shares such that any two shares reconstruct the original, and any one share alone leaks nothing.

> [!TIP]
>
> If you want a visual walkthrough first, see the blog post [How Shamir's Secret Sharing Works](https://ente.com/blog/how-shamirs-secret-sharing-works). The rest of this section covers the same idea in text, with the specifics of what 2of3 does.

The intuition is a straight line through two points. Pick any line through the y-axis. The y-intercept is your "secret". The slope is a random number you throw away after using it. Now pick three different x values (say x = 1, 2, 3) and compute the corresponding y values on that line. Each (x, y) pair is one "share".

- Give someone any **one** share (one point on the line), and they can draw infinitely many lines through it. They learn nothing about the y-intercept.
- Give someone **any two** shares (two points on the line), and there is exactly one line through both. They can compute the y-intercept, which is the secret.

Doing this over ordinary numbers would leak information (large secrets give shares with predictable sizes, for example), so Shamir's scheme does the arithmetic over a finite field. 2of3 uses **GF(256)** (the finite field with 256 elements), which has the convenient property that every byte is a valid element. That lets 2of3 split a secret byte by byte, with each share being exactly the same size as the secret.

For the (k=2, n=3) scheme that 2of3 uses, the per-byte math is small enough to write out:

- For each secret byte _s_, 2of3 picks a uniformly random byte _r_.
- Share 1 stores _s_ XOR _r_.
- Share 2 stores _s_ XOR (r × 2 in GF(256)).
- Share 3 stores _s_ XOR (r × 3 in GF(256)).

GF(256) multiplication uses the standard AES polynomial (`0x11b`). Two of those three shares plus their share numbers (the "x values" 1, 2, 3) are enough to recover _s_ for every byte, which gives back the whole secret. One share, by itself, is _s_ XOR (some random byte), which is indistinguishable from random.

> [!NOTE]
>
> 2of3 specifically implements the 2-of-3 case for clarity and simplicity. The same scheme also powers Ente's [Legacy Kit](/locker/features/legacy/legacy-kits), the version we ship for Ente accounts: it adds a server-mediated, revocable recovery flow tied to your Ente account on top of the same 2-of-3 math.
>
> If you want general-purpose k-of-n Shamir sharing for a research project, look at SLIP-0039 or similar standards. 2of3's job is to make 2-of-3 friction-free for normal people, not to be a general crypto library.

## What is on a card

Each card carries one share, encoded as a short text code (and rendered as a QR code on the same card for easy phone capture). The text code looks like this:

```
2of3-AQEA...
```

The `2of3-` prefix is there so a reader can recognize the code at a glance and so 2of3 itself can reject pasted text that is not a share with a clear error message ("That code does not look like a 2of3 share.").

Everything after the prefix is a base64url-encoded byte payload. The payload has a 14-byte header followed by the share bytes.

### Share format

Reading from the start, the payload is:

| Bytes | Field      | What it means                                                                                                            |
| ----- | ---------- | ------------------------------------------------------------------------------------------------------------------------ |
| 0     | Version    | Always `1` in the current format. Future versions can use a different number to introduce a breaking change.             |
| 1     | Card index | `1`, `2`, or `3`. This is the "x value" used during recovery to combine shares.                                          |
| 2-3   | Length     | A 16-bit big-endian length of the secret in bytes. Both shares in a recovery must agree on this.                         |
| 4-9   | Random ID  | 6 bytes of `crypto.getRandomValues` output, generated fresh for each set. All three cards from one secret share this ID. |
| 10-13 | Checksum   | A 32-bit checksum of the original secret bytes, computed before splitting.                                               |
| 14+   | Share data | The share bytes themselves. The same length as the original secret.                                                      |

The ID and checksum are what let recovery be safe and helpful:

- The **random ID** is used to detect mismatched cards. If you try to combine a card from one set with a card from a different set, both cards parse fine but their IDs disagree, and 2of3 stops with "These two cards are from different sets. Match the ID on both cards." The card's UI shows the first 8 characters of the base64url-encoded ID as the human-readable fingerprint (for example, `ID A1B2C3D4`) so you can match cards by eye too.
- The **checksum** is used to detect corrupted cards. After combining, 2of3 recomputes the checksum of the recovered bytes and compares it against the checksum stored on each card. If they disagree, you get "These shares did not reconstruct a valid secret." instead of silently returning garbage. The checksum is a simple FNV-1a 32-bit hash, not a cryptographic MAC, because the ID and the share data are not secret and there is no one for an attacker to lie to. The checksum is there to catch accidents like a misread QR or a transcription error.

The maximum secret size 2of3 will accept is 2048 bytes in principle, but the practical limit is whatever still fits as a readable QR plus four lines of printed text on a card, currently about 200 bytes of text. The byte counter under the **Secret** field in the UI shows the live limit.

## Offline recovery file

When you click **Download all cards**, 2of3 includes one extra file alongside the three card PNGs: `2of3-recovery.html`. This is an offline copy of the recovery flow.

What is in it:

- A standalone HTML page with the recovery UI from 2of3.ente.com.
- The full Shamir combine logic, written out as inline JavaScript.
- A bundled QR decoder, so you can upload phone photos of printed cards and have them decoded locally.
- No network requests. No dependencies on Ente, on 2of3.ente.com, or on any CDN.

You can open this file by double-clicking it. It works in any modern browser. Recovery using this file is identical to recovery on 2of3.ente.com: drop two cards (image or text), click **Recover secret**, copy the result.

This file is the answer to the question "what happens if 2of3.ente.com is gone in 10 years?". The answer is: nothing. You open the HTML file you stored alongside your cards, and recover. Even if Ente as a company is gone, the file does not need anything from us. It is a few hundred lines of inspectable JavaScript that does exactly what 2of3.ente.com does.

> [!IMPORTANT]
>
> Treat the offline recovery file like a backup. Store at least one copy somewhere durable: on a USB stick, in a backup, or printed alongside the cards if you are storing things in a safe. The cards are the secret; the recovery file is the tool that opens them.

The file is also a verification target: because the file is self-contained plain JavaScript, you can read it, run it through static analysis, or compare it against the [open source repository](https://github.com/ente/ente) to convince yourself that it does what it claims. There is no remote service to trust.

## QR decoder

2of3's recovery accepts more than just cleanly cropped QR images. Phone photos of printed cards usually have the QR taking up only a portion of the frame, surrounded by the rest of the card. To handle this without asking the user to crop, the QR decoder tries several attempts on each uploaded image:

1. Decode the whole image at its full size.
2. Decode the whole image with auto-square cropping.
3. Decode three progressively tighter card-shaped crops, each cropped to roughly where the QR sits on a 2of3 card.

The first attempt that returns a valid code wins. In practice this means a casual phone photo with the whole card in frame decodes on the first or second card-shaped crop. If you have already cropped tightly to the QR, the full-image attempts succeed. The same logic ships inside the [offline recovery file](#offline-recovery-file), so the same forgiveness applies there.

If none of the attempts succeed, the recovery flow shows "Could not read that QR code." and you can try a clearer photo or paste the text code instead.

## Related topics

- [Getting started](/2of3/getting-started): splitting, storing, and recovering, with the actual UI steps.
- [FAQ](/2of3/faq): answers to common questions about safety, storage, and edge cases.
- [Source code on GitHub](https://github.com/ente/ente): the full 2of3 source, including the Shamir implementation and the offline recovery file generator.
