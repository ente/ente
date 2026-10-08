---
title: Duplicate detection
description: How Ente automatically detects and handles duplicate photos during backup
---

# Duplicate detection

Ente automatically detects and handles duplicate files during backup to save storage space and upload time. This happens transparently in the background without any action required from you.

## How automatic detection works

When uploading photos and videos, Ente uses a hash-based system to identify duplicate files:

**Same file to same album:**

- If you try to upload an exact duplicate to an album where it already exists, Ente will skip it entirely
- This allows you to safely resume interrupted uploads or re-upload folders without creating duplicates

**Same file to different albums:**

- If the same file already exists in a different album, Ente creates a symlink (reference) instead of storing it again
- The file appears in both albums, but storage is only counted once
- This is the same behavior as using "Add to album" within Ente

## Platform-specific behavior

The duplicate detection works slightly differently on each platform to match platform conventions:

### Mobile (iOS and Android)

![Free up space menu with Duplicates highlighted on Ente Photos mobile](https://docs-assets.ente.com/screenshots/phone-free-up-duplicates-callout.png){width=320px}

- Uses hash-based detection for exact duplicates
- If uploading to the same album: duplicate is skipped
- If uploading to a different album: creates a symlink (no data uploaded)
- Storage is only counted once regardless of how many albums contain the photo

### Web and desktop

On laptops using the web or desktop app, both the file hash AND filename are used for detection:

- A file is considered duplicate if it has the same name AND same hash
- This assumes users want to keep two copies if they have the same file but with different names
- If uploading to the same album: exact duplicate (same name + hash) is skipped
- If uploading to a different album: symlink is created (similar to "Add to album")

## Benefits

**Saves storage space:**

- Each unique file is only stored once, even if it appears in multiple albums
- Symlinks count minimal storage compared to full copies

**Saves upload time:**

- Duplicate files are detected immediately and skipped
- Only new or modified files need to be uploaded

**Enables safe re-uploads:**

- You can safely drag and drop the same folder multiple times
- Resume interrupted uploads without worrying about duplicates
- Reinstall the app and re-configure backups without creating duplicates

## Adding files to albums within Ente

Once a file is backed up to Ente, adding it to another Ente album always creates a symlink. This means:

- You can add photos to as many albums as you want
- Storage is only counted once
- Changes or deletions affect the file across all albums

## Related topics

For manual cleanup of existing duplicates, see [Storage optimization](/photos/features/albums-and-organization/storage-optimization).

## Related FAQs

- [How does the deduplication feature work on the desktop app?](/photos/faq/backup-and-sync#deduplication-desktop)
- [Does Ente deduplicate across different albums?](/photos/faq/storage-and-plans#dedup-albums)
- [How does duplicate detection work in watch folders?](/photos/faq/backup-and-sync#watch-folder-dedup)
