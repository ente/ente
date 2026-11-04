---
title: Collect wedding and event photos
description: Collect guest photos from a wedding or other event into one private album
---

# Collect wedding and event photos

Make one shared album and send guests a link that lets them upload. iCloud Shared Albums and Google Photos both do this. Apple says its Shared Albums aren't end-to-end encrypted, even with Advanced Data Protection on ([Apple](https://support.apple.com/en-us/108756)). Starting in iOS 27, iCloud guests can add photos on the web without an Apple Account ([Apple](https://support.apple.com/en-us/108314)). With Ente, create a collect link. Guests open it in their browser and upload, with no app and no account. Learn more in the [Sharing and collaboration FAQ](/photos/faq/sharing-and-collaboration#collect-without-account). The album stays end-to-end encrypted. You can add a password and an expiry date.

Whatever you use, set it up before the day and put the link or a QR code on the tables.

## Your options

**iCloud Shared Albums.** Easy for iPhone guests. Starting in iOS 27, guests can contribute on the web without an Apple Account, and Apple says Shared Albums add full-resolution sharing ([Apple](https://support.apple.com/en-us/108314)). On iOS 26 and earlier, Apple says shared albums upload a copy, and downloaded content may not contain the same information as the original. Ente's [Import from Apple Photos](/photos/migration/from-apple-photos/) guide describes those copies as reduced quality, with location data removed.

**Google Photos shared albums.** Works on any phone. Google lets you share with people even if they don't use the Google Photos app ([Google](https://support.google.com/photos/answer/6131416)).

**Wedding upload sites.** Some services are made just for this. Check how long they keep photos and whether you can download everything at full quality.

**Ente collect links.** A private album with an upload link. The rest of this page shows how.

## Setting it up in Ente

1. **Create an album** in the [Ente app](https://ente.com/app), for example "Emma & James, 12 Dec".
2. **Create a public link with uploads allowed.** In Ente this is a collect link. Share the album via link, then turn on **Allow adding photos** in the link settings. Learn more in [Public links](/photos/features/sharing-and-collaboration/public-links).
3. **Choose your settings.** You can set a password, an expiry date, and a device limit. Learn more in the [Sharing and collaboration FAQ](/photos/faq/sharing-and-collaboration#link-limits). For a wedding, an expiry about a month after the day works well.
4. **Make a QR code** for the tables and the invitation. The Ente mobile app can share a public link as a QR code (added in v1.2.11). Learn more in the [changelog](/photos/changelog). Look for it when you share the album's link.
5. **Optional: use your own domain,** such as `photos.yourwedding.com`. Ente supports custom domains for links, and the feature is available to everyone, including the free plan. Learn more in [Custom domains](/photos/features/sharing-and-collaboration/custom-domains/).

The link stays end-to-end encrypted. The key sits in the part of the link after the `#`, which never reaches Ente's servers, so anyone with the link can open the album. That's why the password matters. Learn more in the [Sharing and collaboration FAQ](/photos/faq/sharing-and-collaboration#public-link-encryption).

## What guests see

They open the link in a browser, enter the password if you set one, and can view the album and add photos from their phone. You won't see which guest added which photo. Uploads from people without an Ente account appear without attribution. Learn more in the [Sharing and collaboration FAQ](/photos/faq/sharing-and-collaboration#collect-link-attribution).

## After the wedding

- **Turn off uploads** or let the link expire.
- **Download everything** to your computer with the desktop app's export. Learn more in [Export](/photos/migration/export/).
- **Share a view-only link** with family for the final album.

## Before you send the link

### Do guests need to install Ente? {#collect-event-no-app}

No. They upload from the browser.

### Is there a limit on guests or uploads? {#collect-event-device-limit}

On the free plan, a public link works on up to 10 devices. A paid plan can create public links with no device limit. A link created on the free plan keeps its device limit until you set **Device limit** to **None**. Learn more in the [Sharing and collaboration FAQ](/photos/faq/sharing-and-collaboration#keep-public-link-after-device-limit) and [Sign up](/photos/getting-started/signup). For a big wedding, use a paid plan.

### Can I collect photos for other events? {#collect-event-other-events}

Yes. Birthdays, school trips, and reunions work the same way.
