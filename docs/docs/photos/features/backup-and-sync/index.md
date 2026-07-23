---
title: Backup
description: How automatic backup works in Ente Photos
---

# Backup

Ente provides automatic, continuous backup of your photos and videos with end-to-end encryption. Once configured, your precious memories are safely synced to Ente's cloud without any manual effort.

## How backup works

### Mobile backup (iOS and Android)

Ente will automatically backup any albums in your native photos app that you select for backup. The app runs in the background, and any new photos added to these albums (or any photos in these albums that were modified) will be automatically synced to Ente.

**Key features:**

- **Background sync**: New photos are uploaded automatically without needing to open the app
- **Original quality**: Photos and videos are backed up in their original quality with no compression
- **Smart resumption**: If backup is interrupted, it automatically resumes from where it left off
- **Battery and data aware**: By default, uploads happen over WiFi to save mobile data and battery

### Desktop backup (Mac, Windows, Linux)

On desktop, you can use [watch folders](/photos/features/backup-and-sync/watch-folders) to automatically backup photos from specific directories on your computer. This creates a one-way sync from your computer to Ente.

## Selecting albums to backup

You can choose which albums should be backed up when you first sign up for Ente. If you change your mind later, or if you create a new album in your native photos app that you also want to backup, you can modify your choices:

**On mobile:**

Open `Settings > Backup > Backed up folders` and select or deselect albums as needed.

**On desktop:** Use the [watch folders](/photos/features/backup-and-sync/watch-folders) feature to select directories to sync.

## Background sync {#background-sync}

Ente Photos supports seamless background sync so that you don't need to open the app to backup your photos. It will sync in the background and automatically backup the albums that you have selected for syncing.

> [!NOTE]
>
> Background sync isn't currently consistent on iOS and on certain Android devices. We're actively working on a fix.

Day to day sync will work automatically. However, there are some platform specific considerations that apply:

### iOS

On iOS, if you have a very large number of photos and videos, then you might need to keep Ente running in the foreground for the first backup to happen (since we get only a limited amount of background execution time). To help with this, under `Settings > Backup` there is an option to disable the automatic device screen lock. But once your initial backup has completed, subsequent backups will work fine in the background and don't need disabling the screen lock.

On iOS, Ente will not backup videos in the background (since videos are usually much larger and need more time to upload than what we get). However, they will get backed up the next time the Ente app is opened.

Note that the Ente app will not be able to backup in the background if you force kill the app.

> If you're curious, the way this works is, our servers "tickle" your device every once in a while by sending a silent push notification, which wakes up our app and gives it 30 seconds to execute a background sync. However, if you have killed the app from recents, iOS will not deliver the push to the app, breaking the background sync.

### Android

On some Android versions, newly downloaded apps activate a mode called "Optimize battery usage" which prevents them from running in the background. So you will need to disable this "Optimize battery usage" mode in the system settings for Ente if you wish for Ente to automatically back up your photos in the background.

On Android versions 15 and later, if an app is in private space and the private space is locked, Android doesn't allow the app to run any background processes. As a result, background sync will not work.

### Desktop

In addition to our mobile apps, the background sync also works on our desktop app through the [watch folders](/photos/features/backup-and-sync/watch-folders) feature.

### Troubleshooting background sync

- On iOS, make sure that you're not killing the Ente app.
- On Android, make sure that "Optimize battery usage" is not turned on in system settings for the Ente app.

## Understanding backup behavior

### What gets backed up

- All photos and videos in selected albums
- Original quality files (no compression)
- Photo metadata (EXIF, location, date/time)
- Live Photos (both photo and video components)

### What happens when files are deleted

If a file is deleted from your native photos app, it will still remain in Ente. This is by design - on both iOS and Android, apps are not allowed to automatically delete users' photos without manual confirmation for security reasons.

If you want to delete a photo from Ente, you need to do it manually within the Ente app.

### Duplicate handling

Ente automatically detects duplicates during upload. If you try to upload the same photo multiple times, Ente will recognize it and skip the duplicate, saving your storage space.

Learn more about how [Duplicate detection](/photos/features/backup-and-sync/duplicate-detection) works.

## Backup only new photos {#backup-only-new-photos}

By default, Ente backs up your entire photo library from selected folders. If you only want to back up photos going forward - without uploading your existing library - you can enable **Backup only new photos**.

This option is available in two places:

- **During signup/login**: On the permissions screen, you can choose to back up only new photos instead of your full library.
- **In settings**: Open `Settings > Backup > Backup settings` and toggle on **Backup only new photos**.

### What "new photos" means

When you select this option during onboarding, Ente backs up photos from the **last 7 days** onward. This ensures you have some recent photos available right away rather than starting with an empty library.

When you enable the toggle in settings after onboarding, Ente uses the **current moment** as the cutoff - only photos created from that point forward will be backed up.

In both cases, photos older than the cutoff date on your device will not be uploaded.

### Folder selection prompt

When you first enable this setting, Ente may prompt you to select which folders to back up:

- If you haven't selected any folders yet, tap **Select folders** to choose which folders to include.
- Tap **Continue** to proceed with your existing folder selection.

### Disabling backup only new photos

To resume backing up all photos (including your existing library), toggle **Backup only new photos** off. Ente will then include all photos from selected folders in the next sync.

### Use cases

- **New devices**: Back up only photos taken on a new device without uploading photos already backed up elsewhere.
- **Privacy**: Exclude older photos from your library while still keeping new ones backed up automatically.
- **Storage management**: Avoid uploading a large existing library while still protecting new memories.

## Backup frequency

- **Mobile**: Background sync happens automatically. The exact timing depends on your device's operating system.
- **Desktop**: Watch folders continuously monitor for new files and deletions.

## Related FAQs

- [Can I backup only new photos without uploading my existing library?](/photos/faq/backup-and-sync#backup-only-new-photos)
- [How does automatic backup work?](/photos/faq/backup-and-sync#automatic-backup)
- [How do I select which albums to back up?](/photos/faq/backup-and-sync#select-albums)
- [Why isn't background sync working?](/photos/faq/backup-and-sync#background-sync-not-working)
- [Do deleted photos on my device also delete from Ente?](/photos/faq/backup-and-sync#deletion-sync)
- [Understanding backup vs. sync](/photos/faq/backup-and-sync#backup-vs-sync)
- [Can I delete photos from my device after backing up?](/photos/faq/backup-and-sync#free-up-space-after-backup)
- [Will deleted photos be re-uploaded?](/photos/faq/backup-and-sync#delete-reupload)
- [What file formats can I backup?](/photos/faq/backup-and-sync#backup-file-formats)
- [Does Ente compress my photos?](/photos/faq/backup-and-sync#does-ente-compress)
- [Why are some photos not uploading?](/photos/faq/troubleshooting#upload-issues)
- [Troubleshooting backup and upload issues](/photos/faq/troubleshooting#photos-not-uploading)

## Related topics

- [Watch folders](/photos/features/backup-and-sync/watch-folders) - Automatic desktop backup
- [Duplicate detection](/photos/features/backup-and-sync/duplicate-detection) - How automatic duplicate detection works
- [Storage optimization](/photos/features/albums-and-organization/storage-optimization) - Tools to optimize your storage usage
