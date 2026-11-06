---
title: Back up photos on Linux
description: Ways to back up photos on Linux, including Ente's Linux desktop app
---

# Back up photos on Linux

There are three main ways to back up photos on Linux: self-host a photo server, push your folders to cloud storage with a backup tool, or use a hosted photo app with a Linux client, such as Ente. The right choice comes down to how much maintenance you want to take on.

## Option 1: Self-host (Immich, PhotoPrism)

Good if you already run a home server or NAS and enjoy looking after it. You get full control and no subscription. You're also responsible for updates, disk failures and an off-site copy. A self-hosted library on one disk in your house isn't a backup yet.

## Option 2: A backup tool and cloud storage

Tools like Restic, Duplicity and Duplicacy can encrypt your photo folders and push them to object storage such as Backblaze B2 on a schedule ([Backblaze](https://www.backblaze.com/docs/cloud-storage-back-up-linux-to-backblaze-b2)). They're reliable, and you pay only for the storage you use. What you don't get is a photo app: no timeline, no phone backup and no shared albums with family.

## Option 3: A hosted photo app with a Linux client

This gives you phone backup, search and sharing without running anything yourself. Ente has a Linux desktop app, and everything is end-to-end encrypted before it leaves your machine, including metadata ([Security and privacy FAQ](/photos/faq/security-and-privacy#can-ente-see-metadata)).

1. **Install the desktop app.** Download the Linux build from [ente.com/download](https://ente.com/download/). It comes as an AppImage, DEB, RPM or Flathub package.
2. **Sign in** or create an account. The free plan includes 10 GB ([Sign up](/photos/getting-started/signup)).
3. **Set up watch folders.** Open **Watch folders** in the sidebar and point Ente at your photo folders, for example `~/Pictures`. Ente uploads new files automatically. The sync is one-way: if you delete a file locally, Ente moves its copy to Uncategorized rather than deleting it. Learn more in [Watch folders](/photos/features/backup-and-sync/watch-folders).
4. **Keep a local copy (optional).** Open **Export data** in the sidebar and turn on **Continuous export**. Ente then keeps an up-to-date copy of your library on a local or external drive, including new files, album moves and deletions. Learn more in [Export](/photos/features/backup-and-sync/export).

Prefer the terminal? The Ente CLI runs on Linux, macOS and Windows and can export your library to a local disk or NAS ([Account creation FAQ](/photos/faq/account-creation#install-cli)).

Ente's apps and server are open source ([GitHub](https://github.com/ente/ente)), so you can also self-host the server. Learn more in [Self-hosting](/self-hosting/).

## A sensible setup for most people

Follow the 3-2-1 rule: three copies, on two kinds of storage, with one off-site. On Linux that could look like this:

- Your photos in `~/Pictures` on your laptop or desktop.
- A hosted photo service or self-hosted server that syncs them.
- A Restic or Borg backup to an external drive or B2, in case the first two fail at the same time.

## FAQ

### Can I back up my Android phone to my Linux PC? {#linux-android-backup}

Yes, with a sync tool. It's simpler to use a photo app that backs up from your phone and syncs to your desktop.

### Does Ente's Linux app do face recognition? {#linux-face-recognition}

Yes. Machine learning runs in the desktop app, though not in the web app. Turn it on in `Settings > Preferences > Machine learning`. Learn more in [Machine learning](/photos/features/search-and-discovery/machine-learning).
