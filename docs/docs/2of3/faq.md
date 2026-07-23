---
title: 2of3 FAQ
description: Common questions about splitting secrets, storing cards, recovery, privacy, and edge cases
---

# 2of3 FAQ

Answers to common questions about splitting secrets, storing cards, and recovery. If your question is not here, browse [Getting started](/2of3/getting-started) or [How it works](/2of3/how-it-works), or write to [support@ente.com](mailto:support@ente.com).

## Basics

### What is 2of3, exactly? {#2of3-what-is}

2of3 turns one secret into three recovery cards. Any two cards can bring the secret back. One card by itself is not enough.

It is a web app at [2of3.ente.com](https://2of3.ente.com). There is no account, nothing to install, and your secret never leaves your browser.

### When is 2of3 useful? {#2of3-when-useful}

Use it for something important that feels risky to keep in one place: an Ente recovery key, a password manager master password, a wallet recovery phrase, a full-disk encryption key, a break-glass production credential, or another recovery code you do not want to lose.

If a secret would be a disaster to lose _and_ a disaster to leak, 2of3 is the right shape of tool. Learn more in the [intro](/2of3/).

### Why not just keep the secret in one note? {#2of3-why-not-one-note}

A single note is a single point of failure. If that one place is lost, stolen, or forgotten, recovery becomes hard. If it falls into the wrong hands, the damage is done.

2of3 lets you spread the risk without making recovery too difficult. Three copies in three places means losing one place is no longer fatal, and the "any two" threshold means an attacker who finds one card still has nothing usable.

### Why "2-of-3" specifically and not some other split? {#2of3-why-two-three}

Three places is concrete and memorable. Requiring two cards means losing one place is not a disaster. Requiring all three would make recovery too fragile (one fire ends everything). Requiring only one would not improve on a single note at all.

2of3 is built around exactly the 2-of-3 case so that the UI, the cards, the recovery flow, and the explanations can all be specific and friction-free. If you need a general k-of-n scheme for a research or engineering project, look at SLIP-0039 or a Shamir library instead.

## Storage

### Where should the three cards go? {#2of3-where-to-store}

Keep the three cards in different safe places. Home, a safe, a trusted family member, a desk drawer at work, a document locker, or a safe-deposit box are all reasonable. The important part is separation.

A common spread is:

- One with your important documents (passport, will, deeds).
- One physically separate from your home: work, a safe-deposit box, or another building.
- One with a trusted person: a spouse, an adult child, an executor, or a long-time friend.

Mix formats freely: a printed card in one place, a downloaded PNG on a USB stick in another, and the text code in a sealed note for the third is a fine combination. Learn more in [Getting started](/2of3/getting-started#store-the-cards-in-different-places).

### Should I print, download, or both? {#2of3-print-or-download}

Either is fine. Printed cards are easy to store offline and survive things that damage hard drives. Downloaded images are easier to duplicate carefully (a backup of a backup, on a USB stick in a safe). Many people will want both (a printed copy and a saved PNG of the same card stored in two different places) so a single fire or disk failure does not take out an entire card.

### Can I store two cards in the same place "just to be safe"? {#2of3-two-in-one-place}

No. Two cards together is the whole secret. The protection comes from physical separation, not from the format the cards are in. If you keep two cards in the same drawer, that drawer now contains your secret in full.

If you want extra safety against a single card being damaged, keep duplicates of the _same_ card in places that are already paired with that card's location. For example: a printed copy of Card 1 in your safe and a PNG of Card 1 on a USB stick in the same safe is fine, because the safe was already going to hold Card 1's worth of information.

### Should I label the cards with what they unlock? {#2of3-label-cards}

A short hint is helpful, especially for cards intended for an executor or a future you who has forgotten the context. Consider attaching a sticky note or envelope that says what the secret is for (so the finder knows whether to act on it), where the other two cards are likely to be (so they have somewhere to start), and a reminder that any two of the three are enough.

Avoid writing the secret itself on the same card, of course. That defeats the point.

## Recovery

### Do I need all three cards to recover? {#2of3-need-all-three}

No. Any two are enough. The third card is there so one missing card does not lock you out.

### How do I recover later? {#2of3-how-to-recover}

Open 2of3 at [2of3.ente.com](https://2of3.ente.com), or use the offline recovery HTML file you downloaded with the cards. In the **Recover** section, upload any two card images (PNGs, JPGs, or phone photos of printed cards), or paste their text codes. Click **Recover secret** and the original secret appears on the page.

The full walkthrough lives in [Getting started](/2of3/getting-started#recover-the-secret).

### Can I recover from a photo of a printed card? {#2of3-recover-from-photo}

Yes. 2of3's QR reader tries several crops automatically, so a phone photo with the whole card in frame usually decodes on the first try. If a particular photo does not decode, take another with even lighting, no glare on the QR, and the whole card clearly in frame, or try a tighter crop on the QR.

The same forgiveness applies when recovering from the [offline recovery file](/2of3/how-it-works#offline-recovery-file).

### Should I test recovery before storing the cards? {#2of3-test-first}

Yes. Before you put the cards away, try recovering the secret once using two of the cards you just made. It is the quickest way to catch a bad print, a saving mistake, or a card from the wrong set. Ideally, try all three possible pairs (1+2, 1+3, 2+3) so you know every card is good.

### One of my cards is damaged. Am I locked out? {#2of3-card-damaged}

Not by itself. The whole point of 2of3 is that any two of the three cards are enough. If one card is damaged, the other two still recover the secret.

If two cards are damaged or lost at the same time, you are down to one share, which by itself cannot reconstruct the secret. At that point, treat the secret as effectively gone and rotate it (generate a fresh secret and a fresh set of cards) if you can.

### The recovery flow says "These two cards are from different sets". {#2of3-different-sets}

The two cards you uploaded were generated from different secrets, so their **IDs do not match**. Each set of three cards shares one ID (shown as something like `ID A1B2C3D4`). Both cards being combined must have the same ID.

If you have a stash of old and new cards, look at the ID on each card and group them. Only combine cards that share an ID.

### The recovery flow says "Use two different cards from the same set". {#2of3-duplicate-cards}

The two cards you uploaded share the same card number. You probably uploaded the same card twice (for example, the printed card and its saved PNG). Recovery needs two _different_ card numbers from the same set: 1 and 2, 1 and 3, or 2 and 3.

### The recovery flow says "These shares did not reconstruct a valid secret". {#2of3-bad-reconstruct}

Both cards parsed fine but combined into bytes that did not match the checksum stored on each card. This usually means at least one card has been corrupted: a misread QR, a transcribed text code with a typo, or a faint print where the decoder picked up wrong bits.

Try a different pair of cards. With three cards in a set there are three possible pairs (1+2, 1+3, 2+3); if exactly one card is bad, the pair that avoids the bad card will still recover the secret.

### Can a chat app eating my link or text break recovery? {#2of3-chat-mangling}

If you share a card by sending the text code through a chat app that wraps lines, adds invisible characters, or auto-formats text, the recipient may end up with a mangled code. 2of3 ignores ordinary whitespace and line breaks, so a wrapped code is fine, but if a chat app turned characters into "smart quotes" or stripped the `2of3-` prefix, the code will not parse.

Safer options are to share the **PNG image** of the card (which travels well through most channels), the original PNG file as an attachment, or the code through an end-to-end-encrypted channel that does not modify the message body.

## Privacy and trust

### Does this send my secret to Ente? {#2of3-sends-to-ente}

No. Your secret is split and recovered in your browser. There is no account, no sign-in, and nothing about your secret leaves the page. The downloaded offline recovery file also works fully offline.

### Can one card alone reveal my secret? {#2of3-one-card-leak}

No. A single card is mathematically harmless on its own. It looks like random data because that is what it is: the secret XOR-ed with a uniformly random byte (per byte). Knowing one card gives the same information about the original secret as knowing zero cards: none.

You need any two of the three before the secret can be reconstructed.

### What if 2of3.ente.com is gone in 10 years? {#2of3-site-gone}

Recovery still works. When you click **Download all cards**, 2of3 also downloads a file called `2of3-recovery.html`, a fully offline copy of the recovery flow. Open that file in any browser, drop in any two cards, and recover.

2of3 is also [open source](https://github.com/ente/ente), and the [share format](/2of3/how-it-works#share-format) is documented, so even if both Ente and the offline file were gone, someone with the cards could write their own recovery tool from the format description.

### What information does Ente collect when I use 2of3? {#2of3-collected-info}

Nothing about your secret or your cards. 2of3 has no account, no sign-in, and no server-side processing of any card data. The site itself is hosted like any other page on `ente.com`, which means standard server-side request logs (an IP address connected to fetch the page) exist for the page load, but the secret you type and the cards you generate are processed entirely on your device.

### Is 2of3 open source? {#2of3-open-source}

Yes. 2of3 is part of [Ente's open source repository](https://github.com/ente/ente). The Shamir implementation, the share format, the QR encoder, and the offline recovery file generator are all there to read.

## How it works

### Walk me through the math. {#2of3-the-math}

2of3 uses Shamir secret sharing with a (k=2, n=3) threshold. For each byte of your secret it picks a uniformly random byte _r_ and stores:

- Share 1: secret byte XOR _r_
- Share 2: secret byte XOR (r × 2 in GF(256))
- Share 3: secret byte XOR (r × 3 in GF(256))

GF(256) multiplication uses the AES polynomial (`0x11b`). Any two shares plus their share numbers (1, 2, or 3) recover the secret byte by byte; one share alone is a uniformly random byte from the attacker's point of view.

The full walkthrough lives in [How it works](/2of3/how-it-works#shamir-secret-sharing-briefly).

### What is the `ID A1B2C3D4` thing on the card? {#2of3-card-id}

The ID is a short fingerprint that identifies the set. All three cards from one secret share the same ID; cards from different secrets have different IDs. It exists so that recovery can tell "two cards from the same set" apart from "two cards that happen to look similar", and so that you can group cards by eye when you have a stash of old and new ones.

The displayed ID is the first 8 characters of the base64url-encoded 6-byte random ID embedded in the card. Learn more in [How it works](/2of3/how-it-works#share-format).

### What is the maximum secret size? {#2of3-secret-too-long}

The format supports up to 2048 bytes, but the practical limit on the website is whatever still fits as a readable QR plus four lines of printed text on a card, currently around 200 bytes of text. The byte counter under the **Secret** field shows the current limit live.

For most things people use 2of3 for (recovery keys, master passwords, wallet phrases, 2FA backup codes), the limit is more than enough. If your secret is longer, consider splitting it logically into pieces that each fit, or use 2of3 to protect a key that decrypts the long content stored separately.

### Can I edit one card and re-split? {#2of3-edit-one-card}

No. 2of3 generates a complete set of three cards from one secret in one step. There is no "edit Card 2 in place" because the math links all three cards through one random per-byte coefficient.

If the underlying secret needs to change, generate a fresh set of three cards from the new secret and replace all three old cards. Do not mix cards from different sets.

## Comparison and scope

### How is this different from Legacy Kit? {#2of3-vs-legacy-kit}

[Legacy Kit](/locker/features/legacy/legacy-kits) and 2of3 both use the same Shamir 2-of-3 math. The difference is what sits around the math.

**Legacy Kit** is the version we ship for Ente accounts. It is server-mediated, so kits can be revoked if a sheet is lost or stolen; recovery has a configurable waiting period during which you can block it; and the helper does not need an Ente account. If you want someone to be able to recover your Ente account without you around, Legacy Kit is the right tool.

**2of3** is the standalone version. It works on any piece of text (a Bitcoin seed phrase, a full-disk encryption key, a non-Ente recovery code) without needing an Ente account or a server. The trade-off is that 2of3 has no revocation, no waiting period, and no notion of "the rightful owner": anyone with any two cards reconstructs the secret immediately.

2of3 stays useful when you want the same split-and-recover guarantee for a non-Ente secret, or when you want recovery to depend on nothing but the cards themselves.

### How is this different from a password manager? {#2of3-vs-password-manager}

A password manager is for the secrets you use every day. 2of3 is for the one or two secrets a password manager itself depends on (the master password, the recovery key, the seed phrase) that you cannot store inside the password manager for obvious reasons.

The two are complements, not substitutes.

### Is 2of3 a place to store passwords? {#2of3-as-store}

No. 2of3 is a one-shot split for a single secret. There is no "vault", no listing of stored secrets, no sync, and no concept of multiple entries. If you want a place to store many secrets, use [Ente Locker](/locker/) or a password manager. Use 2of3 for the small number of underlying secrets that those tools themselves depend on.

## Related topics

- [Getting started](/2of3/getting-started): splitting, storing, testing, and recovery walkthroughs.
- [How it works](/2of3/how-it-works): Shamir secret sharing, the share format, the offline recovery file, and the QR decoder.
- [2of3 overview](/2of3/): what 2of3 is and when to use it.
