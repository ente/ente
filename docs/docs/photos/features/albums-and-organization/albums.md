---
title: Albums
description: Using albums in Ente Photos
---

# Albums

Albums in Ente are collections that help you organize your photos and videos. Similar to folders on your computer, albums group related photos together - but with some key differences:

**How albums work:**

- Albums are collections of photos and videos
- Each photo can belong to multiple albums simultaneously
- When you add a photo to multiple albums, it only counts once toward your storage
- Albums sync across all your devices automatically

**Key differences from folders:**

- **No nesting**: Unlike folders, albums cannot contain other albums - they're all at the same level
- **Multiple membership**: A single photo can exist in many albums without using extra storage
- **Device-independent**: Albums you create in Ente are separate from folders on your device

## Create a new album

Create albums to organize your photos and videos into collections.

### On mobile

- Open the **Albums** tab
- Tap the **Add new** button
- Enter a name for your album
- Tap **Create**

### On web / desktop

- Click the All Albums button (down arrow) in the top right corner
- Click the **New album** button
- Enter a name for your album
- Click **Create** or press Enter

You can also create albums by uploading photos from your device, manually adding photos to new albums, or automatically through features like [watch folders](/photos/features/backup-and-sync/watch-folders) on desktop.

## Rename album

Personalize your albums by giving them a meaningful name.

### On mobile

- Open the album
- Tap the overflow menu (three dots) in the top right corner
- Tap **Rename album**, then type in a new name
- Tap **Rename**

### On web / desktop

- Open the album
- Click the overflow menu (three dots) in the top right corner
- Click **Rename album**
- Type in a new name
- Click **Rename** or press Enter

## Set album cover

Select any photo you want to use as the cover for your album.

### On mobile

- Open the album you want to change
- Tap the overflow menu (three dots) in the top right corner
- Select **Set cover**
- A new screen will appear, prompting you to select the cover photo
- Browse through your photos and tap on the image you want to set as the album cover
- Tap **Use selected photo**

### On web / desktop

- Click the album you want to change
- Click the overflow menu (three dots) in the top right corner
- Click **Set cover**
- Select the image you want to use as the album cover
- Click **Confirm**

## View album photos on a map

Explore your album's memories based on their location.

- Open the album
- Tap the overflow menu (three dots) in the top right corner
- Select **Map**
- All photos from the album will appear in map view

Learn more about [Map and location](/photos/features/search-and-discovery/map-and-location) features.

## Sort albums

Maintain order in your albums by arranging them from newest to oldest.

### On mobile

- Open the album
- Tap the overflow menu (three dots) in the top right corner
- Select **Sort by**
- Choose **Newest first** or **Oldest first**

### On web / desktop

- Open the album
- Click the overflow menu (three dots) in the top right corner
- Click **Sort by**
- Select **Newest first** or **Oldest first**

## Pin albums

Keep your favorite albums at the top by pinning them for quick access.

### On mobile

- Open the album
- Tap the overflow menu (three dots) in the top right corner
- Tap **Pin album** or **Unpin album**

## Empty albums

Empty albums are albums that contain no photos or videos. They can occur in two ways:

**During import:**

Albums are automatically created whenever Ente detects any file that belongs to an album, even if that file is unsupported (for example, a text file). This can sometimes result in empty albums if there are no valid photo or video files inside.

**Manual creation:**

When you create an album but don't add any photos to it, the album remains empty.

### Delete empty albums

If you have multiple empty albums cluttering your album list, you can bulk delete them all at once.

**On mobile:**

1. Open the **Albums** tab
2. If you have more than 2 empty albums, you'll see a "Delete empty albums" button
3. Tap the button
4. Confirm the deletion

This will delete all empty albums from your library. The feature only appears after your initial sync is complete and when you have more than 2 empty albums.

## Uploading nested folders from desktop {#preserving-folder-structure}

When you upload photos and videos from your computer using the desktop app - whether by dragging and dropping a folder or zip file, or by setting up [watch folders](/photos/features/backup-and-sync/watch-folders) - you can choose how to handle nested folder structures.

### Single files or flat folders

If you upload individual files or a folder without nested subfolders, the desktop app will ask you to either:

- Upload to an existing Ente album, or
- Create a new album

The app will intelligently suggest a name for the new album based on the folder name.

### Nested folder structures

If the folder contains nested subfolders and you choose to create a new album, you'll see two options:

**Single album:**

- Creates one Ente album named after the parent folder
- All files from all nested subfolders go into this single album
- Example: Folder `Photos` containing `New Year/` and `Summer/` → One album called "Photos" with all files

**Separate albums:**

- Creates a separate Ente album for each nested subfolder
- Only folders containing at least one file become albums (empty folders are ignored)
- Only the leaf folder name is used (e.g., both `A/B/C/Photos/x.jpg` and `1/2/3/Photos/y.jpg` go to an album called "Photos")
- Example: Folder `Photos` containing `New Year/` and `Summer/` → Two albums: "New Year" and "Summer"

> [!NOTE]
>
> Ente albums cannot be nested. In separate album mode, each nested folder becomes a top-level album - they won't be organized in a hierarchy.

Learn more about [watch folders](/photos/features/backup-and-sync/watch-folders) for automatic desktop syncing.

## Related FAQs

- [Can Ente albums be nested?](/photos/faq/albums-and-organization#nested-albums)
- [What happens when I upload a nested folder structure?](/photos/faq/albums-and-organization#nested-folders)
- [Can I sync a folder with multiple subfolders?](/photos/faq/albums-and-organization#sync-subfolders)
- [Why don't all photos from a new iOS album appear in the corresponding Ente album?](/photos/faq/albums-and-organization#ios-album-sync)
- [How does Ente handle photos that are part of multiple iOS albums?](/photos/faq/albums-and-organization#multiple-ios-albums)
