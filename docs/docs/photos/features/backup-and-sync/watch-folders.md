---
title: Watch folder
description: Automatic syncing of selected folders using the Ente Photos desktop app
---

# Watch folders

The Ente desktop app allows you to "watch" a folder on your computer for new files and deletions, creating a one-way background sync from folders on your computer to Ente albums. This is intended to automate your photo management and backup.

By using the "Watch folders" option in the sidebar, you can tell the desktop app which are the folders that you want to watch for new files and deletions. The app will then automatically upload new files added to these folders to the corresponding ente album (it will also upload them initially). And if a file is deleted locally, then the corresponding Ente file will also be automatically moved to uncategorized.

Paired with the option to run Ente automatically when your computer starts, this allows you to automate backups to ente's cloud.

### Steps

1. Press the **Watch folders** button in the sidebar. This will open up a dialog where you can add and remove watched folders.

2. To start watching a folder, press the **Add folder** button and select the folder on your system that you want to watch for new files and deletions. You can also drag and drop the folder here.

3. If the folder has nesting, you will see two options - **A single album** and **Separate albums**. This work similarly to the [options you see when you drag and drop a folder with nested folders](/photos/features/albums-and-organization/albums#preserving-folder-structure).

4. After choosing any of the above options, the folder will be initially synced to Ente's cloud and monitored for new files and deletions. You can now close the dialog and the sync will continue in background.

5. When the app is syncing in the background it'll show a small progress status in the bottom right. You can expand it to see more details if needed.

6. You can stop watching any folder by clicking on the three dots next to the watch folder entry, and then selecting **Stop watching**.

> Note: In case you start a new upload while an existing sync is in progress, the sync will be paused then and resumed when your upload is done.

Some more details about the feature are in our [blog post](https://ente.com/blog/watch-folders) announcing it.

## 2-way sync

Note that a two way sync is not currently supported. Attempting to export data to the same folder that is also being watched by the Ente app will result in undefined behaviour (e.g. duplicate files, export stalling etc).

## Related FAQs

- [What are watch folders?](/photos/faq/backup-and-sync#what-are-watch-folders)
- [How do I set up watch folders?](/photos/faq/backup-and-sync#set-up-watch-folders)
- [Can I watch multiple folders at once?](/photos/faq/backup-and-sync#watch-multiple-folders)
- [What happens if I delete a file from my watched folder?](/photos/faq/backup-and-sync#delete-from-watched-folder)
- [Why are my watch folders not syncing?](/photos/faq/backup-and-sync#watch-folders-not-syncing)
- [Can I watch folders on a network drive (NAS)?](/photos/faq/backup-and-sync#watch-nas)
- [Can watch folders preserve my nested folder structure?](/photos/faq/backup-and-sync#watch-nested-structure)
- [Can I do a 2-way sync with watch folders?](/photos/faq/advanced-features#export-two-way-sync)
