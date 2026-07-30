---
title: Import from Apple Photos
description: Migrating your existing photos from Apple Photos to Ente Photos
---

# Import from Apple Photos

## Mobile

If you are using Apple Photos on your phone, then the most seamless way is to install the Ente app on your mobile device. The Ente app will directly read from your iCloud library and import.

> [!TIP]
>
> For large libraries, this process may take a bit of time, so you can speed it up by keeping the app running in the foreground while the initial import is in progress. You can do this by going to `Settings > Backup > Backup settings` and turning on "Disable auto lock" (Note: this is only needed during the initial import, subsequently the app will automatically backup photos in the background as you take them).

## Importing iCloud shared albums

iCloud shared albums use reduced-quality copies of your photos and videos - they are **not** the same as your original files. Apple downscales photos to 2,048 pixels on the long edge and caps videos at 720p / 15 minutes. Location data, captions, and original dates are also stripped.

Because of these limitations, the best approach depends on whether you have access to the originals.

### If you (or the album owner) still have the originals

This is the recommended path, as it preserves full quality and metadata.

1. Install the Ente app on your iPhone or iPad.
2. The Ente app will directly read from your iCloud library and back up the originals with full quality and metadata.
3. Organize the photos into albums inside Ente after upload.

### If shared album copies are all you have

1. **On iPhone/iPad:** Open the shared album, select the photos, tap the share button, and save them to your device library.
2. **On iCloud.com:** Open the shared album, select up to 1,000 items, and click Download.
3. Import the saved photos into Ente using the mobile app or the desktop app.

> [!NOTE]
>
> Photos downloaded from iCloud shared albums will be lower quality than the originals and will be missing location data and original dates. The download date may replace the original capture date, causing photos to sort incorrectly. After importing, you can [fix dates manually](/photos/faq/metadata-and-editing#fix-incorrect-dates) in Ente if needed.

## Importing iCloud Shared Photo Library

iCloud Shared Photo Library lets one organiser share a photo library with up to five other people. Ente does not have an exact equivalent - instead, Ente supports shared and collaborative albums on a per-album basis.

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

### Mac alternative

You can also migrate from a Mac:

1. Open the Photos app.
2. Switch the library view to **Shared Library** or **Both Libraries**.
3. Select the items you want.
4. Choose **File > Export > Export Unmodified Original**.
5. Import those files into Ente from the desktop or web app.

> [!NOTE]
>
> Older devices running iOS 16.0 or earlier and iCloud for Windows cannot see Shared Library content. If migrating from one of these, use the Mac alternative above from a Mac running macOS Ventura or later, or consolidate your libraries first on a supported iPhone or iPad by following the steps above in "Optional: leave the Shared Library after migrating".

For information regarding desktop migration, please go through this [FAQ](/photos/faq/migration#importing-from-apple-photos).

If you run into any issues during this migration, please reach out to [support@ente.com](mailto:support@ente.com) and we will be happy to help you!
