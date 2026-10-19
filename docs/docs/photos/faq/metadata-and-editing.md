---
title: Metadata and Editing FAQ
description: Frequently asked questions about photo metadata, EXIF data, and editing in Ente Photos
---

# Metadata and Editing

## Viewing Metadata

### Why is my iPhone Portrait photo smaller in Ente than in Apple Photos? {#portrait-photo-size}

Apple Photos may include extra Portrait depth and adjustment data when showing an asset's size. Ente backs up the full-resolution image provided by iOS without compressing it, but that image file can be smaller than the complete Apple Photos asset. To compare them, export the photo from Apple Photos using **Current** and check its file size and resolution against the copy in Ente.

Ente preserves the current look of the photo, but not Apple's separate editable Portrait data. If you restore the image from Ente, controls such as changing the depth or removing the Portrait effect may no longer be available. Keep a copy in Apple Photos or iCloud if you need those controls.

### What metadata does Ente preserve during import? {#metadata-preserved}

Ente reads and preserves:

- **EXIF data**: Camera settings, date taken, GPS coordinates
- **XMP and IPTC**: Additional metadata standards
- **Google Takeout JSON**: If importing from Google Photos
- **Filename-based dates**: For files without EXIF (like screenshots)

All this metadata is:

- Encrypted before upload
- Preserved when you export

### How does Ente handle Exif data and descriptions? {#exif-handling}

Ente will try to read as much information from Exif metadata when the image is uploaded, but after that, only the fields which have been parsed into Ente can be searched.

The app still shows all the fields in the raw Exif data in the file info panel when someone taps on the "View all Exif" option, but otherwise the app is unaware of these fields.

