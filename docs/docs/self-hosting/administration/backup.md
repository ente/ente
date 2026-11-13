---
title: Backups - Self-hosting
description: General introduction to backing up your self hosted Ente instance
---

# Backing up your Ente instance

A functional Ente backend needs three things:

1. Museum (the API server)
2. Postgres (the database)
3. Object storage (any S3-compatible object storage)

Thus, when thinking about backups:

1. For Museum, you should backup your `museum.yaml`, `credentials.yaml` or any other custom configuration that you created.
2. The entire data volume needs to be backed up for the database and object storage.

A common oversight is taking a lot of care for backing up the object storage, even going as far as enabling replication and backing up the the multiple object storage volumes, but not applying the same care to the database backup.

While the actual encrypted photos are indeed stored in the object storage, **this encrypted data will not be usable without the database** since the database contains information like a file specific encryption key.

Viewed differently, to decrypt your data you need three pieces of information:

1. The encrypted file data itself (which comes from the object storage backup).
2. The encrypted file and collection specific encryption keys (which come from the database backup).
3. The master key (which comes from your password).

If you're starting out with self hosting, we recommend keeping plaintext backup of your photos.

[You can use the CLI or the desktop app to automate this](/photos/faq/export).

Once you get more comfortable with the various parts, you can try backing up your instance.

If you rely on your instance backup, ensure that you do full restoration to verify that you are able to access your data.

As the industry saying goes, a backup without a restore is no backup at all.
