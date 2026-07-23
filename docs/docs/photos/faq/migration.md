---
title: Migration FAQ
description: Frequently asked questions about migrating to Ente Photos from other services
---

# Migration

## Importing from Google Photos

### How much Ente storage do I need when importing my Google Photos Takeout? {#google-takeout-storage}

When importing your Google Photos Takeout into Ente, your storage usage is based on your actual Google Photos library size - not the (much larger) Takeout ZIP size.

For example, if Google Photos reports 30 GB used, but your Takeout export is 100 GB, you will need around 30 GB of Ente storage.

Google includes duplicate copies of the same photos inside multiple album folders in the Takeout export. Ente detects these during import and only stores a single original.

If any duplicates slip through and you temporarily hit your storage limit, you can clean them up using the desktop app's built-in deduplication tool:

`Desktop app → Settings → Deduplicate files`

This removes exact duplicates while keeping one original safely.

### How does Ente handle Google Takeout metadata? {#google-takeout-metadata}

When you export your data using Google Takeout, Google provides both your photos and their associated metadata JSON files. However, Google sometimes splits the JSON and photo across different zip files.

For example, `flower.jpeg` might be in one zip and `flower.json` in another. This prevents Ente from correctly mapping them.

**Best practice**: We [recommend](/photos/migration/from-google-photos/) unzipping all of your Google Takeout zips into a single parent folder, keeping subfolders as-is (do not flatten files), then importing that parent folder into Ente. This way, we can always correctly map photos and their metadata.

### Why are my Google Photos dates wrong after import? {#google-photos-dates-wrong}

If the dates appear incorrect after importing from Google Takeout, it's usually because:

- The photo's Exif data has a different date than Google's metadata JSON
- The JSON file wasn't matched with the photo during import

To fix this:

1. Make sure you unzipped all Google Takeout zips into one parent folder (with subfolders kept as-is)
2. Import that parent folder (not individual zips)
3. This ensures Ente can match JSON files with their photos

### Can I retry failed uploads?

Yes. You can check the progress/info tab that appears during upload to determine the cause of failed uploads. You can also drag and drop the folder or files again. Ente will automatically ignore already backed up files and try to upload just the rest.

### Why does my google takeout upload fail?

This usually occurs due to a network connectivity issue:

- Check your internet connection is active
- Try switching networks (WiFi to mobile data or vice versa)
- If using VPN, try disabling it temporarily
- Check if your firewall is blocking Ente's servers
- On desktop/web, try disabling "Faster uploads" in Settings > Preferences > Advanced