In particular, for the description associated with a photo, the exact logic to determine the description from the Exif when uploading the image can be seen [in this part of the code](https://github.com/ente/ente/blob/0dcb185744da469848b41b668fe4b647226b6fe2/web/packages/gallery/services/exif.ts#L609-L620).

### Where does Ente import photo dates from? {#photo-date-sources}

Ente will import the date for your photos from three places (in order of priority):

1. **EXIF data**: Normally, Ente tries to read the date from the Exif and other metadata (e.g. XMP, IPTC) embedded in the file.

2. **Metadata JSON** (Google Takeout): In case of photos exported from Google Photos, the metadata is not embedded within the file itself, but is instead present in a separate sidecar ".json" file. Ente knows how to read these files.

3. **File name**: If the photo does not have a date in the Exif data (and it is not a Google takeout), for example, for screenshots or WhatsApp forwards, Ente will try and deduce the correct date for the file from the name of the file.

> [!NOTE]
>
> The filename-based detection works great most of the time, but it is inherently based on heuristics and is not exact.

If we are unable to decipher the creation time from these 3 sources, we will set the upload time as the photo's creation time.

### How do I view EXIF data for a photo? {#view-exif}

**On mobile, web and desktop:**

1. Open the photo
2. Tap the overflow menu (⋮) and select **Info** on mobile, or click the info button (i) on web/desktop
3. Scroll down to see basic metadata
4. Tap "View all Exif data" to see complete EXIF information

This shows all the technical data about the photo including camera settings, lens information, and more.

### What metadata can people I share with see? {#shared-metadata-visibility}

Anyone you share an album with sees the same item details you do: capture date, camera EXIF, captions, album titles, and map pins, because that metadata decrypts together with the photo.

Public link viewers see the same fields. Contributor emails on a shared album are masked on public links by default; see [Why do emails on my feed appear masked for public links?](/photos/faq/sharing-and-collaboration#masked-emails-public-links).

There is no public-link setting to hide location data. Editing a location in Ente does not remove GPS coordinates embedded in the original file or change the copy in your phone's photo library. Turning off downloads does not remove that metadata either.

To share without GPS metadata, create separate copies outside Ente with location metadata removed, then verify those copies before uploading and sharing them. Keep your original files privately, and keep them out of the album containing the sanitized copies.

## Importing from Google Photos

### How does Ente handle Google Takeout metadata? {#google-takeout-metadata}

When you export your data using Google Takeout, Google provides both your photos and their associated metadata JSON files. However, Google sometimes splits the JSON and photo across different zip files.

For example, `flower.jpeg` might be in one zip and `flower.json` in another. This prevents Ente from correctly mapping them.

**Best practice**: We [recommend](/photos/migration/from-google-photos/) unzipping all of your Google Takeout zips into a single parent folder, keeping subfolders as-is (do not flatten files), then importing that parent folder into Ente. This way, we can always correctly map photos and their metadata.

### Why are my Google Photos dates wrong after import? {#google-photos-dates-wrong}

A date can be incorrect if Ente could not match a photo to its Google Takeout JSON sidecar, or if the available metadata contains an unexpected date. Older desktop versions may also miss some of Google's sidecar filename formats.

Before retrying:

1. Update to the current stable [desktop app](https://ente.com/download/desktop).
2. Keep the original Takeout ZIPs and a separate backup of any files you plan to change or remove.
3. Extract all parts of the same Takeout into one combined folder. Merge matching album folders so their media and JSON files are together. Keep the album subfolders; do not flatten the files or leave each ZIP in its own numbered folder tree.
4. Check a few affected photos and their matching JSON files before attempting a larger repair.

**Repeating the import does not rewrite dates on files that Ente skips as already uploaded.** Updating the app or fixing the source folder alone does not change those existing items.

For photos already in Ente, you can select the affected items in the desktop app and use **Fix time** to choose the correct date. If you need to reimport dates from the Takeout sidecars, contact [support@ente.com](mailto:support@ente.com) for help with an affected-only reimport. Before removing anything, verify that your backup opens and includes the originals and matching JSON files. Do not delete your entire library or empty Trash just to test a date repair.

If an import is still running, [stop the upload](/photos/migration/from-local-hard-disk#stop-and-resume-an-upload) before cleanup. Files still present in the selected source can be uploaded again during that import or a later retry.

## Editing Metadata

### What metadata is preserved when I edit a photo? {#metadata-preserved-after-edit}

When Ente creates an edited copy on mobile, it preserves key camera information along with the photo's date, time, and location metadata. Other metadata may not be retained in the edited copy.

For JPEG photos, an edit that only rotates or flips the image is applied without re-encoding it, preserving the original image quality. Other image edits may re-encode the photo.

The original photo remains untouched.

### Does saving photo edits change the original or reduce resolution? {#saving-photo-edits}

Saving an image edit creates a separate copy. Your original photo stays unchanged.

The edited copy is rendered again, so its format, file size, and pixel dimensions can change. Cropping changes the dimensions by design. Other edits may re-encode the image even when you do not crop it. On mobile, most edits are saved as JPEG. On web and desktop, JPEG and WebP are kept where possible; other formats may be saved as PNG.

A smaller file size does not always mean fewer pixels. Compare the width and height of the original and edited copy to check whether the resolution changed. If you need a full-resolution edited version and the copy has fewer pixels, edit the original in an app that exports at full resolution, then upload that copy to Ente.

### How do I add descriptions or captions to photos? {#add-descriptions}

You can add descriptions (captions) to your photos in Ente:

**On mobile, web and desktop:**

1. Open the photo
2. Tap the overflow menu (⋮) and select **Info** on mobile, or click the info button (i) on web/desktop
3. Tap/click "Add description" or the description field
4. Type your description
5. Save

**Searchability**: Descriptions are searchable! You can find photos later by searching for words in their descriptions.

**Privacy**: Like all your data in Ente, descriptions are stored end-to-end encrypted.

### Can I bulk edit photo dates? {#bulk-edit-dates}

Yes! You can bulk-edit creation time of photos from the desktop app:

1. Multi-select the photos you want to edit (Ctrl/Cmd+click or Shift+click)
2. Select the "Edit time" option from the action bar
3. Choose the correct date/time
4. Apply to all selected photos

This is useful for:

- Fixing photos with incorrect timestamps
- Adjusting timezone differences
- Correcting dates on scanned photos

> [!NOTE]
>
> This feature is currently only available on the desktop app.

### Can I bulk edit photo locations? {#bulk-edit-locations}

Yes! You can bulk-edit location coordinates:

**On mobile:**

1. Long press to multi-select the photos you want to edit
2. Tap "Edit location" from the action bar
3. Choose the correct location on the map
4. Tap Save

**On web/desktop:**

1. Click to select photos (Ctrl/Cmd+click or Shift+click for multiple)
2. Click the edit location icon in the selection bar
3. Click on the map to set the location, or drag the pin to adjust
4. Click "Save location"

This is useful for:

- Adding location to photos without GPS data
- Correcting wrong GPS coordinates
- Organizing photos by location after the fact

### How do I fix incorrect photo dates? {#fix-incorrect-dates}

Photos sometimes have incorrect dates due to:

- Camera settings being wrong
- Timezone issues
- Scanned photos without proper metadata

**To fix dates:**

1. Use the bulk date editing feature (see above)
2. Select photos with incorrect dates
3. Apply the correct date/time

Ente will store your corrections and sync them across all your devices.

### What do the Fix time options mean? {#fix-time-options}

- **Exif:DateTimeOriginal**: The original capture timestamp saved in the file's EXIF metadata.
- **Exif:DateTimeDigitized**: The timestamp for when the image was converted to a digital file, such as when it was scanned.
- **Exif:MetadataDate**: The timestamp for when the metadata was last updated. Use this only if the capture timestamps are incorrect.
- **File name**: Parses a date from the file name, if it contains one.
- **Custom time**: lets you enter the exact date and time manually.

### Are my metadata edits reversible? {#edits-reversible}

Yes! When you edit metadata (dates, locations, descriptions) in Ente, the **original file is never modified**. Your edits are stored separately.

This also means that changing a location in Ente does not strip embedded GPS from the original or update the copy in your phone's photo library. Before sharing a file without location data, see [what metadata recipients can see](#shared-metadata-visibility).

When you export your photos:

- You get the exact original file
- Edits are saved in a separate JSON file (same format as Google Takeout)
- This preserves both the original and your modifications

This means:

- You can always access the original metadata
- Your edits are preserved when exporting
- Your original files remain untouched

### How do I edit photo filenames? {#edit-filenames}

You can rename photos in Ente:

**On mobile and web:**

1. Open the photo
2. Tap the overflow menu (⋮) and select **Info** on mobile, or click the info button (i) on web
3. Tap/click on the filename
4. Enter the new name
5. Save

The original filename is preserved, and your edit is stored separately (similar to other metadata edits).

### Can I add location data to photos that don't have it? {#add-location}

Yes! You can manually add location data to any photo:

**On mobile:**

1. Select the photo(s)
2. Tap "Edit location" from the menu
3. Select the location on the map
4. Tap Save

**On web/desktop:**

1. Open the photo and click the info button (i)
2. In the Location section, click "Add"
3. Click on the map to set the location, or drag the pin to adjust
4. Click "Save location"

You can also add location to multiple photos at once. Learn more at [Bulk edit photo locations](#bulk-edit-locations).

This adds GPS coordinates to the photo's metadata, allowing you to:

- View them on the map
- Search by location
- Organize photos by where they were taken

## Exporting Metadata

### Does the exported data preserve metadata? {#export-data-preserve-metadata}

Yes, the metadata is written out to a separate JSON file during export. Note that the original is not modified.

When you export your library, suppose you have `flower.png`. You will end up with:

```
flower.png
metadata/flower.png.json
```

Ente writes this JSON in the same format as Google Takeout so that if a tool supports Google Takeout import, it should be able to read the JSON written by Ente too.

> One small difference: to avoid clutter, Ente puts the JSON in the `metadata/` subfolder, while Google puts it next to the file. Ente itself will read it from either place.

Here is a sample of how the JSON looks:

```json
{
    "description": "This will be imported as the caption",
    "photoTakenTime": {
        "timestamp": "1613532136",
        "formatted": "17 Feb 2021, 03:22:16 UTC"
    },
    "creationTime": {
        "timestamp": "1613532136",
        "formatted": "17 Feb 2021, 03:22:16 UTC"
    },
    "modificationTime": {
        "timestamp": "1640225957",
        "formatted": "23 Dec 2021, 02:19:17 UTC"
    },
    "geoData": {
        "latitude": 12.004170700000001,
        "longitude": 79.8013945
    }
}
```

Ente writes both timestamp blocks: `photoTakenTime` holds the photo's capture time (the value other apps and Takeout expect), while `creationTime` is kept only for backward compatibility with older exports that relied on it and may be dropped in a future version. When importing, Ente treats `photoTakenTime` as canonical and falls back to `creationTime` if needed. `geoDataExif` will be considered as a fallback for `geoData`.

> [!NOTE]
>
> The `creationTime` field is deprecated and will be removed in a future release. Prefer `photoTakenTime`.

### What happens to file creation time during export? {#file-creation-time}

The photo's data will be preserved verbatim, however when it is written out to disk on a new machine a new file gets created. This file will not have the same file system creation time as the file that was uploaded.

There are two reasons for this:

1. **"Creation time" is not universal**: For example, Linux does not support it. From the man page of [fstat](https://linux.die.net/man/2/fstat), we can see that this information is just not recorded by the file system on Linux.

2. **Cannot be set from browsers or mobile apps**: There isn't a way to set it even on Windows and macOS for files downloaded from the browser, or for files saved from the mobile apps.

We have considered modifying our desktop and CLI clients to write back the photo's creation time into the creation time of the filesystem file during export. But it is not clear if this would be less or more confusing due to inconsistencies across platforms.

Ente is a photos app, not a file system backup app. Customers for whom the creation time of the file on disk is paramount might be better served by file backup apps.

### Does the date taken of a file change when the file is downloaded or exported? {#date-taken-preservation}

Ente preserves the original file and its embedded metadata. If the original contains an EXIF capture date, that value remains in the file. Ente does not add or rewrite an EXIF date just because a different date appears in Ente.

A date imported from a Google Takeout JSON file, or changed later in Ente, is stored separately. A library export includes that date in a metadata JSON sidecar. Another app needs to read the sidecar to use it.

See [original files during export](#modify-originals) and [file-system creation times](#file-creation-time).

### Can I modify the original files during export? {#modify-originals}

No. Ente exports the original photos and videos without changing their embedded metadata. Metadata imported from Google Takeout JSON files and changes you make in Ente are written separately to metadata JSON files during library export.

Keep those sidecars with the originals when transferring to another app that supports them. See [the export metadata format](#export-data-preserve-metadata). To export selected albums with their metadata, you can also use [CLI photo export](/photos/features/utilities/cli#exporting-photos).

### How can I read the date used by Ente from my export? {#read-corrected-date-export}

Ente does not write imported or corrected dates back into the original file. To compare the values:

- **Original embedded date**: inspect the EXIF metadata in the photo file, for example with [ExifTool](https://exiftool.org/).
- **Date used by Ente**: open the matching JSON file in the export's `metadata/` folder and read `photoTakenTime`.

The exported date can come from the original metadata, an imported Takeout sidecar, a date inferred during import, or a later correction in Ente. The original file and the sidecar can therefore contain different dates.

### Why do some exported photos show the wrong date when imported into another app? {#wrong-export-date-other-app}

Another app may be reading only the original file's embedded date. Ente leaves that file unchanged. Dates imported from Google Takeout sidecars, inferred during import, or corrected in Ente are included in the export's metadata JSON sidecars.

If the original has no EXIF capture date, downloading the image alone does not add one. If its EXIF date differs from the date shown in Ente, the original embedded value remains unchanged too.

Keep the `metadata/` folder with the photos, and check whether the destination app reads Google Takeout-style JSON and accepts that folder layout. See [the export metadata format](#export-data-preserve-metadata) and [how to check the exported date](#read-corrected-date-export).

## Platform-Specific Behavior

### Do metadata edits sync across devices? {#edits-sync}

Yes! All metadata edits (dates, locations, descriptions, filenames) are synced across all your devices using end-to-end encryption.

When you edit metadata on one device:

- Changes appear on all other devices
- The original file remains unchanged everywhere
- Edits are preserved when exporting from any device

### Can I edit metadata on all platforms? {#platform-support}

**Available on mobile, web, and desktop:**

- Adding descriptions
- Editing filenames
- Viewing all EXIF data
- Adding and editing locations

**Desktop only:**

- Bulk editing dates ("Edit time" feature)

We're working on bringing all editing features to all platforms.

### A photo I shared into Ente from WhatsApp shows the wrong date in the timeline. Why? {#whatsapp-wrong-date}

Apps like WhatsApp strip the hidden "date taken" information from photos for privacy. When Ente can't find that information, and can't reliably extract it from the filename either (especially for videos), it falls back to the upload date.

To fix dates already uploaded, the easiest path is the desktop app, which supports bulk editing:

1. Install the desktop app and sign in.
2. Select the affected photos and videos.
3. Click **Edit time** in the action bar.
4. Set the correct date and apply.

The correction syncs to all your devices.

To prevent this for future shared media, save photos to your phone's gallery first and let Ente back them up from the gallery. Ente reads dates correctly when files come from the gallery rather than directly from a sharing intent.

### Why is GPS location missing when I share a photo to Ente on Android? {#android-share-gps-missing}

The Android share flow or the app you share from may send Ente a copy without its GPS metadata. Ente cannot preserve location data it does not receive.

To upload the original photo with its location data:

1. Turn on backup for its folder in **Settings > Backup > Backed up folders**.
2. Or open an album in Ente, tap **Add**, and select the photo from your device instead of using Android's Share menu.

If the location is still missing, check that the original photo contains GPS coordinates.

### Does Ente modify any file metadata? {#modify-file-metadata}

No. Ente never modifies your original files or their embedded metadata. All edits you make are stored separately in Ente's database and:

- Synced encrypted across your devices
- Written to separate JSON files during export
- Kept separate from the original file

Your original photos with their original metadata remain untouched.
