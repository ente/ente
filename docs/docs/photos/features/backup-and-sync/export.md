---
title: Export
description: Export your photos from Ente to local storage
---

# Export

Export allows you to download your entire Ente library or specific albums to local storage. This creates a local backup of your photos while keeping them safely stored in Ente's cloud.

## Why use export?

Export is useful for:

- **Local backups**: Keep a copy of your photos on your computer or NAS
- **Data portability**: Export your data in a standard format you can use anywhere
- **Redundancy**: Have multiple copies of your precious memories
- **Offline access**: Keep a complete local copy for when you're without internet

## Export options

### Desktop continuous export

The desktop app offers continuous export, which automatically exports new items as they're uploaded to Ente. The web app does not support export.

**How to set up:**

1. Open `Settings > Export data`
2. Choose a destination folder on your computer
3. Enable "Continuous export"
4. The app will automatically export new items in the background

**Important notes:**

- The desktop app must be running for continuous export to work
- Exports happen in the background without interrupting your work
- Mirrors album changes (new files, album moves, and deletions) so your export reflects the latest album state
- Incremental exports only download new or changed files
- The web app does not support export; use the desktop app or CLI

### CLI export

For advanced users and automation, use the [Ente CLI](/photos/features/utilities/cli) to export via command line. The CLI is particularly useful for:

- Automated exports with cron jobs
- Server-to-server transfers
- NAS sync setups

## What gets exported

### Album structure

Your album structure is fully preserved during export. Each album becomes a separate folder with your photos organized exactly as they are in Ente.

**Example structure:**

```
export-folder/
├── Vacation 2024/
│   ├── photo1.jpg
│   └── photo2.jpg
├── Family/
│   └── photo3.jpg
└── Best Photos/
    └── photo1.jpg  # Same file in multiple albums
```

### Metadata preservation

Metadata is exported as separate JSON files alongside your photos. The original files are not modified. The metadata folder name differs depending on whether you export using Ente Desktop or the Ente CLI.

**Ente Desktop Format:**

```
photo.jpg
metadata/photo.jpg.json
```

**Ente CLI Format:**

```
photo.jpg
.meta/photo.jpg.json
```

The JSON format matches Google Takeout format, so tools that support Google Takeout imports can read Ente's exported metadata.

For details about the metadata format, see [Metadata and Editing FAQ](/photos/faq/metadata-and-editing#export-data-preserve-metadata).

### Files in multiple albums

If a photo exists in multiple albums:

- **In Ente**: Counts as 1 file (storage counted once)
- **On export**: Appears in each album folder (downloaded multiple times)

This is why your export size may be larger than your Ente storage usage.

### Shared albums on export

All shared albums, including albums shared with you as well as albums shared by you, are exported.

## Export limitations

### Two-way sync not supported

Exports create a **one-way sync** from Ente to your local storage. Changes to exported files do not sync back to Ente.

> [!IMPORTANT]
>
> Do **not** export to the same folder that you're watching for uploads. This will cause:
>
> - Duplicate files
> - Export stalling
> - Undefined behavior

**Best practice:** Use separate folders for:

- Upload source (watch folders)
- Export destination (local backups)

### Network drives (NAS)

Exporting to network drives generally works better than importing from them:

- File system interaction is simpler for exports
- Performance is usually acceptable

**Windows UNC path issue:** If exporting to a UNC path (`\\server\share`), map it to a network drive letter first. File separators don't work correctly with UNC paths and the export won't start.

Learn more in [Troubleshooting NAS issues](/photos/faq/troubleshooting#nas).

## Incremental exports

Both desktop continuous export and CLI exports are **incremental**:

- Only new or changed files are downloaded
- Gracefully handles interruptions
- Safe to stop and restart without re-downloading everything
- Saves time and bandwidth

## Related FAQs

- [How can I backup my data locally outside Ente?](/photos/faq/advanced-features#local-backup)
- [Does export preserve album structure?](/photos/faq/advanced-features#export-album-structure)
- [Does export preserve metadata?](/photos/faq/advanced-features#export-preserves-metadata)
- [Can I do 2-way sync with exports?](/photos/faq/advanced-features#export-two-way-sync)
- [Why is my export size larger than my Ente storage?](/photos/faq/advanced-features#export-size-larger)
- [Can I export to a network drive (NAS)?](/photos/faq/advanced-features#export-to-nas)

## Related topics

- [CLI](/photos/features/utilities/cli) - Command-line tool for automated exports
- [Watch folders](/photos/features/backup-and-sync/watch-folders) - Automatic uploads (the counterpart to export)
