---
title: Import from Apple Photos
description: Migrating your existing photos from Apple Photos to Ente Photos
---

# Import from Apple Photos

The most direct way to import an iCloud Photos library into Ente is the iPhone app. It reads your library, including photos stored in iCloud, and backs up the originals with their metadata. Nothing is deleted from iCloud.

> [!NOTE]
>
> Apple's transfer service copies iCloud Photos to Google Photos only ([Apple Support: transfer a copy of your data](https://support.apple.com/en-us/118257)). It does not import into Ente. Apple says you need iCloud Photos turned on, two-factor authentication on your Apple Account, **Advanced Data Protection turned off**, and a Google account with enough free storage. Most transfers take three to seven days, and some take up to 30. Smart Albums, Live Photos, and some RAW files may not come across the way they look in iCloud.

## Mobile

Install the [Ente app](https://ente.com/app) on your iPhone or iPad and allow access to your photo library. Ente reads the iCloud library directly and backs up the originals with their metadata.

> [!TIP]
>
> Large libraries may take some time to back up. Open [Backup mode](/photos/features/backup-and-sync/#backup-mode-ios) under `Settings > Backup > Backup settings` and tap **Start backup mode**. Keep Ente open on screen. Backup mode keeps the screen awake and dims it to save battery.
>
> You only need Backup mode for the initial backup. Ente will automatically back up new photos in the background afterwards.

If **Optimize iPhone Storage** is on, the phone keeps smaller previews locally, so each original has to be downloaded from iCloud as the backup runs. For backup, Ente still fetches the full-resolution original from iCloud. Learn more in [How does Ente handle media when Optimize iPhone Storage is enabled?](/photos/faq/backup-and-sync#optimize-iphone-storage). Stay on WiFi and keep the phone plugged in.

## Importing iCloud Shared Albums

On iOS 26 and earlier, iCloud Shared Albums do not hold your originals. Apple shrinks shared photos and strips some metadata: photos are downscaled to 2,048 pixels on the long edge, videos are capped at 720p and 15 minutes, and location data, captions, and original dates are removed.

Starting in iOS 27, Shared Albums share at full resolution ([Apple Support: iCloud Shared Albums](https://support.apple.com/en-us/108314)) and accept guest web uploads. Check which version the album was shared from. Importing the originals from the person who took the photos is still the safest route.

### If you (or the album owner) still have the originals

This is the recommended path. It preserves full quality and metadata.

1. Install the Ente app on your iPhone or iPad.
2. The Ente app reads your iCloud library and backs up the originals with full quality and metadata.
3. Organize the photos into albums inside Ente after upload.

### If shared album copies are all you have

1. **On iPhone/iPad:** Open the shared album, select the photos, tap the share button, and save them to your device library.
2. **On iCloud.com:** Open the shared album, select up to 1,000 items, and click **Download**.
3. Import the saved photos into Ente using the mobile app or the desktop app.

> [!NOTE]
>
> Copies saved from a Shared Album that was shared on iOS 26 or earlier are lower quality than the originals and are missing location data and original dates. The download date may replace the original capture date, causing photos to sort incorrectly. After importing, you can [fix dates manually](/photos/faq/metadata-and-editing#fix-incorrect-dates) in Ente if needed.

## Importing iCloud Shared Photo Library

iCloud Shared Photo Library lets one organiser share a photo library with up to five other people. Ente does not have an exact equivalent. Ente supports shared and collaborative albums on a per-album basis.

On iPhone or iPad running iOS 16.1 or later, Shared Library photos are available through the system Photos library alongside your Personal Library. If Ente has full access to your photo library, it can back up Shared Library photos as well.

### Import into Ente

1. Install the Ente app on your iPhone or iPad.
2. Sign in and grant Ente full access to your photos when prompted.
3. Ente will then read and back up photos from your device's photo library, including Shared Library items visible there.

### Optional: leave the Shared Library after migrating

If you want to stop using Apple's Shared Library after your Ente backup is complete, you can leave it at any time.

1. Open `Settings > Apps > Photos > Shared Library` on your iPhone or iPad.
2. Tap **Leave Shared Library**. If you are the organiser, you may instead see **Delete Shared Library**.
3. Choose whether to keep everything from the Shared Library or only the items you contributed.

> [!NOTE]
>
> If you have been in the Shared Library for less than seven days, Apple only lets you keep the items you contributed.

### What about metadata?

- **EXIF data** (dates, location, camera info) embedded in photo files is preserved during import.
- **Favorites, album membership, and People tags** are stored only inside Apple Photos and are not embedded in exported files.

### Mac alternative {#mac-alternative}

You can also migrate a Shared Library from a Mac:

1. Open the Photos app.
2. Open `Settings > iCloud` and select **Download Originals to this Mac**. Wait until the download finishes.
3. Switch the library view to **Shared Library** or **Both Libraries**.
4. Select the items you want.
5. Choose **File > Export > Export Unmodified Originals**.
6. Import those files into Ente from the desktop or web app.

> [!NOTE]
>
> Older devices running iOS 16.0 or earlier and iCloud for Windows cannot see Shared Library content. If migrating from one of these, use the Mac alternative above from a Mac running macOS Ventura or later, or consolidate your libraries first on a supported iPhone or iPad by following the steps above in "Optional: leave the Shared Library after migrating".

## Download originals on a Mac or from iCloud.com

Use this to copy originals from a Mac or from iCloud.com. These steps copy the library.

**On a Mac:**

1. Open the Photos app.
2. Open `Settings > iCloud` and select **Download Originals to this Mac**. Wait until the download finishes.
3. Choose **File > Export > Export Unmodified Originals** so the export keeps the files and their metadata.
4. Import the exported folder into Ente.

For a Shared Library, switch the library view before you export. Follow the [Mac alternative](#mac-alternative) above. Learn more about [importing from Apple Photos on desktop](/photos/faq/migration#importing-from-apple-photos).

**On iCloud.com:**

Select photos and download them in batches. Downloading in the browser is slow for a large library. Then upload the downloaded files with Ente's desktop or web app.

## Before you turn off iCloud Photos

- Compare photo counts between iCloud and Ente.
- Open a few old photos and check dates and locations.
- Check that Live Photos and videos play.

Only then reduce your iCloud plan or turn off iCloud Photos.

If you run into any issues during this migration, please reach out to [support@ente.com](mailto:support@ente.com) and we will be happy to help you!
