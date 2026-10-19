---
title: Import from local hard disk
description: Migrating to Ente Photos by importing data from your local hard disk
---

# Upload photos from your computer

Use the Ente desktop app to upload photos and videos from your computer or an external drive.

## Start an upload

1. Download and install the [Ente desktop app](https://ente.com/download/desktop), then sign in.
2. Click **Upload** and select **Files** or **Folder**. You can also drag and drop files or folders into the app window.

    ![Choose files or a folder from the Ente upload dialog](from-google-photos/google-takeout.png)

3. Choose an album. For folders, choose one album or a separate album for each folder.
4. Review the media and album counts, then click **Start upload**.

    ![Ready to upload with media and album counts](from-local-hard-disk/upload-ready.webp)

> [!NOTE]
>
> A single file may skip this review. Google Takeout imports show it; [Watch Folder](/photos/features/backup-and-sync/watch-folders) uploads do not.

## Understanding folder structure options

![Multiple folders detected — single album or separate albums](https://docs-assets.ente.com/screenshots/desktop-import-albums-choice.png){width=720px}

When you upload a folder, Ente will ask how you want to organize your photos:

**Single album**: Creates one Ente album containing all files from all subfolders. Best for a collection where folder structure doesn't matter.

**Separate albums**: Creates a separate Ente album for each subfolder. Best for preserving your existing organization (e.g., "2023/Summer", "2023/Winter" become separate albums).

Learn more about [folder structure handling](/photos/features/albums-and-organization/albums#preserving-folder-structure).

## Follow upload progress

Uploads start as a compact card in the bottom-right corner. Expand it for details.

![Minimized upload progress card in the bottom-right corner](from-local-hard-disk/upload-minimized-progress.webp)

The expanded view opens on **In progress**.

![Files currently being uploaded](from-local-hard-disk/upload-in-progress.webp)

Use the four sections to review the upload:

- **In progress**: Active files.
- **Completed**: Successfully uploaded files.
- **Skipped**: Files not uploaded, grouped by reason.
- **Failed**: Unsuccessful uploads.

### In-progress and completed files

Open **Completed** to see uploaded files.

![Files that completed uploading](from-local-hard-disk/upload-completed-tab.webp)

### Skipped files

**Skipped** groups files by reasons such as **Already on Ente** and **Hidden file**.

![Skipped files grouped by reason](from-local-hard-disk/upload-skipped-tab.webp)

Select a reason to filter the list.

![A hidden file shown under the skipped reason filter](from-local-hard-disk/upload-skipped-hidden-reason.webp)

Skipped files are not retryable failures.

## Stop and resume an upload

Close an active upload and confirm **Stop uploads**. Completed files remain in Ente and will be skipped if selected again.

![Confirmation shown before stopping an upload](from-local-hard-disk/stop-upload-confirmation.webp)

After stopping, open a section to review its files.

![Upload details shown after stopping an upload](from-local-hard-disk/stopped-upload-details.webp)

To continue, select the same files or folders again. Ente uploads only the remaining items.

## Review a completed upload

When the upload finishes, click **Review items** to inspect skipped or failed files.

![Completed upload summary with skipped and failed items](from-local-hard-disk/upload-completion-with-failures.webp)

Open **Failed**, then click **Retry failed uploads** to try them again.

![Failed upload details with the retry button](from-local-hard-disk/failed-upload-review.webp)

## Tips for large libraries

- **Start small**: Try uploading a small folder first to familiarize yourself with the process
- **Check your storage**: Ensure you have enough space in your Ente plan before starting large uploads
- **Stable connection**: Use a reliable internet connection, preferably wired Ethernet for very large libraries
- **Keep app open**: While the initial upload of multi-TB libraries may take hours or even days, the app will resume if interrupted
- **Resumable uploads**: If uploads get interrupted, select or drag and drop the same folders again. Ente skips already uploaded files and continues with the rest.

## Alternative: Watch Folders

Instead of a one-time upload, you can use [watch folders](/photos/features/backup-and-sync/watch-folders) to automatically sync folders on an ongoing basis. This is perfect for:

- Photo libraries you actively update
- Automated backup workflows
- Keeping Ente in sync with your local photo organization

## Troubleshooting

**Upload is slow**: Try disabling "Faster uploads" in `Settings > Preferences > Advanced` if you're having issues

**Large videos causing problems**: See the [large uploads troubleshooting guide](/photos/faq/troubleshooting#large-uploads)

**Files being skipped or failing**: Review the reason in **Upload details**, then check [Troubleshooting](/photos/faq/troubleshooting) for common solutions.

If you run into any issues during uploads, please reach out to [support@ente.com](mailto:support@ente.com) and we will be happy to help you!
