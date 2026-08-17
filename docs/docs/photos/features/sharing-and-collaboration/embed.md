---
title: Embed albums
description: Embed your Ente Photos albums on your own website
---

# Embed albums

The embed feature allows you to display your Ente photo albums directly on your own website or blog using an iframe.

For example, if you have a public Ente album that you'd like to showcase on your website, you can embed it just like you would embed a YouTube video. Visitors can browse through your photos without leaving your site.

## Availability

The embed feature works with any public album link. Since creating public albums requires an active Ente subscription for abuse prevention, embedding also requires a subscription.

## How to embed

### Easy method - Using the app

The simplest way to get the embed code is directly from Ente, whether you're on web or mobile:

**On web:**

1. Open the album in [photos.ente.com](https://photos.ente.com)
2. Open the album's sharing settings
3. Create a public link (if you haven't already)
4. Open the link settings ("Manage link")
5. Click the "Copy embed HTML" button

**On mobile:**

1. Open the album in the Ente app
2. Tap the share icon
3. Create a public link (if you haven't already)
4. Tap "Manage link"
5. Tap "Copy embed HTML"

This copies ready-to-use iframe code that you can paste directly into your website's HTML.

### Manual method

Alternatively, you can create the embed code manually:

#### Step 1 - Create a public link

First, you need to create a public link for the album you want to embed:

1. Open the album in Ente (web or mobile app)
2. Open the album's sharing settings
3. Create a public link
4. Copy the link (it will look like `https://albums.ente.com/?t=...#...`)

#### Step 2 - Add iframe to your website

Add an iframe to your HTML with the public link as the source, replacing `albums.ente.com` with `embed.ente.com`:

```html
<iframe
    src="https://embed.ente.com/?t=...#..."
    width="800"
    height="600"
    frameborder="0"
    allowfullscreen
>
</iframe>
```

> [!NOTE]
>
> If you're using a custom domain for your public links, then replace your custom domain with `embed.ente.com`. The easy method will automatically do this for you.

> [!NOTE]
>
> `https://embed.ente.io` is soft-deprecated. Existing embeds will keep working, but new embed links use `https://embed.ente.com`. You can update an old embed link by changing `embed.ente.io` to `embed.ente.com`.

### Embedding in WordPress (Block Editor)

WordPress supports Ente embeds using the Custom HTML block:

1. Open the page or post in the WordPress editor.
2. Click the block inserter and choose **Browse all** to expand the block list (the Custom HTML block may not appear in the quick list).
3. Search for or select **Custom HTML**.
4. Paste the iframe embed code that you copied from Ente.
5. Publish or update the page to make the embedded album live.

### Customizing the embed

You can customize the appearance by adjusting the iframe attributes:

- `width` and `height`: Control the size of the embed
- `allowfullscreen`: Allows viewers to open photos in fullscreen mode
- You can use percentage values for responsive sizing: `width="100%"`

#### Example with responsive sizing

```html
<div
    style="position: relative; padding-bottom: 75%; height: 0; overflow: hidden;"
>
    <iframe
        src="https://embed.ente.com/?t=...#..."
        style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;"
        frameborder="0"
        allowfullscreen
    >
    </iframe>
</div>
```

## Features

The embedded album viewer includes:

- Thumbnail grid view
- Full-size image viewer with navigation
- Video playback support
- Fullscreen mode (when `allowfullscreen` is set)
- Password protection (if enabled on the album)
- Automatic updates when you add new photos to the album

## Privacy and security

- The embed uses the same encryption and security as regular Ente albums
- Only photos in the public album are accessible through the embed
- If you delete the public link, the embed will stop working
- Password-protected albums will prompt for the password within the iframe

> [!NOTE]
>
> Password protection is extra access control, not extra encryption.
>
> Password protection adds server-side access control but does not re-encrypt the files. The files remain encrypted with the same key used for the public link. Password protection prevents unauthorized access by requiring authentication before the server grants access to the encrypted content.

Note that by putting the embed link in a webpage, you're making it public for anyone who can view the page, including search engines that can index your webpages. This isn't any different from putting the public link in your webpage or sharing it in a public forum, but it is good to call this out.

The album is still end to end encrypted in a manner that Ente does not have access to the key to decrypt the album. If you're curious how this works technically, then you can find [implementation details here](https://ente.com/blog/building-shareable-links/).

## Related topics

- [Public links](/photos/features/sharing-and-collaboration/public-links) - Learn about creating public album links
- [Sharing overview](/photos/features/sharing-and-collaboration/share) - All sharing methods in Ente
- [Custom domains](/photos/features/sharing-and-collaboration/custom-domains/) - Use your own domain for public links
- [Sharing and Collaboration FAQ](/photos/faq/sharing-and-collaboration) - Common questions about sharing