For more check: [Troubleshooting](https://ente.com/help/photos/faq/troubleshooting#desktop-app-issues)

### How do I prevent duplicates while migrating from Google Photos? {#prevent-duplicates-migration}

Ente detects duplicates by identical hash and file name.

Duplicates can occur:

1. **If editing is done in Google Photos.** The original photo as well as edited copies are saved and exported separately in Google Takeout. They have different hash values and are thus not detected as duplicates by Ente.

2. **If storage saver mode is enabled or compressed photos are stored in Google Photos.** If the same photos are present locally in phone in original quality and are also backed up to Ente along with Google Takeout, Ente does not recognize these as duplicates due to different hash values.

3. **If upload from Google Takeout on desktop and backup from mobile folders run simultaneously.** When the same photos come in from two different sources at the same time, Ente may not detect they are duplicates and both copies may be uploaded.

**Steps to prevent duplication due to the above reasons:**

1. All required photo folders from mobile are backed up to Google Photos.
2. Disable backup in Google Photos.
3. Request Google Takeout.
4. Empty any local photo folders which are part of Google Takeout and also need to be backed up post migration.
    - External tools can be used to deduplicate Google Takeout before importing into Ente.
5. Import Google Takeout using Ente desktop app.
6. After successful import, enable desired photo folder backup on Ente mobile app.

**If duplicates still arise after migration and upload:**

- Use the [Remove duplicates](/photos/features/albums-and-organization/storage-optimization#remove-exact-duplicates) option.
- Use the [Remove similar images](/photos/features/albums-and-organization/storage-optimization#remove-similar-images) option. (Ensure Machine Learning is enabled in Settings for similar-image detection)

> [!NOTE]
>
> Special mention to l1br3770 for his [detailed guide](https://www.reddit.com/r/enteio/comments/1jyxk4b/howto_migration_from_google_photos_pitfalls/).

### Why aren't my Google Takeout albums preserved after import? {#takeout-albums-not-preserved}

Usually because the album folders weren't placed directly inside one parent folder during extraction. Ente expects this structure:

```
Google Photos/
  Album 1/
  Album 2/
  Album 3/
```

Not this:

```
Google Photos/
  Takeout 1/
    Album 1/
    Album 2/
  Takeout 2/
    Album 3/
```

When you have multiple Takeout ZIPs, extract all of them into the same parent folder so the album folders end up at the same level — don't keep `Takeout 1/`, `Takeout 2/` as wrappers.

If photos already uploaded without the right album assignment, Ente can't reconstruct it after the fact. The cleanest fix:

1. Delete the existing upload and empty Trash.
2. Re-arrange the extracted Takeout contents into a single merged folder as shown above.
3. Re-upload through the desktop app.

### Why is my storage usage in Ente higher than what Google Photos showed? {#ente-storage-higher-than-google}

Google Photos and Ente count storage differently:

- **Compression**: Google's "Storage saver" mode compresses photos. Ente always stores the original quality, so the same library can take noticeably more space.
- **Edited photos and motion photos**: Takeout exports the original and any edited copies as separate files. Live/motion photos export as separate image and video components.
- **Shared and partner-shared items**: These often appear as additional files in Takeout.
- **Older uploads**: Photos from before Google's storage policy change didn't count toward Google's quota but are stored fully in Ente.
- **Duplicates in Takeout**: Google repeats files across album folders. Ente tries to deduplicate, but some can slip through.

To clean up duplicates after import, use `Desktop app > Settings > Deduplicate files`. See [How do I prevent duplicates while migrating from Google Photos?](#prevent-duplicates-migration).

### Does Google Photos show the full size of my library? {#google-photos-full-size}

Not always. The storage figure shown in Google Photos only counts items that use your Google quota. Older uploads, partner-shared photos, and other items can be present in Takeout without showing up in that number.

### What is the best way to migrate Google Photos shared albums to Ente? {#migrate-google-photos-shared-albums}

Google Takeout does not reliably export shared albums:

- Shared albums you own may appear in Takeout and may export as a folder, but not consistently. Some photos may be missing, folders may be split, or the album might not be recreated at all.
- Shared albums you joined (someone else owns) do not export unless you manually added each photo to your own library.
- Shared-album names or structure are not preserved in the metadata, hence the shared album cannot be automatically reconstructed.
- Metadata regarding who shared the photo with you will not be present.

The best way to export shared albums is to manually download each shared album:

1. Open the album in Google Photos
2. Menu (⁝) → Download all
3. Extract the ZIP → you get a clean folder
4. Import that folder into Ente → the album is preserved correctly

This will reliably preserve the shared album name and contents.

### How do I move from Google Photos Partner Sharing to Ente? {#migrate-google-photos-partner-sharing}

Google Photos Partner Sharing automatically shares one person's entire library (or photos of specific people) with a partner. Ente achieves a similar result through shared albums. However, saving any shared photos (vs viewing) counts against the user's storage.

#### 1. Both partners export and import their libraries

Each partner should export their own library via [Google Takeout](/photos/migration/from-google-photos/) and import it into their own Ente account.

> [!NOTE]
>
> Photos only visible to you through Partner Sharing (not saved to your library) are **not** included in your Takeout. Only the partner who originally took those photos will have them in their export. There is also no built-in filter to remove partner-shared photos from a Takeout import - so duplicates may occur if both partners import and then share entire libraries on Ente.

#### 2. Set up sharing on Ente

**Share your Camera folder (recommended):**

1. Open the **Camera** folder (Android) or **Recents** (iOS)
2. Tap the Share icon and add your partner as a [Viewer, Collaborator, or Admin](/photos/features/sharing-and-collaboration/collaboration#collaborating-with-ente-users)
3. Ask your partner to do the same for you

New photos backed up to these folders will automatically sync to your partner's device.

**Share all existing albums at once:**

1. Long-press any album to enter selection mode
2. Tap "All" at the bottom right to select every album
3. Tap Share and add your partner as a [Viewer, Collaborator, or Admin](/photos/features/sharing-and-collaboration/collaboration#collaborating-with-ente-users)

**Auto-add photos of specific people:**

Use [Smart albums](/photos/features/albums-and-organization/auto-add-people) to automatically add photos of selected people (e.g., your kids) to a shared album.

#### 3. Consider a Family plan

A [Family plan](/photos/features/account/family-plans) lets both partners share a single subscription's storage at no extra cost, while keeping libraries private.

> [!NOTE]
>
> Shared albums on Ente have the extra advantage of [Admin roles](/photos/features/sharing-and-collaboration/collaboration#permissions-explained), E2EE [comments and likes](/photos/features/sharing-and-collaboration/comments-and-likes), [collect links](/photos/features/sharing-and-collaboration/collaboration#collecting-photos-from-anyone), bulk ZIP download, [custom domains](/photos/features/sharing-and-collaboration/custom-domains/), trip layout, and download restrictions.

### Can I reupload the Google Takeout in case I did not upload it correctly the first time?

Yes, you can start fresh.

- Open home gallery view and press Ctrl + A to select everything, then delete all items.
- After that, open Trash. It may take a little while for all deleted items to sync into Trash.
- Once synced, empty Trash to permanently remove all items from your account.

Once this is done, you can reupload your entire Google Takeout folder again using the desktop app.

### Is there a way to remove partner sharing photos when importing via Google Takeout?

There is currently no built-in filter to automatically remove partner-shared photos when importing from Google Takeout.

## Importing from Apple Photos

### Why is it recommended to migrate Apple Photos from mobile? {#why-migrate-apple-photos-from-mobile}

It is highly recommended to import from Apple Photos via mobile rather than desktop, as mobile upload preserves metadata, while desktop upload may lose metadata (reason stated [below](#can-i-import-apple-photos-via-desktop)), requires manual export and sequential naming for live photos.

### Can I import Apple Photos via desktop? {#can-i-import-apple-photos-via-desktop}

It is highly recommended to import from Apple Photos via mobile rather than desktop.

Some photos may not have EXIF metadata embedded directly within the image file. In these cases, Apple Photos exports metadata into separate `.XMP` sidecar files instead of writing it into the photo itself.

Currently, the desktop app does not read metadata from separate XMP sidecar files - it can only recognize metadata that is embedded within the file.

We recommend to upload the photos using the iPhone app as iOS exports typically include embedded metadata, which ensures dates and other details are preserved correctly.

However, for any reason, if desktop is the only way to import, you can follow the steps below:

#### 1. Export your data from the Apple Photos app.

Select the files you want to export (`Command + A` to select them all), and click on `File` > `Export` > `Export Unmodified Originals`.

In the dialog that pops up, select File Name as `Sequential` and provide any prefix you'd like. This is to make sure that we combine the photo and video portions of your Live Photos correctly.

Finally, choose an export directory and confirm by clicking `Export Originals`. You will receive a notification from the app once your export is complete.

#### 2. Import into Ente

Now simply drag and drop the downloaded folders into [our desktop app](https://ente.com/download/desktop) and grab a cup of coffee (or a good night's sleep, depending on the size of your library) while we handle the rest.

> Note: In case your uploads get interrupted, just drag and drop the folders into the same albums again, and we will ignore already backed up files and upload just the rest.

## Importing from other cloud services

### I have photos on my phone and also photos autosynced from my phone to a cloud storage. How do I upload all these photos to Ente without duplicates? {#prevent-duplicates-cloud-sync}

Ente detects duplicates by identical hash and file name. If your previous cloud service modified your photos in any way (re-compressed them, stripped or altered EXIF metadata, converted formats, etc.), the hashes won't match and duplicates may occur.

**Recommended workflow:**

1. Turn off auto-upload in your current cloud app.
2. Download all your photos and videos from your current cloud service to your computer.
3. Upload them to Ente via the desktop app or web. The desktop app handles large uploads more reliably.
4. Sign into Ente on your phone and let the app fully sync.
5. Enable [automatic backups](/photos/getting-started/daily-use#select-albums-folders-to-back-up). If duplicates are a concern, enable the "Back up only new photos" toggle (`Settings > Back up > Back up settings > Back up only new photos`), which skips existing photos on your phone and backs up only new ones.

**If duplicates still arise after migration and upload:**

- Use the [Remove duplicates](/photos/features/albums-and-organization/storage-optimization#remove-exact-duplicates) option.
- Use the [Remove similar images](/photos/features/albums-and-organization/storage-optimization#remove-similar-images) option. (Ensure Machine Learning is enabled in Settings for similar-image detection)
