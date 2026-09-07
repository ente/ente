---
title: Ente Photos - Changelog
description: Release notes of recent updates to Ente Photos mobile and desktop apps
---

# Changelog - Ente Photos

A short summary list of changes to the Ente Photos mobile and desktop apps. For a more descriptive list with screenshots and blog post links, see the [news](https://ente.com/news).

## v1.3.63 (mobile) - Sep 2026

- Added Library Sharing for automatically sharing current and future albums with family members.
- Added album descriptions, including on shared links. The “Ente” album filter now includes albums shared with you, and shared and received albums can be archived and restored.
- Added album slideshows, with controls for slide duration, photo order, and background style.
- On Android 11 and newer, deleted gallery photos can be recovered from [Device Trash](/photos/features/albums-and-organization/deleting#device-trash), including in gallery mode.
- Edited photos now retain key camera, date, and location details. JPEGs also retain their original quality when only rotated or flipped.
- Added music and audio controls to memories.
- Improved Search with country names in the app language and each country’s native languages, more accurate city matching, better result ordering, and faster performance on large libraries.
- Added a “You” uploader filter and fixed duplicate “Someone” entries in the Uploaded by filter.
- Backup Status now shows per-file progress, large multipart uploads are more reliable, and large uploads use less memory.
- Added Backup mode on iOS to keep Ente awake and dim the display during large backups.
- Made Free Up Space more reliable on Android.
- Improved performance across Map, timeline loading, and Smart Memories for large libraries. Also fixed week grouping and reduced memory spikes when Search and Gallery load very large libraries.
- Improved timeline scrolling performance for large galleries. (@r4khul)
- Improved processing of large on-device photo libraries on Android and reduced unnecessary home-gallery reloads.
- Fixed smart albums not automatically adding newly recognized people and improved the reliability of People changes after startup.
- Fixed downloading images without file extensions, newly captured photos failing to open on Android, and incorrectly rotated photos in Android home screen widgets.
- Fixed edited photos sometimes not syncing after their originals were fetched.
- Added five-second double-tap seeking for videos. (@r4khul)
- Added a menu option to control video playback speed. (@r4khul)
- Improved video-editing reliability, including exports with mismatched audio and video durations.
- Double tapping to zoom will zoom into the tapped area now rather than towards the center of the photo.
- Fixed multiple photos animating when closing the full-screen viewer. (@r4khul)
- Reordered the selection menu and updated the share icon. (@r4khul)
- Prevented page swiping while albums are selected. (@r4khul)
- Fixed the image-editor tune slider showing an active track at the neutral position. (@r4khul)
- Made the support email easier to find and copy when reporting an issue.
- Redesigned the referral screen.
- Improved handling of network disconnections in the payment screen. (@r4khul)
- Fixed clipping and error handling in the billing questions widget. (@r4khul)
- Improved coordination between foreground and background machine-learning processing and fixed cleanup of downloaded machine-learning models.

## v1.7.28 (desktop) - Sep 2026

- Improved the account deletion flow with clearer steps and a summary of the data that will be deleted.
- Added search when assigning names to people.
- Added support for adding photos to hidden albums.
- Add album description to gallery.
- Added a unified album details dialog for editing album names, descriptions, and cover photos.
- Improved the authentication UI for Ente Photos.
- Fixed CollectionMapDialog resetting after returning to the desktop app.
- Added search for photos without location information.
- Added functionality for sharing and applying referral codes.
- Revamped the All Albums UI with filters for quick links, received albums, and shared albums, also added an option to delete all empty albums.
- Use the shared rust ML code for indexing
- Enable CoreML on MacOS and WebGPU on Linux and Windows
- Fixed incorrect capture times for videos whose metadata stores creation time in UTC.

## v1.3.61 (mobile) - Aug 2026

- Fixed remote photos not loading on older self-hosted Ente servers.

## v1.3.60 (mobile) - Aug 2026

- Improved Cast device discovery on Android and added automatic Cast pairing on iOS.
- Improved handling of device out-of-storage errors.
- Made the favorite icon's stroke width consistent with the rest of the icon set.
- Fixed cropped panoramas sometimes opening blank (@agarwalrahul2702).
- Tapping an unconfigured home screen widget now opens its customization screen (@r4khul).
- Improved app lock screens and fixed password setup edge cases.
- Made panoramic photos open faster and improved panning, zooming, and motion controls.
- Fixed uploading photos to multiple albums at once (@nuit-dhiver).
- Fixed the no-op when a user tries to enable notifications from Settings → Notifications after denying permission.
- Improved photo viewer responsiveness while swiping through photos.
- Fixed picking SD card media from Ente in other Android apps (@wangwillian0).
- Added Traditional Chinese as a selectable language.
- Adjusted SVG icon sizing in the video editor bottom bar for better visibility (@r4khul).
- Added a mute button to the video player that remembers your preference. (@r4khul).
- Fix a black screen flash while loading videos on Android. This issue only affected video stream playback.

## v1.7.27 (desktop) - Jul 2026

- Added Close button to the download notification toast.
- Fix ML indexing and search getting stuck when the library contains very large images.
- Harden IPC boundary between the renderer and main process.
- Hide archived albums from the main Gallery album bar.
- Choose whether to import Google Photos favourites into Ente's favourite album.
- Fix the File Info panel closing after saving caption edits.
- Manage your family plan directly within the app.
- Upgrade to MUI v9.
- Redesigned stop-upload confirmation dialog.
- Redesigned upload completion dialog.
- Redesigned upload progress with completed, skipped, and failed file tracking.
- Review photo, video, and album counts before uploading.
- Search for people by name in the Add a person dialog.
- Fix shared file action menus to show only available actions.
- Show hidden album presence in the File Info panel.
- Import or skip partner-shared photos during Google Photos Takeout.

## v1.3.59 (mobile) - Jul 2026

- Comment and react to shared memories.
- Choose which photos and videos are included before creating a shared memory link.
- Redesigned the photo viewer and info sheet for a cleaner, more readable experience.
- Added support for saving contact names and profile photos.
- Removed indirect connections from Contacts.
- Redesigned the Family plan dashboard.
- Improved backup reliability and progress updates.
- Improved thumbnail and file download reliability.
- Reduced background processing while browsing photos for smoother swiping.
- Improved handling of photos and videos with incomplete metadata.
- Reduced cache buildup by clearing caches more effectively during ML indexing.
- Improved text detection and text selection reliability and performance.
- Fixed app bar titles being truncated when **Bold Text** is enabled.
- Fixed syncing edited iOS photos after local gallery changes.
- Fixed the **"No text detected"** message appearing unexpectedly when opening some photos.
- Fixed crashes when leaving screens, closing dialogs, or switching app state during background work.

## v1.3.58 (mobile) - Jul 2026

* Added support for casting albums to multiple screens and managing active cast sessions.
* Improved the account deletion flow with clearer impact details and confirmation.
* Simplified delete confirmations into a single prompt that remembers the last selected option.
* Clear cached images and videos from device storage during logout and automatic cache cleanup.
* Fixed backup folder selection when switching from the local gallery to an account.
* Reduced storage growth on iOS by deleting temporary photo copies after machine-learning processing.
* Show smaller detected people groups in Search when larger groups are unavailable.

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
