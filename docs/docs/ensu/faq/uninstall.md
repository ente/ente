---
title: Uninstall Ensu
description: >
    How to completely remove Ensu and its downloaded models from your device
---

# Uninstall Ensu

Uninstalling the Ensu app from your device removes the application itself, but depending on your platform, the downloaded model files and local data may remain. This page explains how to remove the downloaded models and local data.

## macOS

1. Quit Ensu if it is running.
2. Move **Ensu.app** from your Applications folder (or wherever you placed it) to the Trash.
3. Delete "~/Library/Application Support/io.ente.ensu". It contains the downloaded models, local chat database, attachments, and logs.

## Windows

1. Uninstall Ensu using **Settings > Apps** (or **Add or Remove Programs**).
2. Delete "%APPDATA%\io.ente.ensu". You can paste this path into the File Explorer address bar. It contains the downloaded models, chat database, and logs.

## Linux

1. Remove the Ensu application (e.g. delete the AppImage or uninstall the package).
2. Delete "~/.local/share/io.ente.ensu" (or "$XDG_DATA_HOME/io.ente.ensu" if set). It contains the downloaded models, chat database, and logs.

## iOS

Deleting the Ensu app from your Home Screen or through **Settings > General > iPhone Storage** removes everything, including the downloaded model and all local chat data. No additional cleanup is needed.

## Android

Uninstalling Ensu through your device settings or the Play Store removes the app and its internal data (chat database, preferences). The downloaded model files are stored in the app's external files directory and are also removed on uninstall.

If you want to manually free space _without_ uninstalling, you can clear the app's storage via **Settings > Apps > Ensu > Storage > Clear data**.

## Web

The web version of Ensu stores the model in the browser's Origin Private File System (OPFS). To reclaim this space:

1. Open your browser's settings.
2. Find the site data for **ensu.ente.com**.
3. Delete it.

In Chrome, this is under **Settings > Privacy and security > Site settings > View permissions and data stored across sites**. Search for `ensu.ente.com` and click **Delete data**.
