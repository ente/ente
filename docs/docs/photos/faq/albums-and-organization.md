---
title: Albums and Organization FAQ
description: Frequently asked questions about organizing photos with albums, hiding, archiving, and deletion in Ente Photos
---

# Albums and Organization

## Albums {#albums-section}

### Can Ente albums be nested? {#nested-albums}

No, Ente albums cannot be nested currently. When you upload a nested folder structure using the "Separate albums" option, Ente will create a separate album for each nested folder, but these albums themselves will not be nested - they will all appear as top-level albums.

For example, if you have folders organized as `Photos/2024/Summer/Beach`, Ente will create separate albums but display them as a flat list rather than maintaining the hierarchical structure.

### What happens when I upload a nested folder structure? {#nested-folders}

When you upload a folder with nested subfolders using the desktop app, you'll see two options:

**Single album**: Creates one Ente album with the parent folder's name and syncs all files from all nested folders into this single album.

**Separate albums**: Creates separate albums for each nested folder. Only the leafmost folder name is used for the album name. For example, both `A/B/C/D/x.png` and `1/2/3/D/y.png` will be uploaded into the same Ente album named "D".

Note that in separate album mode:

- Only nested folders with at least one file will create an album
- Empty folders (or folders containing only other folders) will be ignored

### Can I sync a folder with multiple subfolders? {#sync-subfolders}

Yes! When you drag and drop a folder with multiple subfolders onto the desktop app, Ente will detect the structure and prompt you to choose between creating a single album or separate albums for each folder.

This works for:

