---
title: Set up for daily use
description: Guide to configuring Ente Photos for automatic daily backup
---

# Set up for daily use

Now that your account is created and you've logged in to your devices, let's set up Ente Photos to automatically back up your new photos. This is a one-time setup - once configured, Ente will work seamlessly in the background.

## Select albums/folders to back up

The first time you open Ente Photos on a mobile device, you'll be prompted to select which albums you want to back up.

**On mobile (iOS/Android):**

1. When you first open the app, a list of albums from your device's photo library appears
2. Select the albums to automatically back up (most people choose "Camera Roll" or "All Photos")
3. Tap to confirm your selection
4. Your selected albums will now back up automatically

You can change backed up albums later in **Settings > Backup > Backed up folders**.

**On desktop:** Desktop works differently - instead of albums, you set up [watch folders](/photos/features/backup-and-sync/watch-folders) that automatically sync whenever files are added or deleted.

## Understanding automatic backup

Once you've selected your albums, Ente will:

- Automatically back up new photos and videos you take
- Work in the background without you needing to open the app
- Upload photos over WiFi by default to save your mobile data
- Preserve original quality with no compression

**Backup settings you can configure:**

**On mobile:**

- **WiFi vs mobile data**: Open `Settings > Backup` and toggle "Backup over mobile data" if you want to back up without WiFi
- **Background backup**: On iOS, videos won't backup in background - keep the app open for large video uploads
- **Battery optimization**: On Android, disable battery optimization for Ente to ensure reliable background backup

The initial backup of your existing photos may take some time depending on how many photos you have. Subsequent backups of new photos happen quickly in the background.

## Enable machine learning

Machine learning powers search in Ente Photos, allowing you to search for photos by faces and natural language descriptions like "beach sunset" or "birthday cake".

**Why enable it:**

- **Face recognition**: Find all photos of specific people
- **Magic search**: Search using natural language descriptions for objects, scenes, colors, and activities
- **Completely private**: All processing happens on your device - your photos never leave your device for ML analysis

**How to enable:**

**On mobile:** Open `Settings > Machine learning` and enable "Machine learning" and/or "Local indexing".

**On desktop:** Open `Settings > Preferences > Machine learning` and enable "Machine learning" and/or "Local indexing".

> [!NOTE]
>
> Machine learning is not available on the web app. You must use mobile or desktop apps.

**What happens next:**

After enabling, the app will download and process your photos locally on your device to build search indexes. This can take some time for large libraries:

- WiFi is recommended for faster downloads
- Desktop computers process faster than mobile devices
- Indexes are encrypted and synced to your other devices

> [!TIP]
>
> If you have a large library, enable machine learning on desktop first for faster indexing. Once complete, the indexes sync to your mobile devices.

Learn more in the [Machine learning guide](/photos/features/search-and-discovery/machine-learning).

## Next steps

You're all set! Ente is now backing up your photos automatically. Here are some features you might want to explore:

- **[Create albums](/photos/features/albums-and-organization/albums)** - Organize your favorite photos
- **[Share with family](/photos/features/sharing-and-collaboration/share)** - Collaborate on shared albums
- **[Set up family plan](/photos/features/account/family-plans)** - Share your storage with family members
- **[Free up device storage](/photos/features/albums-and-organization/storage-optimization)** - Remove local copies after backup

## Related FAQs

**Backup:**

- [How does automatic backup work in Ente?](/photos/faq/backup-and-sync#automatic-backup)
- [How does background sync work?](/photos/faq/backup-and-sync#how-background-sync-works)
- [Can I backup over mobile data or only WiFi?](/photos/faq/backup-and-sync#mobile-data)

**Troubleshooting:**

- [Why are some photos not uploading?](/photos/faq/troubleshooting#upload-failures)
- [Why is my initial backup taking so long?](/photos/faq/backup-and-sync#initial-backup-slow)
- [Why isn't background sync working on my phone?](/photos/faq/troubleshooting#background-sync-issues)

**Advanced:**

- [How can I keep NAS and Ente photos synced?](/photos/faq/advanced-features#nas-sync)
- [How do watch folders work on desktop?](/photos/faq/backup-and-sync#how-watch-folders-work)
