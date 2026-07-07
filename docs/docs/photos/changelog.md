---
title: Ente Photos - Changelog
description: Release notes of recent updates to Ente Photos mobile and desktop apps
---

# Changelog - Ente Photos

A short summary list of changes to the Ente Photos mobile and desktop apps. For a more descriptive list with screenshots and blog post links, see the [news](https://ente.com/news).

## v1.7.26 (desktop) - Jul 2026

- Fix machine learning features failing to load.

## v1.7.25 (desktop) - Jun 2026

- Reduce desktop app package size by excluding unused ONNX Runtime native binaries.
- Sign shipped Windows native modules and DLLs.
- Make the upload dialog draggable.
- Import Google Takeout favourites into Favourite Album.
- Navigate files keeping the File Info opened using Alt/Option + Arrow Keys
- Use Google Takeout metadata titles when naming imported folders.
- Update the Archive section to show only archived albums on the top bar.
- Fix link icon visibility for albums shared with people and a public link. By @yashs33244.
- Show files skipped during upload (hidden files and unreadable zips) in the upload progress.
- Support Traditional Chinese and Urdu translations.
- Update to Electron 42.

## v1.3.57 (mobile) - Jun 2026

- Redesigned the Search tab with improved spacing, previews, empty states, and keyboard handling.
- Improved Albums with Shared/Received filters, refreshed empty states, and better add-to-album flows.
- Fixed a bug in bulk file downloads and improved backup album selection.
- Added skipped backup file reasons, such as “Deleted from Ente”.
- Preserved draft comments when closing and reopening the photo comment panel.
- Polished app lock, login/signup, gallery, trash, and warning screens.

## v1.3.56 (mobile) - Jun 2026

- Update to media_kit v1.2.2 to fix app crashing on using media_kit video player.
- Add album title tooltips, fix album sorting labels, and consistent typography.
- Fixed album widgets repeatedly showing the same cached photos from selected albums.
- Fixed JPEG export artifacts in the image editor.
- Use app bar from new design on galleries.
- Stopped repeatedly retrying Apple Photos items that cannot be downloaded from iCloud during backup.
- Migrated remaining sharing calls from `Share` to `SharePlus`.

## v1.7.24 (desktop) - May 2026

- Upload files to shared albums
- Add shared files to your albums
- Add shared files to shared albums
- Favorite files in shared albums
- Indicator for shared files in map view

## v1.3.54 (mobile) - Jun 2026

- New design system
- Improved albums navigation
- Feed gets its own tab
- Bulk ignore faces from photo info
- Better OCR animations
- Faster file downloads
- Faster face thumbnail generation
- Fixed ML lookup failures for large offline galleries
- Fixed video edit delete navigation
- Fixed upload dates for files with ISO-like metadata timestamps
- Fixed grey screen after single-memory delete or favorite actions
- Better file-picker support for selecting photos in other Android apps

## v1.3.44 (mobile) - May 2026

- Added support for selecting photos in 3rd party apps
- Added support to review photos directly from camera apps
- Fixed issue with HEIC photos rendering
- Improvements in gallery scrolling performance

## v1.3.40 (mobile) - May 2026

- Faster Memories loading
- Memory lane improvements
- New QR Codes section in Discovery
- Photos loading improvements
- Better handling of high resolution images
- Fixed widget showing hidden photos

## v1.7.23 (desktop) - May 2026

- All People dialogs shows entire face clusters
- Public Albums app separated from Photos app
- Faster and Light-weight public albums
- Memory and Memory Lane links
- Improvements (Public albums, file viewer, metadata preservation on editing, and more)

## v1.3.36 (mobile) - Apr 2026

- Memories improvements
- View other family members
- Better OCR selection
- Fix dedupe cleanup progress percentage display
- Fix app going blank on iOS after deleting all empty albums
- Home gallery bug fixes

## v1.3.32 (mobile) - Apr 2026

- Memory Lane
- Share any memory or Memory Lane as a link
- Long press to detect QR codes in photos
- Long press to select text in photos
- Bug fixes and performance improvements

## v1.7.22 (desktop) - Mar 2026

- App lock
- Better people list experience (bigger view with search)
- Various bug fixes (map view tiles, etc)

## v1.3.28 (mobile) - Mar 2026

- Fix app getting stuck on splash screen
- Bug fixes and performance improvements

## v1.3.24 (mobile) - Mar 2026

- Fix app getting stuck on splash screen

## v1.3.22 (mobile) - Mar 2026

- Gallery mode to use Ente Photos without an account
- New shared albums card in feed
- Shared albums and shared photos notifications redirect to feed
- Friendlier help & support page
- Better people suggestions in person overview
- Bug fixes and performance improvements

## v1.7.21 (desktop) - Feb 2026

- Masonry layout for public albums
- Quick links
- Full viewer experience for single-photo/video links
- Update album cover
- Public album improvements
- Catalan language support

## v1.3.16 (mobile) - Feb 2026

- Fix broken map view

## v1.3.15 (mobile) - Feb 2026

- Faster search and discovery
- See shared photos in feed
- Fix window controls hiding app UI on iPadOS
- Ignore already named persons
- Fix iOS video player crash
- Fix pinch to zoom opening info sheet on video
- Refresh security toggles with latest account state (2FA + email verification)
- Fix file picker galleries getting clipped on wider screens
- More collage layouts

## v1.3.13 (mobile) - Feb 2026

- Cleanup hidden files in non-hidden albums
- Delete hidden files from device
- Hide shared albums
- Search in device albums

## v1.3.10 (mobile) - Feb 2026

- Notifications for likes and comments
- Support for hidden rituals
- Better upload reliability

## v1.7.18 (desktop) - Jan 2026

- Hide shared albums
- Right click context menu for photos
- Cleanup large files
- Fix search bar losing focus on last backspace
- Hide empty favorites album from albums bar
- Cleanup uncategorized photos
- Hide favorites from album selector dialogs
- Show current album in album selector for upload flow
- Sort albums when uploading, adding, moving photos
- Select all memories in gallery and albums view
- Edit location of photos and videos
- More sorting options of albums lists
- Improved UI for login and sign-up pages
- Improved map view rendering logic
- Upload directly to hidden albums

## v1.3.7 (mobile) - Jan 2026

- Settings screen redesign
- Search within settings
- Faster search tab loading
- Search bar moved to top
- Results screen redesign
- Search within discovery, location, file type sections
- Allow admin and album owner to delete comments
- Pinch to zoom on video
- View all ignored persons
- Better merge flow
- Search and custom sort on people page
- Consistent sorting of contacts
- Preview images for unsupported image formats
- Swap photos and tap to replace in collage creator
- Performance improvement on file info sheet
- Fix for music pausing when opening the app
- Fix for swipe to select issue on Samsung S devices
- Fix for splash screen issue after backup restore
- Fix for gallery issues on tablets and landscape mode
- Fix for uncategorised page not updating after move

## v1.3.0 (mobile) - Jan 2026

- Likes and comments
- Admin role for albums
- Video streaming improvements

## v1.7.17 (desktop) - Dec 2025

- Map view.
- Manually tag people in photos.
- Album admins can now remove photos added by collaborators.
- Viewers and collaborators can see and copy public links.
- Free users can now create public links (device limit of 5).

## v1.2.31 (mobile) - Dec 2025

- Rituals
- Manually tag people
- Public links for everyone
- Shared albums pinning
- New favorite icon

## v1.2.28 (mobile) - Dec 2025

- Ability to pin people
- Hide people from memories
- Fresh QR code designs for links
- Performance improvements on Rewind
- Setting to disable Swipe to Select

## v1.7.16 (desktop) - Nov 2025

- Support Greek translations.
- Ability to terminate sessions on other devices.
- Quick access for search: Ctrl/Cmd + K.
- Search now shows settings.
- Ability to pin people.
- Ability to add a photo to an album from the photo viewer menu.

## v1.2.20 (mobile) - Nov 2025

- Move Add button to top in Albums, Contacts, and Location Tags screens for easier access
- Add full scrollable overview of people in the person edit page for easier merging of people
- Enable select all functionality in shared album date headers
- Update "Send Link" feature to share only link text instead of image
- Improve the scroll position behavior in the similar images page
- Fix OCR for HEIC files on Android
- Fix continuous loading in map view when no images have location data

## v1.2.18 (mobile) - Nov 2025

- **Jump to date** - See surrounding photos for any photo by selecting the jump to date option in the file's info pane.

- **Faster video editor** - Video editor was revamped to both drastically improve its speed when editing larger videos, and also improve the UX.

## v1.2.15 (mobile) - Oct 2025

- **OCR! Select text in photos** - Ente will detect if a photo or screenshot has an text and show you a button to enter text selection mode. Each line of text can be individually selected.
- **Swipe to select** - Use the swipe gesture to quickly select photos in your gallery. Works great with one handed use, without needing to lift up your finger!
- **New memories** - "Playful kids", "Winter adventures", "Neon nights", and more.
- Support for landscape layout in the app's main gallery.
- Show persons without any associated photos instead of filtering them out.
- Improve video aspect detection when shared from external apps.

## v1.7.15 (desktop) - Oct 2025

- Search functionality for album selection dialogs.
- Quicker way to create new albums.
- New layouts for public albums - grouped, continuous and trip.
- Custom domain support for public album sharing.
- Support Czech translations.

## v1.2.11 (mobile) - Oct 2025

- **Map view for your trips** - Choose between grouped, continuous, or trip (map-based) layouts when sharing albums.
- **Embed albums** - Embed your albums in your own website, blog, photography portfolio. Ente takes care of hosting!
- **Shared albums in widgets** - Home screen widgets now supports albums that have been shared with you.
- Quality of life wins - Add photos to albums from file viewer. Album level guest view option.
- Sharing improvements - Share public links using a QR code. Customize the ability to join albums from links you share.
