---
title: Android gallery integration
description: Use Ente as a system gallery on Android — pick photos from Ente in other apps and open camera thumbnails directly in Ente
---

# Android gallery integration

On Android, Ente integrates with the rest of the system so it can act like a regular gallery app. Other apps can pick photos and videos from your Ente library, and tapping a thumbnail in your camera app can open the photo directly in Ente's viewer.

> [!NOTE]
>
> These integrations are available on Android only.

## Pick photos and videos from Ente in other apps

When another app asks you to attach a photo or video — for example a messenger, an email client, or a social app — Ente shows up as one of the apps you can pick from.

**How it works:**

1. In the other app, tap the attach or add photo button
2. In the app chooser, select **Ente Photos**
3. Browse your Ente library and select one or more items
4. Tap **Use** (or the equivalent confirmation) to send them back to the original app

The picker opens directly in Ente without interrupting your normal session, and the original app receives the files you selected.

Ente registers as a handler for the standard Android picker intents, so it works with:

- The system photo picker (`PICK_IMAGES`)
- Apps that use `PICK` or `GET_CONTENT` to request media
- Both single-item and multi-item selection
- Image-only, video-only, or mixed media requests

## Open camera thumbnails directly in Ente

After taking a photo or video, many camera apps show a small thumbnail you can tap to review the shot. On supported camera apps, that thumbnail can open the photo directly in Ente's viewer.

**How it works:**

1. Take a photo or video in your camera app
2. Tap the thumbnail preview
3. If asked, select **Ente Photos** as the app to handle the review
4. The photo opens in Ente's viewer, where you can zoom, share, or delete it

The first time you tap a camera thumbnail, Android may ask which app should handle it. Choose Ente, and optionally set it as the default to skip the prompt next time.

> [!NOTE]
>
> Whether the thumbnail uses this integration depends entirely on your camera app, and not all camera apps support it. Notably, the default Pixel Camera and Samsung Camera apps do not send the review intent that Ente listens for, so tapping the thumbnail in those apps will not open the photo in Ente.

## Set Ente as your default gallery

Ente also registers as a gallery app, so on Android versions that let you choose a default gallery, Ente will appear in the list.

**On Android:**

1. Open device `Settings > Apps > Default apps`
2. Select **Gallery app** (the exact name varies by manufacturer)
3. Select **Ente Photos**

Once set as default, the camera thumbnail review and other gallery-style intents open in Ente without asking each time.
