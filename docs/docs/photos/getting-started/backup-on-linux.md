---
title: Back up photos on Linux
description: Ways to back up photos on Linux, including Ente's Linux desktop app
---

# Back up photos on Linux

If you want a photo app without running a server, use a hosted service with a Linux app, such as Ente, which is end-to-end encrypted. If you'd rather own everything, self-host Immich or PhotoPrism, or push your folders to Backblaze B2 with a tool like Restic ([Backblaze docs](https://www.backblaze.com/docs/cloud-storage-back-up-linux-to-backblaze-b2)).

Which one is right comes down to how much maintenance you want to do.

## Option 1: Self-host (Immich, PhotoPrism)

Good if you already run a home server or NAS and enjoy that kind of thing. You get full control and no subscription. You also become the person responsible for updates, disk failures, and an off-site copy. A self-hosted library on one disk in your house isn't a backup yet.

## Option 2: A backup tool and cheap cloud storage

Tools like Restic, Duplicity, and Duplicacy can encrypt your photo folders and push them to object storage such as Backblaze B2 on a schedule. They're reliable, and you pay only for the storage you use. You don't get a photo app: no timeline, no phone backup, and no sharing albums with family.

## Option 3: A hosted photo app with a Linux client

This gives you phone backup, search, and sharing without running anything yourself.

Ente has a Linux desktop app:

1. **Install the desktop app.** Download it from [ente.com/download](https://ente.com/download/) and pick the Linux build. The download page offers AppImage, DEB, RPM, and Flathub.
2. **Sign in,** or create an account. The free plan includes 10 GB. Learn more in [Sign up](/photos/getting-started/signup).
3. **Set up watch folders.** Open **Watch folders** in the sidebar and point Ente at your photo folders, for example `~/Pictures`. Ente uploads new files automatically. It's a one-way sync: if you delete a file locally, Ente moves its copy to Uncategorized. Learn more in [Watch folders](/photos/features/backup-and-sync/watch-folders).
4. **Optionally keep a local copy.** The desktop export can keep an up-to-date copy of your Ente library on a local or external drive. Open **Export data** in the sidebar and turn on **Continuous export**. It picks up new files, album moves, and deletions. Learn more in [Export](/photos/features/backup-and-sync/export).

There's also an Ente CLI that runs on Linux, macOS, and Windows and can export your library to a local disk or NAS. Learn more in the [Account creation FAQ](/photos/faq/account-creation#install-cli).

Everything is end-to-end encrypted before it leaves your machine, including metadata. Learn more in the [Security and privacy FAQ](/photos/faq/security-and-privacy#can-ente-see-metadata). Ente's apps and server are open source, and you can self-host the server if you'd rather run it yourself ([GitHub](https://github.com/ente/ente)). Learn more in [Self-hosting](/self-hosting/).

## A sensible setup for most people

Use the 3-2-1 rule: three copies, on two kinds of storage, with one of them off-site. A realistic Linux version:

- Your photos in `~/Pictures` on your laptop or desktop.
- A hosted photo service or a self-hosted server that syncs them.
- A Restic or Borg backup to an external drive or B2, in case the first two fail at the same time.

## Odds and ends

### Can I back up my Android phone to my Linux PC? {#linux-android-backup}

Yes, with sync tools. A photo app that backs up from the phone and syncs to the desktop is less fiddly.

### Does Ente's Linux app do face recognition? {#linux-face-recognition}

Yes. Machine learning works in the desktop app. Open `Settings > Preferences > Machine learning`. Learn more in [Machine learning](/photos/features/search-and-discovery/machine-learning). It isn't available in the web app.
