---
title: 2of3
description: Split one important secret into 3 recovery cards. Any 2 cards bring it back. One card alone reveals nothing.
---

# 2of3

2of3 turns one important secret into three recovery cards. Any two of the three cards can reconstruct the secret. A single card by itself reveals nothing.

It is a free, end-to-end private web app from Ente. Open it at [2of3.ente.com](https://2of3.ente.com). There is no account, nothing to install, and your secret never leaves your browser.

## Why 2of3 exists

Some secrets are the kind you cannot afford to lose, and also the kind you cannot afford to leak. A single note is a single point of failure: if it is lost, stolen, or forgotten, recovery becomes hard. If it is found by the wrong person, the damage is done.

2of3 lets you spread the risk without making recovery harder than it needs to be. Three copies in three places means losing one place is no longer a disaster. The "any two" threshold means an attacker who finds one card still has nothing to attack with.

This is the same idea behind safe-deposit boxes that need two keys, or backup tape rotations that survive any one site going down. 2of3 brings it to the kind of secret you can fit on a card.

## When to use it

Some of the ways people use 2of3:

- **Legacy account recovery.** You want a spouse, adult child, or executor to recover something important if you are not around to explain it. One card stays with your documents, one in a safe place at home, and one with a trusted person. Any two are enough when the time comes.
- **Break-glass credentials.** A root password, a production recovery key, or the master secret behind your setup. 2of3 avoids both bad outcomes at once: one lost copy that locks you out, or one stolen copy that gives everything away.
- **Family emergency pack.** A password manager emergency kit, a wallet recovery phrase, or the one recovery code your household cannot afford to lose. Splitting it across three places means recovery stays possible even when one place fails.

Concretely, people use 2of3 for things like Ente recovery keys, password manager master passwords, crypto wallet recovery phrases, full-disk encryption keys, and 2FA backup codes that they do not want to keep in only one drawer.

> [!NOTE]
>
> If the secret is your Ente account recovery key specifically, consider [Legacy Kit](/locker/features/legacy/legacy-kits) instead. Legacy Kit is the version we ship for Ente accounts. It is built on the same 2-of-3 Shamir math but adds a configurable waiting period, the ability to revoke sheets if one is lost, and a server-mediated recovery flow tied to your Ente account.
>
> 2of3 stays useful when you want the same split-and-recover guarantee for a non-Ente secret, or when you want recovery to depend on nothing but the cards themselves.

## How a card works

When you enter a secret, 2of3 generates three cards in your browser. Each card carries:

- A **QR code** with the share data
- The same data printed as a short **text code** below the QR (starting with `2of3-`)
- A short **ID** (8 characters) that is shared by all three cards from the same secret
- A **Card 1 / 2 / 3** number so a reader knows which share it is

The cards from one secret all share the same ID. The ID is how recovery tells "two cards from the same set" apart from "two cards that happen to look similar". The card number lets the recovery code know which two of the three you are using.

A single card is mathematically harmless on its own. It looks like random data, because that is exactly what it is. Knowing one card gives the same information about the original secret as knowing zero cards: none. You need any two of the three before the secret can be put back together.

## What you do with the cards

Once you have generated the three cards, you can:

- **Print** each card individually (one card per page)
- **Download** each card as a PNG image
- **Share** a card via the system share sheet (mobile and supported desktop browsers)
- **Copy** just the text code for a card to paste into a note or a vault

Or you can use **Download all cards**, which downloads all three PNGs and an [offline recovery file](/2of3/how-it-works#offline-recovery-file) (an HTML file) in one click. That offline file is its own copy of 2of3's recovery flow. It works without internet, without Ente, and without 2of3.ente.com being online.

Read [Getting started](/2of3/getting-started) for the full splitting and storing walkthrough.

## How recovery works

To recover the secret, go back to [2of3.ente.com](https://2of3.ente.com) (or open the offline recovery file) and feed in **any two** cards. For each slot:

- Upload the card's image (PNG, JPG, even a phone photo of a printed card)
- Or paste the card's text code
- Or drop the file onto the slot

The recovery section reads the cards, checks that both belong to the same set, combines them, and shows the secret on the page. Everything happens locally.

You do not need to remember which card was Card 1, 2, or 3. Any two of the three work.

Read [Getting started](/2of3/getting-started#recover-the-secret) for the full recovery walkthrough, including how the photo-of-printed-card recovery handles real phone photos.

## Privacy

2of3 has nothing to send to Ente, and it sends nothing. The splitting and the recovery both happen inside your browser:

- Your secret is split into shares locally before anything is rendered.
- Card images and QR codes are built locally.
- Recovery combines shares locally; the recovered secret never leaves the page.
- There is no account, no sign-in, no analytics that touch your secret.

Because the recovery flow is also bundled into an offline HTML file you can download, even the long-term recovery path does not depend on Ente being around. Learn more in [How it works](/2of3/how-it-works).

## Source code

2of3 is part of [Ente's open source repository](https://github.com/ente/ente). The Shamir implementation and the offline recovery file are short and inspectable. The data format on each card is documented in [How it works](/2of3/how-it-works#share-format) so that, in principle, anyone with the cards and a few hours could write their own recovery tool.

## Get started

- [Getting started](/2of3/getting-started): splitting, storing, testing, and recovering with concrete steps.
- [How it works](/2of3/how-it-works): Shamir secret sharing explained, the share format, the offline recovery file, and the QR decoder.
- [FAQ](/2of3/faq): common questions about safety, storage, recovery, and edge cases.