- Drag and drop operations
- Upload selector
- [Watch folders](/photos/faq/backup-and-sync#watch-folders) setup

The app will intelligently handle the folder structure based on your preference.

### Why don't all photos from a new iOS album appear in the corresponding Ente album? {#ios-album-sync}

If you create a new album on your iOS device after the initial backup, the photos in that album may have already been uploaded to another album in Ente.

When you select multiple albums for backup, Ente prioritizes uploading each photo to the album with the fewest photos. This means a photo will only be uploaded once, even if it exists in multiple albums on your device.

**To fix this**: Open the "On Device" album in Ente, select all photos, and manually add them to the corresponding album in Ente.

### What happens if I reorganize my photos in the iOS Photos app after backing up? {#ios-reorganize}

Reorganizing photos in the iOS Photos app (e.g., moving photos to new albums) won't automatically reflect in Ente. You'll need to manually add those photos to the corresponding albums in Ente to maintain consistency.

This is because iOS doesn't notify apps when photos are moved between albums - apps only see when new photos are added to the device.

### How does Ente handle photos that are part of multiple iOS albums? {#multiple-ios-albums}

When you select multiple albums for backup, Ente prioritizes uploading each photo to the album with the fewest photos. This means a photo will only be uploaded once, even if it exists in multiple albums on your device. If you create new albums on your device after the initial backup, those photos may not appear in the corresponding Ente album if they were already uploaded to a different album.

### What is the best way to migrate Google Photos shared albums to Ente? {#google-photos-shared-albums}

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

## Uncategorized

### What is the Uncategorized album? {#what-is-uncategorized}

Uncategorized is a special system album in Ente where photos are automatically placed when they don't belong to any other album. It acts as a catch-all location to prevent photos from being lost when they're removed from all regular albums.

Photos appear in Uncategorized when:

- You remove a photo from its last remaining album
- You delete an album but choose to keep the photos
- You delete a file from a [watched folder](/photos/faq/backup-and-sync#watch-folders) on desktop

Learn more in the [Uncategorized feature guide](/photos/features/albums-and-organization/uncategorized).

### Why are photos appearing in Uncategorized? {#why-uncategorized}

Photos automatically move to Uncategorized in these situations:

**When you remove from last album**: If you remove a photo from the only album it belongs to, it goes to Uncategorized instead of being deleted.

**When deleting albums**: If you delete an album and choose "Keep photos", any photos that were exclusively in that album move to Uncategorized.

**When deleting from watched folders**: On desktop, if you delete a file from a folder being watched by Ente, the corresponding photo in Ente moves to Uncategorized (it's not permanently deleted).

> [!NOTE]
>
> Photos uploaded by others (from shared albums) do not go to Uncategorized when removed.

### If all my photos are in Uncategorized, how do I move them to resemble the local album structure I have on my device? {#move-uncategorized-to-albums}

If your photos are in Uncategorized instead of their original albums, you can reorganize them manually:

1. Open **On device**, go to an album, select all photos, and add them to the corresponding album in Ente.
2. Repeat for each album.
3. Open Uncategorized, tap the three dots menu, and select **Clean up Uncategorized**. This removes any photos from Uncategorized that now exist in another album.

Alternatively, if you have the original photos on your device, you can delete them from Uncategorized and re-upload them via **Backup folders** on mobile.

### How do I clean up Uncategorized items? {#clean-uncategorized}

**On mobile:**

1. Open the Uncategorized album
2. Tap the three dots (overflow menu)
3. Select "Clean Uncategorized"

This will automatically remove all files from Uncategorized that are also present in another album that you own. Only files exclusive to Uncategorized will remain.

**Manual cleanup:** You can also manually:

- Add photos from Uncategorized to specific albums
- Delete photos you don't need from Uncategorized
- Move photos to appropriate albums by selecting them and choosing "Add to album"

### Can I delete the Uncategorized album? {#delete-uncategorized}

No, you cannot delete the Uncategorized album itself because it's a system album. However, you can:

- Delete individual photos from Uncategorized
- Use "Clean Uncategorized" to remove photos that exist in other albums
- Empty it completely by deleting all photos within it

The Uncategorized album will always exist as a container for photos without other albums.

### Do photos in Uncategorized count against my storage? {#uncategorized-storage}

Yes, photos in Uncategorized count towards your storage quota just like photos in any other album. If you want to free up storage, you'll need to delete photos from Uncategorized (they'll move to Trash for 30 days before permanent deletion).

### Can I organize photos in Uncategorized? {#organize-uncategorized}

Yes! Photos in Uncategorized work just like photos in regular albums. You can:

- View them by date
- Search for them
- Add them to other albums (recommended to keep them organized)
- Delete them if you don't need them
- Share individual photos

The best practice is to periodically review Uncategorized and add photos to appropriate albums or delete ones you don't need.

### What happens if I add an Uncategorized photo to an album? {#add-from-uncategorized}

When you add a photo from Uncategorized to another album:

- The photo will appear in both the new album AND Uncategorized
- It will remain in Uncategorized unless you use "Clean Uncategorized"
- Running "Clean Uncategorized" will remove it from Uncategorized since it now exists in another album

This behavior ensures photos aren't accidentally lost.

### Why do some photos stay in Uncategorized after cleaning? {#photos-stay-uncategorized}

The "Clean Uncategorized" function only removes photos that exist in at least one other album that you own. Photos remain in Uncategorized if:

- They don't exist in any other album yet
- They only exist in albums shared by others (not albums you own)
- They were uploaded by others in collaborative albums

If you want these photos organized, manually add them to appropriate albums.

### Can I prevent photos from going to Uncategorized? {#prevent-uncategorized}

Not directly, but you can minimize it:

1. **Be careful when removing from albums**: Before removing a photo from an album, check if it exists in other albums
2. **Use "Delete album and photos" option**: When deleting albums, choose to delete photos too if you don't need them
3. **Organize regularly**: Ensure photos belong to at least one album before removing them from others
4. **For watched folders**: Keep files in watched folders or move them to another watched folder instead of deleting them

### How do I view Uncategorized photos? {#view-uncategorized}

**On mobile:**

- Open the Albums tab
- Scroll to the bottom
- Tap on "Uncategorized"

**On web/desktop:**

- Click the hamburger menu (three lines) in the top left
- Select "Uncategorized"

The Uncategorized section shows all photos that aren't in any other album you own.

## Hide vs Archive {#hide-vs-archive}

### What's the difference between hiding and archiving? {#difference}

**Hiding** provides maximum privacy - hidden photos are completely removed from everywhere in the app (timeline, albums, search results) except the special "Hidden" section, which requires biometric authentication (FaceID/TouchID) or your device passcode to access.

**Archiving** is for decluttering - archived photos are only removed from your home timeline and memories, but still appear in albums and search results. No authentication is required to view archived items. Use archiving when you want to clean up your timeline (e.g., old screenshots) without completely hiding the content.

For detailed guides, see [Hide](/photos/features/albums-and-organization/hide) and [Archive](/photos/features/albums-and-organization/archive).

### Can I hide albums or photos that are shared with me? {#hide-shared}

You can hide an album shared with you, but you can't hide an individual photo shared with you since hiding of individual files only works for files you own.

### Do archived photos appear in search results? {#archive-search}

Yes, archived photos still appear in search results and in their respective albums. Archiving only removes photos from your home timeline and memories section. If you want photos completely hidden from search results too, use the "Hide" feature instead of archiving.

### How do I hide photos in Ente? {#how-to-hide}

Open the photo, tap the three dots menu (overflow menu), and select "Hide" (the action with the eye icon). Hidden items will only be accessible from the special "Hidden" category at the bottom of the Albums screen, which requires biometric authentication to view.

> [!NOTE]
>
> Hidden items may still appear in "On device" albums within Ente as long as they're present in your native device gallery. Once you remove them from your device, they'll stop showing up there.

### How do I archive photos in Ente? {#how-to-archive}

Long press to select the photo(s) you want to archive, then select "Archive" from the bottom menu. To archive an entire album, open the album, tap the three dots menu, and select "Archive album". You can view archived content anytime by going to the "Archive" section (no authentication required).

## Storage Management

### How can I free up space on my device? {#free-up-device-space}

Once your photos are backed up to Ente, you can safely delete them from your device to reclaim storage space:

**On mobile:**

Open `Settings > Backup > Free up space`, review the amount of space that will be freed, and confirm to delete backed-up photos from your device.

Your photos remain in Ente and will be automatically downloaded when you view them in the app.

Learn more in the [Storage optimization guide](/photos/features/albums-and-organization/storage-optimization).

### How can I remove duplicate photos from my library? {#remove-duplicates}

If you have exact duplicate files across different albums, you can use the manual deduplication tool:

**On mobile:**

Open `Settings > Backup > Free up space > Remove duplicates`, review the duplicates found, and confirm to remove them.

**On desktop:**

Open `Settings > Deduplicate files`, review the duplicates found, and confirm to remove them.

This keeps one copy of each unique file and creates symlinks in all albums, freeing up storage while maintaining your album structure.

Learn more in the [Storage optimization guide](/photos/features/albums-and-organization/storage-optimization).

### How can I find and remove similar photos? {#remove-similar}

Ente's ML-powered similar images feature helps you find visually similar (but not identical) photos:

**On mobile:**

Open `Settings > Backup > Free up space > Similar images`, review each group of similar photos, choose which to keep and which to delete, and confirm your selections.

**On desktop:**

Desktop doesn't have a "Similar images" feature. Use the mobile app for AI-powered similar image detection.

Ente intelligently manages symlinks to ensure no album loses all photos from a scene.

Learn more in the [Storage optimization guide](/photos/features/albums-and-organization/storage-optimization).

### Will I lose my photos when freeing up device space? {#free-up-space-safe}

No! Freeing up device space only removes local copies from your device. All photos remain safely stored in Ente's encrypted cloud and can be viewed or re-downloaded anytime.

### Can I choose which photos to delete from my device? {#selective-device-deletion}

Currently, the "Free up space" feature removes all backed-up photos at once. If you want selective deletion, manually delete specific photos from your device's gallery app.

### How much space will I free up? {#how-much-space-freed}

The app will show you the exact amount before you confirm. This is typically the total size of all backed-up photos and videos on your device.

### Will new photos still backup automatically after freeing up space? {#backup-after-free-space}

Yes! After freeing up space, new photos you take will continue to backup automatically to Ente.

### What's the difference between duplicates and similar images? {#duplicates-vs-similar}

- **Duplicates**: Exact same file (identical hash) - automatically detected during upload
- **Exact duplicates tool**: Finds and removes exact duplicates across your entire library
- **Similar images**: Visually similar but not identical photos - uses ML to detect

Learn more in [Storage optimization](/photos/features/albums-and-organization/storage-optimization).

### Does removing duplicates affect automatic duplicate detection? {#manual-vs-auto-dedup}

No. Automatic duplicate detection during upload continues to work regardless of whether you use the manual deduplication tool.

Learn more about [Duplicate detection during backup](/photos/features/backup-and-sync/duplicate-detection).

## Trash and Deletion {#trash}

### How do I delete photos in Ente? {#delete-photos}

When you delete a photo or video in Ente, it's moved to Trash rather than being permanently deleted immediately.

**On mobile:**

- Long press to select the photo(s) you want to delete
- Tap the trash icon in the action bar
- Confirm the deletion

**On web/desktop:**

- Select the photo(s) you want to delete
- Click the trash icon or press the Delete key
- Confirm the deletion

Deleted items remain in Trash for 30 days before being permanently deleted automatically.

Learn more in the [deletion feature guide](/photos/features/albums-and-organization/deleting).

### How do I restore deleted photos? {#restore-photos}

If you accidentally deleted photos, you can restore them from Trash within 30 days:

**On mobile:**

- Open the Albums tab
- Scroll to the bottom and tap "Trash"
- Select the photos you want to restore
- Tap the "Restore" button

**On web/desktop:**

- Open the sidebar menu
- Click on "Trash"
- Select the items to restore
- Click the "Restore" button

Restored photos will be moved to an album of choice.

### How do I permanently delete photos or empty trash? {#empty-trash}

To free up storage space immediately, you can permanently delete items from trash:

**To empty all trash:**

- Open Trash
- Click/tap "Empty trash" or the trash icon
- Confirm that you want to permanently delete all items

**To delete specific items:**

- Open Trash
- Select the items you want to permanently delete
- Choose "Delete permanently" from the menu
- Confirm the action

> [!WARNING]
>
> Permanently deleted items cannot be recovered.

### Can I recover files after 30 days in trash? {#recover-after-30-days}

No, files in trash are permanently deleted after 30 days and cannot be recovered. This is an irreversible operation.

If you need to keep certain files, make sure to restore them from trash before the 30-day period expires. We recommend regularly checking your trash if you're unsure about deleting certain items.

### Does trash count against my storage? {#trash-storage}

Yes, items in trash are included in your storage quota calculation. To free up storage space, you can:

- Manually empty your trash
- Permanently delete specific items
- Wait for automatic deletion after 30 days

Once files are permanently deleted (either manually or after 30 days), the storage space will be freed up and reflected in your account.

### What happens when I delete an album? {#delete-album}

When you delete an album in Ente, you'll be given two options:

1. **Delete album and keep photos**: The album is removed, but photos that were exclusively in that album are moved to the [Uncategorized](#uncategorized) section. Photos that exist in other albums remain there.

2. **Delete album and photos**: Both the album and all photos in it are moved to Trash. Photos will be permanently deleted after 30 days unless restored.

### Can I delete photos that are shared with me? {#delete-shared-photos}

You can remove shared photos from your view, but you cannot permanently delete photos that someone else owns. Only the owner of the photo can permanently delete it from Ente.

If someone has shared an album with you and you want to stop seeing it, you can leave the shared album or archive it instead.

### Do deleted photos on my device also delete from Ente? {#device-deletion-sync}

No. If you delete a photo from your device's native photos app, it will **not** be automatically deleted from Ente. This is by design for two reasons:

1. **Safety**: Prevents accidental loss of your backed-up photos
2. **Platform restrictions**: iOS and Android don't allow apps to automatically delete users' photos without manual confirmation

If you want to delete a photo from Ente, you must do it manually within the Ente app.

### What happens to deleted photos in collaborative albums? {#collaborative-deletion}

In collaborative albums, deletion permissions depend on your role:

- **If you're a viewer**: You cannot delete any photos from the album.
- **If you're a collaborator**: You can only delete photos that you uploaded. When you delete a photo you uploaded, it goes to your trash.
- **If you're an admin**: You can remove any photo from the album (including photos uploaded by others), but you can only permanently delete photos you own. Other participants' photos will be removed from the album but remain in their accounts. You can also [suggest deletion](/photos/faq/sharing-and-collaboration#suggest-deletion) for photos owned by others.
- **If you're the album owner**: You have all admin permissions, plus you can manage link settings and delete the album.

When a participant leaves or is removed from a shared album, any photos they uploaded are also removed from that album.

### Can I recover photos after deleting my account? {#recover-after-account-deletion}

No. When you delete your Ente account, all your data (including photos in trash) is permanently deleted and cannot be recovered. This is an irreversible operation.

Before deleting your account, make sure to:

1. [Export your photos](/photos/faq/advanced-features#export) if you want to keep them
2. Restore any photos from trash that you want to keep
3. Save any important albums or shared content

### How do I delete multiple photos at once? {#bulk-delete}

**On mobile:**

- Long press on the first photo to enter selection mode
- Tap additional photos to select them (or tap "Select all")
- Tap the trash icon in the action bar
- Confirm deletion

**On web/desktop:**

- Click the first photo
- Hold Shift and click the last photo to select a range (or Ctrl/Cmd+A for all)
- Press Delete key or click the trash icon
- Confirm deletion

All selected photos will be moved to trash together.

### Why can't I delete some photos? {#cannot-delete}

You may not be able to delete photos if:

- They are owned by someone else who shared them with you
- You don't have permission (you're a viewer or collaborator trying to delete others' photos)
- There's a sync issue - try refreshing or restarting the app

If you're an admin or owner and want to remove photos that others uploaded, you can remove them from the album or use [suggest deletion](/photos/faq/sharing-and-collaboration#suggest-deletion).

If you still can't delete photos you own, contact [support@ente.com](mailto:support@ente.com).

### How is Uncategorized different from Trash? {#uncategorized-vs-trash}

**Uncategorized** is for photos that aren't in any regular album but are still active in your library:

- Photos are fully accessible and searchable
- They count towards storage
- They won't be automatically deleted
- You can add them to albums anytime

**Trash** is for photos you've intentionally deleted:

- Photos are scheduled for permanent deletion after 30 days
- They're hidden from normal views (except Trash folder)
- They count towards storage until permanently deleted
- You can restore them within 30 days

## iOS Album Backup and Organization {#ios-album-backup}

### Why don't all photos from a new iOS album appear in the corresponding Ente album? {#ios-new-album}

If you create a new album on your device after the initial backup, the photos in that album may have already been uploaded to another album in Ente. To fix this, go to the "On Device" album in Ente, select all photos, and manually add them to the corresponding album in Ente.
