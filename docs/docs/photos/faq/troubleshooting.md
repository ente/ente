---
title: Troubleshooting FAQ
description: Solutions to common issues with uploading, syncing, and using Ente Photos
---

# Troubleshooting

This page helps you solve common issues with Ente Photos. Jump to the section that matches your problem:

- [Upload Issues](#upload-issues)
- [Mobile Backup Issues](#mobile-backup-issues)
- [Desktop App Issues](#desktop-app-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [Performance Issues](#performance-issues)
- [Getting Help](#getting-help)

## Upload Issues

### Why are my large videos failing to upload? {#video-upload-failures}

If large video files (300-700+ MB) are failing to upload or getting stuck, try these solutions:

**Solution 1: Disable machine learning temporarily**

ML processing can cause crashes during large video uploads, especially on mobile devices:

**On mobile:**

Open `Settings > Machine learning`, disable "Face recognition" and "Magic search", try uploading the videos again, then re-enable ML after upload completes.

**On desktop:**

Open `Settings > Preferences > Machine learning`, disable ML features, upload the videos, then re-enable ML afterwards.

**Solution 2: Disable video streaming (iOS)**

Video streaming can cause crashes when combined with ML on some devices:

**On iOS:**

Open `Settings`, disable "Video streaming" or "Enable video playback", try uploading again, then re-enable after upload completes.

Learn more about [Video Streaming](/photos/features/utilities/video-streaming).

**Solution 3: Upload from desktop instead of mobile**

Desktop apps handle large video uploads more reliably:

- More memory available
- Faster, more stable network connections
- Better handling of large files

**Solution 4: Split large videos**

If a specific video keeps failing:

- The file might be corrupted or too large
- Try uploading other files first to isolate the problem
- Consider compressing the video if it's extremely large
- Check if the video is under the 10 GB file size limit

**If uploads are still failing:**

1. Check your network connection is stable
2. Make sure you're not running out of storage quota
3. Try uploading via WiFi instead of mobile data
4. Contact [support@ente.com](mailto:support@ente.com) with debug logs (see [How to share logs](#sharing-logs))

### Why does the app crash when watching videos or using ML? {#app-crashes-ml-video}

If the Ente app crashes when watching videos or when machine learning is enabled, especially on iOS or older devices, this is a known issue.

**Quick fix: Disable ML and video streaming**

**On mobile:**

Open `Settings`, disable "Machine learning" and "Video streaming" (or "Enable video playback"), then restart the app.

Learn more about [Video Streaming](/photos/features/utilities/video-streaming#troubleshooting).

**Why this happens:**

The combination of ML processing and video streaming can exceed available device memory on:

- Older iPhone/iPad models
- Devices with limited RAM
- When processing very large libraries

**If you want to use ML:**

1. Enable ML on desktop first (more powerful hardware)
2. Let indexing complete on desktop
3. Indexes sync to your mobile device
4. You can then use search on mobile without enabling ML there
5. Keep video streaming disabled on mobile

**Reporting crashes:**

If you continue experiencing crashes, go to `Settings > Support > Report a Bug` (this attaches crash logs automatically). Mention your device model and iOS/Android version, and describe when the crashes occur.

### Why aren't my photos uploading? {#upload-failures}

If your photos or videos aren't uploading to Ente, try these troubleshooting steps:

**Check network connectivity:**

- Verify your internet connection is stable and working
- Try switching between WiFi and mobile data
- If using a VPN, try disabling it or switching to a different provider
- Check if your firewall or network security settings are blocking Ente

**Check storage quota:**

- Check your storage quota in the app
- If you've exceeded your limit, [upgrade your plan](/photos/faq/storage-and-plans#what-plans-does-ente-offer) or delete unwanted photos
- Items in trash count towards your quota - empty trash to free up space

**Check file compatibility:**

- Ente supports all `image/*` and `video/*` file types
- RAW format support is currently limited
- Files larger than 10 GB cannot be uploaded
- If a valid file isn't uploading, contact [support@ente.com](mailto:support@ente.com)

### Why does upload show "Waiting to upload"? {#waiting-to-upload}

This usually indicates a network connectivity issue:

1. Check your internet connection is active
2. Try switching networks (WiFi to mobile data or vice versa)
3. If using VPN, try disabling it temporarily
4. Check if your firewall is blocking Ente's servers
5. On desktop/web, try disabling "Faster uploads" in `Settings > Preferences > Advanced`

### Why are uploads failing on desktop or web? {#faster-uploads}

We use a Cloudflare proxy to speed up uploads ([blog post](https://ente.com/blog/tech/making-uploads-faster/)). However, in some network configurations (depending on your ISP) this might prevent uploads from going through.

**Solution:**

Open `Settings > Preferences > Advanced` (desktop/web), disable the "Faster uploads" option, and try uploading again.

If uploads still fail after disabling this option, check your network connectivity and firewall settings.

### How do I retry failed file downloads? {#retry-failed-downloads}

If some files fail to download from your Ente library on web or desktop, you can easily retry them:

**Solution:**

When files fail to download, a modal dialog appears showing the failed downloads. Click the **retry icon** in the modal to attempt downloading the failed files again.

### Why can't the app detect certain file types? {#file-type-detection}

The desktop/web app tries to detect if a particular file is a video or image. If the detection fails, the app skips the upload.

**Solution:** Contact [support@ente.com](mailto:support@ente.com) if you find that a valid image or video file was not detected and uploaded. Include:

- The file extension (e.g., .jpg, .mp4)
- The file's MIME type if you know it
- A sample file if possible

## Mobile Backup Issues

### Why isn't background sync working on my phone? {#background-sync-issues}

**On Android:**

1. **Disable battery optimization for Ente:**
    - Open device `Settings > Apps > Ente > Battery`
    - Select "Unrestricted" or "Don't optimize"

2. **Check storage permissions:**
    - Open device `Settings > Apps > Ente > Permissions`
    - Ensure "Photos and videos" or "Files and media" is allowed

3. **Verify backed up folders:**
    - Open Ente app, go to `Settings > Backup > Backed up folders`
    - Ensure the correct albums/folders are selected

**On iOS:**

1. **Check Background App Refresh:**
    - Open device `Settings > Ente > Background App Refresh`
    - Ensure it's enabled

2. **Keep app in foreground for initial upload:**
    - For large libraries, keep Ente open during the first upload
    - Once initial upload completes, background sync will work automatically

Learn more in [Backup and Sync FAQ](/photos/faq/backup-and-sync#background-sync).

### Why can't Ente access my photos? {#photo-access-permissions}

**On iOS:**

Open device `Settings > Ente > Photos` and select "Full Access" (not "Selected Photos").

**On Android:**

Open device `Settings > Apps > Ente > Permissions`, enable "Photos and videos" or "Files and media", and ensure permission is set to "Allow" (not "Ask every time").

If you've granted permission but Ente still can't access photos, try:

- Restarting the app
- Revoking and re-granting the permission
- Reinstalling the app (your backed-up photos are safe in the cloud)

### Why is the app looping saying it is preserving one memory when all memories seem to be backed up? {#app-looping-preserving-one-memory}

If the app shows it is preserving one photo or memory but never completes, the file is likely stuck in a retry loop.

Share debug logs with [support@ente.com](mailto:support@ente.com) so we can identify the specific file. Open `Settings > Help & Support > Export logs` and attach to email.

A common cause on iOS is that "Optimize iPhone Storage" is enabled and the original file has not been downloaded from iCloud to your device.

To fix this:

1. Open your iOS Photos app and find the stuck photo or video.
2. Open it and let it fully load (or play, if it is a Live Photo or video). This forces iOS to download the original from iCloud.
3. Once fully loaded, open Ente and keep it in the foreground on WiFi. The upload should complete shortly.

If the photo won't load in your Photos app either, the file may be corrupted or inaccessible on iCloud's end.

## Desktop App Issues

### Why does my desktop app crash during large uploads? {#desktop-large-uploads}

If you're uploading a very large library (multiple terabytes) and the desktop app seems to freeze or restart during upload, especially when uploading large videos, this is related to Electron's 4GB RAM usage limit.

**Workarounds:**

1. **Separate large videos**: Put problematic large videos in a separate folder, complete the rest of your upload, then upload that folder separately

2. **Use drag and drop**: Instead of using watch folders or uploading a zip, drag and drop the folder directly into the app. This works better because the app has direct access to files via browser APIs

3. **Upload in batches**: Split your library into smaller chunks and upload them separately

The app will detect and skip already uploaded items, so you can safely drag and drop the same folder multiple times.

> Technical note: The underlying issue is Electron's [4GB RAM usage limit](https://www.electronjs.org/blog/v8-memory-cage). We stream large videos to avoid reading them all at once, but in some cases even streaming exceeds the limit.

### Why is my desktop app stuck on a black screen? {#desktop-black-screen}

A black, never-loading window usually means the app can't access its local database. A clean reinstall fixes it in most cases.

**On macOS:**

1. Open Finder > Applications, right-click Ente Photos and select "Move to Bin".
2. Open Finder > Home, then press `Cmd + Shift + Period` to reveal hidden folders.
3. Go to `Library > Application Support` and delete the `ente` folder.
4. Download a fresh copy from [our website](https://ente.com/download/desktop) and install.

**On Windows:**

1. Uninstall Ente Photos from Settings > Apps.
2. Delete `%APPDATA%\ente\`.
3. Reinstall from [our website](https://ente.com/download/desktop).

**On Linux:**

1. Remove the app (or AppImage).
2. Delete `~/.config/ente/`.
3. Reinstall from [our website](https://ente.com/download/desktop).

Your photos are safe in the cloud; uninstalling and clearing local app data only removes the local cache and the app's database. If the issue persists after a clean reinstall, share your logs with [support@ente.com](mailto:support@ente.com) (see [How do I share debug logs?](#sharing-logs)).

### Why are my photo thumbnails missing or incorrect? {#thumbnails}

When photos are uploaded on the web app, the most common cause of thumbnails not generating properly is browser security settings blocking canvas access.

**Firefox users:** If you have "block canvas fingerprinting" enabled (`privacy.resistFingerprinting` set to true in `about:config`), Firefox will prevent the app from generating thumbnails.

**Brave users:** Brave Shields can block canvas access and prevent the app from generating thumbnails. To fix this, disable canvas fingerprinting for Ente's domain, or turn off Brave Shields for Ente's domain, or whitelist Ente in any browser extension that blocks canvas access.

**Tor Browser users:** When the upload error appears, click the photo icon on the left side of the address bar and choose **Allow** so Ente can generate thumbnails.

> [!IMPORTANT]
>
> Once thumbnails are incorrectly generated or missing, they cannot be regenerated. You'll need to:
>
> 1. Delete the affected files from Ente
> 2. Fix the browser settings
> 3. Re-upload the files

Ente will automatically skip files that have already been uploaded, so you can drag and drop the original folder again after removing the files without thumbnails.

If the browser settings cannot be changed, we recommend uploading files through the desktop app.

### Why does desktop ML show "Indexing: Error" on Windows? {#windows-ml-indexing-error-13}

If the desktop app shows `Indexing: Error` in `Settings > Preferences > Machine learning`, this is usually caused by Windows roaming profiles preventing access to the ML model files in `%APPDATA%\ente\models\`.

If you check the logs, you might also see `system error number 13` during ML indexing.

**Solution:**

Switch to a local profile, or exclude `%APPDATA%\ente\models\` from roaming sync. Contact your IT administrator if you're on a domain-joined computer.

After making changes, quit the app completely, log out, and log back in to restart the ML pipeline.

### Why is ML stuck on Windows (or models never download)? {#windows-ml-stuck}

If ML does not progress, `%APPDATA%\\ente\\models\\` is never created, or logs show `ERR_DLOPEN_FAILED` for `onnxruntime_binding.node`, your Microsoft VC++ runtime is likely too old for the ONNX runtime bundled with Ente.

**Root cause:**

Recent ONNX Runtime builds on Windows require Microsoft VC++ runtime version `14.40+`. On some Windows 11 systems, an older VC++ runtime can still be installed.

**Check your installed VC++ runtime version:**

```powershell
powershell -Command "(Get-Item 'C:\Windows\System32\vcruntime140.dll').VersionInfo.FileVersion"
```

**Fix:**

Install/update the Microsoft Visual C++ Redistributable (x64):

- Direct download: [vc_redist.x64.exe](https://aka.ms/vc14/vc_redist.x64.exe)
- Reference: [Latest supported Visual C++ Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)

After updating, fully quit and reopen Ente, then re-enable ML. You should see model download entries in logs (for example, `Downloading ML model from ...`) and indexing should continue normally.

### Why aren't my watch folders syncing? {#watch-folders-troubleshooting}

If watch folders aren't uploading new files automatically:

1. **Check the watch folders list:**
    - Click "Watch folders" in the sidebar
    - Verify the correct folders are being watched

2. **Check upload status:**
    - Look for the sync status indicator in the bottom right
    - Expand it to see any errors

3. **Restart the desktop app**

4. **If the issue persists:**
    - Remove the watch folder
    - Re-add it
    - Ente will skip already uploaded files

Learn more in [Backup and Sync FAQ](/photos/faq/backup-and-sync#watch-folders).

### Can I upload from a network drive (NAS)? {#nas}

**Not recommended.** While the desktop app may work with network drives in some cases, network storage often has:

- Flaky file system emulation causing upload issues
- Poor performance during large uploads
- Unreliable file change notifications (critical for watch folders)

**Recommended approach:** Temporarily copy files to local storage before uploading rather than uploading directly from network drives.

**Exception:** Exporting to network drives generally works better than importing. If exporting to a UNC path (Windows network path like `\\server\share`), map it to a network drive letter first.

### Can I safely close the desktop app while it's uploading? {#close-during-upload}

Yes! The desktop app supports resumable uploads. You can close the app at any time, and when you open it again, it will automatically resume from where it left off. Your progress is saved and no files will be uploaded twice.

## Platform-Specific Issues

### Why is my iOS app stuck on "Please wait..." when I purchase a subscription? {#ios-appstore-subscription}

If you purchased a subscription through the iOS App Store but the app shows "Please wait..." indefinitely or doesn't reflect your upgraded storage, this is a known issue with App Store subscription processing.

**Recommended solution:**

1. Request a refund from Apple for the App Store purchase
2. Purchase your subscription directly from [photos.ente.com](https://photos.ente.com) instead

**How to request a refund from Apple:**

1. Go to [reportaproblem.apple.com](https://reportaproblem.apple.com)
2. Sign in with your Apple ID
3. Find the Ente subscription purchase
4. Select "Request a refund"
5. Choose "It's not working as expected" as the reason

**Alternative workaround to try first:**

1. Force close the Ente app completely
2. Update to the latest version from the App Store
3. Reopen the app and wait a few minutes
4. If still stuck, proceed with the refund and web purchase

**Why purchase from photos.ente.com?**

- More reliable payment processing
- Can apply discount codes (not possible through App Store)
- Avoid App Store's 30% fee
- Better refund and support options

If you continue experiencing issues after purchasing from the web, contact [support@ente.com](mailto:support@ente.com).

### Why is my Android app stuck on the splash screen? {#android-splash-freeze}

If the Ente app freezes at the splash screen for 15+ seconds on Android, try these solutions in order:

**Solution 1: Clear app cache**

Open device `Settings > Apps > Ente > Storage` and tap "Clear cache" (NOT "Clear data" - this preserves your login), then reopen the app.

**Solution 2: Log out and log back in**

1. If you can access Settings in the app, log out
2. Log back in with your email and password
3. This refreshes the app state

**Solution 3: Reinstall the app**

1. Uninstall Ente from your device
2. Reinstall from your preferred source (Play Store, F-Droid, GitHub)
3. Log back in
4. Your backed-up photos are safe in the cloud

> [!NOTE]
>
> This is a known issue being investigated by our team. If none of these solutions work, please contact [support@ente.com](mailto:support@ente.com) with your device model and Android version.

### Why does Android ask me to confirm every photo when I delete from Ente? {#android-media-management-delete}

When Ente deletes a photo or video that also exists in your device gallery, Android shows a system confirmation dialog for each item. This is an Android security measure for third-party apps. It is especially noticeable when using **Free up space**, where you may have to confirm a large number of files one by one.

To stop these repeated prompts, grant Ente the **media management** special access:

**On Android:**

Open device `Settings > Apps > Special app access > Media management apps > Ente Photos` and enable "Allow app to manage media".

Once granted, Ente can delete media that it manages without asking for confirmation each time.

### Why is the Linux desktop app still showing the old icon after updating? {#linux-icon-update}

You might need to update the icon cache of your Linux desktop environment.

**Solutions:**

1. Restart your computer (or logout and login again)
2. Refresh the icon cache manually (steps vary by distro):
    - Example: `xdg-desktop-menu forceupdate`

**AppImage users:** If you're using an AppImage and not seeing the icon, you'll need to enable AppImage desktop integration (see below).

### How do I enable AppImage desktop integration on Linux? {#appimage-integration}

AppImages are not fully standalone and require additional steps to enable full "desktop integration":

- Showing the app icon
- Surfacing the app in the list of installed apps
- Handling redirection after passkey verification

**Solution:**

1. Download [appimaged](https://github.com/probonopd/go-appimage/releases) AppImage
2. Run the appimaged AppImage
3. Download the Ente Photos AppImage into your `~/Downloads` folder
4. appimaged will automatically pick it up and integrate it

See the [AppImage documentation](https://docs.appimage.org/user-guide/run-appimages.html#integrating-appimages-into-the-desktop) for all integration methods.

### Why doesn't the AppImage work on my ARM64 Linux machine? {#appimage-arm64}

If the AppImage doesn't do anything when you run it on ARM64 Linux, you need to create a symlink:

```sh
sudo ln -s /usr/lib/aarch64-linux-gnu/libz.so{.1,}
```

This creates `libz.so` as an alias for `libz.so.1`. The exact path might differ on your machine.

### Why does AppImage say it requires FUSE? {#appimage-fuse}

**Solution:** Install libfuse2. For example, on Ubuntu:

```sh
sudo apt install libfuse2
```

See the [AppImage FUSE documentation](https://docs.appimage.org/user-guide/troubleshooting/fuse.html#the-appimage-tells-me-it-needs-fuse-to-run) for more details.

### Why do I get a "SUID sandbox helper" error on Linux? {#suid-sandbox-error}

If you run the AppImage from the command line and see:

> The SUID sandbox helper binary was found, but is not configured correctly.

**Solution:** Either:

1. Double-click the AppImage in your file browser instead of running from CLI, OR
2. Run it with the `--no-sandbox` flag:
    ```sh
    ./ente.AppImage --no-sandbox
    ```

### Why won't the Windows desktop app start (JavaScript error)? {#windows-javascript-error}

If you see "A JavaScript error occurred in the main process - The specified module could not be found" when starting the app on Windows, you need to install the Microsoft VC++ runtime.

**Solution:** Install the [Microsoft VC++ redistributable runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#latest-microsoft-visual-c-redistributable-version).

### Why can't I log in to photos.ente.com on my mobile browser? {#web-login-mobile}

If photos.ente.com loads infinitely or gets stuck when you try to log in on a mobile browser (Safari on iPhone, Chrome on Android), this is a known limitation.

**Why this happens:**

Mobile browsers cannot handle the computationally intensive password derivation process that Ente uses for security. The login process requires significant processing power and memory that mobile browsers don't provide.

**Solutions:**

1. **Use the native mobile app instead** (recommended):
    - Install Ente Photos from the [App Store (iOS)](https://apps.apple.com/app/id1542026904) or [Play Store (Android)](https://play.google.com/store/apps/details?id=io.ente.photos)
    - Mobile apps are optimized for phones and tablets
    - Full feature support including machine learning

2. **Use a desktop or laptop computer**:
    - photos.ente.com works on desktop browsers (Chrome, Firefox, Safari, Edge)
    - Or install the [desktop app](https://ente.com/download/desktop)

**Feature differences:**

Mobile browsers on photos.ente.com are not supported. Use native apps for the best experience:

- ✅ Mobile apps: Full features including ML, search, video streaming
- ✅ Desktop/laptop web: Most features (no ML)
- ❌ Mobile web browsers: Not supported

### Why can I see my photos in the app but not in the browser? {#photos-visible-app-not-browser}

If photos appear in the mobile or desktop app but not on photos.ente.com, try logging out and logging back in on the browser. This clears any stale session data and refreshes your library view.

You can also try opening photos.ente.com in an incognito or private window to rule out browser caching issues.

### How do I identify which files failed to upload? {#identify-failed-uploads}

**On desktop:** Check the sections within the upload progress bar for:

- "Failed Uploads"
- "Ignored Uploads"
- "Unsuccessful Uploads"

Click on each section to see the specific files and error messages.

**On mobile:** Open `Settings > Backup` to see the backup status and any errors.

### Why aren't videos playing on web? {#content-blocker-videos}

If videos aren't playing on photos.ente.com, browser content blockers or ad blockers may be blocking video playback.

**Solution:**

Disable your content blocker or add `photos.ente.com` to your allowlist. Wait 15-20 seconds for changes to take effect before trying again.

**Known issue with AdGuard:** AdGuard's basic filter blocks videos in Ente when using AdGuard Mini on Safari. This has been [reported to AdGuard filter developers](https://github.com/AdguardTeam/AdguardFilters/issues/216424).

## Performance Issues

### Why is the app slow to load my photos? {#app-slow-loading}

**Check your internet connection:**

- Slow loading usually indicates network issues
- Try switching between WiFi and mobile data
- VPNs can sometimes slow down loading

**On mobile:**

- Ensure background sync is enabled (see [Background sync troubleshooting](#background-sync-not-working))
- Check if battery optimization is restricting the app

**On desktop:**

- Large libraries may take time to load initially
- Once loaded, the app caches data for faster access

### Why is face recognition or magic search taking so long? {#ml-slow}

Machine learning features (face recognition and magic search) require downloading and indexing your entire library on your device. This can take time depending on:

- Library size
- Device processing power
- Network speed

**Tips for faster indexing:**

- Enable ML on desktop first (faster processor)
- Use WiFi for initial indexing
- Keep the app open and in the foreground
- If stuck or slow, keep the app open on the 'Machine Learning' page
- Once indexed on one device, the indexes sync to other devices

Learn more in [Search and Discovery FAQ](/photos/faq/search-and-discovery#ml-offline).

### What are the minimum device requirements for Ente apps? {#minimum-requirements}

Ente needs at least **2 GB of RAM** to run reliably. On devices below that, including most Android Go phones, basic operations like backup, export, and indexing may crash or stall.

If you're running into repeated crashes on a low-RAM device:

- Disable Machine learning under `Settings > Machine learning`.
- Disable Video streaming if enabled.
- Use the desktop or web app for heavier tasks like initial backup or export.

### How can I clear the cache from the Ente app? {#clear-cache}

If you notice storage usage growing or temporary files not clearing automatically, you can safely remove the cache:

**Clear the cache manually:**

1. Open Ente Photos.
2. Go to `Settings → Backup → Free up space → Manage device cache`.
3. Tap **Clear cache**.

This deletes temporary files such as thumbnails and preloaded images that can be regenerated when needed.

**Automatic cache cleanup:**

- Ente clears upload-related temporary files and pending syncs every 6 hours.
- If the cache or sync state still hasn't cleared after 6 hours, force-close (kill) and reopen Ente Photos to trigger the manual cleanup.

## Getting Help

### How do I share debug logs with support? {#sharing-logs}

If you need to contact support, debug logs help us diagnose issues faster.

> [!NOTE]
>
> Debug logs contain potentially sensitive information like file names. Feel free to not share them if you have privacy concerns. We'll try to diagnose without logs, though they make the process faster.

**On mobile:**

Open `Settings > Help & Support > Export logs`. This will download logs which you can then email to support@ente.com.

**On desktop:**

Open `Settings > Support > Help` to view logs location, then go back to `Settings > Support` to open your email client. Attach the logs and describe your issue.

**Desktop log locations:**

- macOS: `~/Library/Logs/ente/ente.log`
- Linux: `~/.config/ente/logs/ente.log`
- Windows: `%USERPROFILE%\AppData\Roaming\ente\logs\ente.log`

**On web:**

Open `Settings > Support > Help` to download logs, then email the downloaded logs to [support@ente.com](mailto:support@ente.com).

**Email manually:** If the automatic email doesn't work, send logs directly to [support@ente.com](mailto:support@ente.com) with:

- Your platform (iOS, Android, Desktop, Web)
- Description of the issue
- Steps you've already tried
- Any error messages you see

### Where can I get help? {#get-help}

1. **Check the FAQ sections** for answers to common questions
2. **Join our [Discord community](https://ente.com/discord)** for community support
3. **Email us at [support@ente.com](mailto:support@ente.com)** with details about your issue
4. **Report bugs on [GitHub](https://github.com/ente/ente/issues)** if you've found a technical issue

For security vulnerabilities, please email [security@ente.com](mailto:security@ente.com) directly.
