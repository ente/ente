---
title: Getting started
description: Split a secret into 3 cards, store them safely, test recovery, and recover later
---

# Getting started

This page walks through the full lifecycle of a 2of3 set: splitting your secret, storing the three cards, testing that recovery actually works, and recovering later.

Open 2of3 at [2of3.ente.com](https://2of3.ente.com). No account, nothing to install. Everything described here happens in your browser.

## Split a secret into 3 cards

1. Open [2of3.ente.com](https://2of3.ente.com).
2. In the **Secret** field on the left, paste or type the secret you want to split. This can be a recovery key, a master password, a wallet phrase, or any short piece of text. The counter under the field shows how many bytes you have used out of the maximum.
3. Optionally edit the **Card label**. By default it shows today's date (for example, `26 May 2026`). The label is printed on each card so you can tell different sets apart later.
4. Three cards appear on the right as soon as the secret is valid. Each card shows a QR code, a card number (1, 2, or 3), and an `ID` like `A1B2C3D4`. All three cards from one secret share the same ID.

> [!IMPORTANT]
>
> Treat the three cards as a single set. Never mix cards from different sets. Recovery only works when all the cards being combined share the same ID and were generated from the same secret. If you change the secret, generate a fresh set and replace all three cards together.

### Save the cards

Each card has its own controls. From the card panel you can:

- **Print**: opens a print dialog for that single card.
- **Download**: saves the card as a PNG image (high-resolution, suitable for printing later).
- **Share**: opens the system share sheet on platforms that support it (mobile and some desktop browsers). If sharing is not available, the card is downloaded instead.
- **Copy code**: copies just the text code for that card (the string that starts with `2of3-`) so you can paste it into a note or a password manager.

For the typical case where you want all three cards plus the offline recovery file, click **Download all cards** under the secret field. This downloads four files:

- Three PNG images, one per card, named like `today-set-a1b2c3d4-card-1.png`.
- One HTML file, `2of3-recovery.html`, which is a fully offline copy of 2of3's recovery flow. Learn more in [How it works](/2of3/how-it-works#offline-recovery-file).

> [!NOTE]
>
> The maximum secret size on 2of3 is about 200 bytes of text. The exact limit is whatever still fits in a printable card. The byte counter under the **Secret** field shows the current limit. If your secret is too long to fit, see [the FAQ](/2of3/faq#2of3-secret-too-long).

## Store the cards in different places

The whole point of 2of3 is separation. Three copies in the same drawer is just one drawer.

A reasonable spread is something like:

- One card with your important documents (passport, will, deeds).
- One card somewhere physically separate: a safe at home, a desk drawer at work, or a safe-deposit box.
- One card with a trusted person: a spouse, an adult child, an executor, or a long-time friend.

The cards do not need to be all paper or all digital. Mixing is fine:

- **Printed cards** are easy to store offline and survive things that damage hard drives.
- **Downloaded PNGs** are easy to copy carefully (a backup of a backup, on a USB stick in a safe) and easy to share via end-to-end-encrypted channels.
- **Copied text codes** are easy to paste into a password manager, a sealed note, or an encrypted vault.

Many people will want both a printed copy and a saved image of the same card, in two different places, so that one fire or one disk failure does not take out an entire card.

> [!IMPORTANT]
>
> Do not store two cards in the same place. Two cards together is the whole secret. The protection comes from physical separation, not from the format.

### Label the cards so a stranger could use them

The cards already include the app's name (`2of3.ente.com`), the card number, and the ID. That is enough for someone who has heard of 2of3, but a card found years from now by someone unfamiliar may need a hint. Consider adding a sticky note or envelope that says:

- What the secret is for (so they know whether to act on it).
- Where the other two cards are likely to be (so they have somewhere to start).
- A reminder that any two of the three are enough.

If you are leaving the cards as part of an estate plan, write down which secret each set protects and which person should hold which card.

## Test recovery before you put the cards away

This is the most important step, and the easiest to skip.

Before you store the cards, scroll down to the **Recover** section on the same page and try recovering the secret with any two of the cards you just made. This catches:

- A bad print (faint or smudged QR).
- A download that got truncated.
- A card from a different set that snuck in by mistake.
- A copy-paste that dropped a character at the end of the code.

If all three possible pairs (1+2, 1+3, 2+3) recover the secret, the set is good and you can put the cards away.

## Recover the secret

You can recover at any later time using:

- 2of3 at [2of3.ente.com](https://2of3.ente.com), in the **Recover** section, or
- The offline recovery HTML file you downloaded with the cards.

Both paths work the same way and run entirely in your browser.

1. Open 2of3.ente.com, or open `2of3-recovery.html` from wherever you stored it (double-click works on most operating systems; it opens in your default browser).
2. The recovery section has two slots: **Card A** and **Card B**. They are interchangeable.
3. For each slot, do one of the following:
    - **Upload image**: pick a saved card PNG or JPG, or a phone photo of a printed card.
    - **Drag and drop**: drop an image file directly onto the slot.
    - **Paste code**: paste the text code that starts with `2of3-` into the **Code A** or **Code B** field.
4. As soon as a slot has a valid card, the slot shows which card it is. For example: `Card 2 from ID A1B2C3D4`. Make sure both slots show the same ID.
5. Click **Recover secret**. The original secret appears in a **Recovered secret** box. Click **Copy** to copy it to your clipboard.

### Recovering from a phone photo

Photos of printed cards just work, because 2of3 tries several crops when reading the image. If your phone photo has the whole card in frame and the QR is reasonably in focus, it should decode on the first try. If it does not:

- Make sure there is even light on the card and no strong glare on the QR.
- Try a tighter crop that mostly contains the QR.
- Try a higher-resolution photo if you used a low-quality scan.

Learn more about the QR decoder in [How it works](/2of3/how-it-works#qr-decoder).

### Recovering from a text code

If you only have the text codes (for example, you copy-pasted them into a password manager), paste each code into its **Code A** or **Code B** field. The code is the long string that starts with `2of3-`. Whitespace and line breaks inside the code are ignored, so codes that wrap across multiple lines in your notes app are fine.

### What the errors mean

If something goes wrong during recovery, 2of3 explains what happened. The common ones:

- **"These two cards are from different sets. Match the ID on both cards."** The two cards you uploaded were generated from different secrets (different IDs). Check the `ID A1B2C3D4` line under each slot. Both must match. If they do not, find a card that belongs to the right set.
- **"Use two different cards from the same set."** You uploaded the same card twice, or two copies of the same card (for example, the printed card and its PNG). You need two _different_ card numbers from the same set: 1 and 2, 1 and 3, or 2 and 3.
- **"That code does not look like a 2of3 share."** The pasted text is not a 2of3 code. A real code always starts with `2of3-`.
- **"That share looks incomplete."** or **"This share was cut off."** The code is missing characters at the end. This usually means a copy-paste lost the tail of the code, or the code was wrapped and the last line was missed.
- **"These shares did not reconstruct a valid secret."** The two cards parsed fine but did not combine into the original secret. This usually means at least one card is corrupted (a misread QR, an edited text code, or a bad print). Try a different pair of cards; with three cards in a set, you have three possible pairs.
- **"Could not read that image."** or **"Could not read that QR code."** The uploaded image was not a recognizable QR. Try a clearer photo, a tighter crop, or upload the original PNG instead of a screenshot.

## Replace or rotate a set

If you need to change the underlying secret (for example, you rotated a password), treat it as a brand-new 2of3 set:

1. Generate a fresh set of three cards from the new secret.
2. Distribute the new cards to the same three places.
3. Destroy the old cards (shred the printed ones, delete the PNGs, clear the text from your notes).

Do not keep one old card "just in case". An old card combined with an old card from somewhere else still recovers the old secret, which is exactly what you stopped wanting recoverable.

## Related topics

- [How it works](/2of3/how-it-works): Shamir secret sharing, the share format, the offline recovery file, and the QR decoder.
- [FAQ](/2of3/faq): answers to common questions.
