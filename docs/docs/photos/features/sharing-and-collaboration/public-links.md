---
title: Public links
description: Share photos via links without requiring Ente accounts
---

# Public links

Ente lets you share your photos via links that anyone can access without an app or account. The contents remain end-to-end encrypted, with decryption keys embedded in the link.

## Creating public links

You can create public links in two ways: from an existing album, or by selecting specific photos.

### From an album

Share an entire album via a public link:

**On mobile:**

1. Open the album you want to share
2. Tap the Share icon
3. Select "Create link" or "Share link"
4. Tap "Manage link" to configure optional [link features](#link-features) like album layout, password protection, link expiry, allow adding photos, etc
5. Tap "Copy link" and share it

**On web/desktop:**

1. Open the album
2. Click the share icon
3. Select "Create link"
4. Click "Manage link" to configure optional [link features](#link-features) like album layout, password protection, link expiry, allow adding photos, etc
5. Click "Copy link" and share it

### Quick link (from selected photos)

Create a shareable link without creating an album first:

**On mobile:**

1. Long press to select one or more photos
2. Tap "Send link"
3. The quick link is created
4. Copy and share the link

**On web/desktop:**

You can create a quick link in any of these ways:

1. Right-click a file and select "Send link" from the context menu
2. Select multiple files and use the "Send link" action in the top navbar
3. Open a file in the viewer and use "Send link" from the viewer menu

**How it works:** Ente creates a special album behind the scenes and adds your selected photos to it. The link works exactly like a regular public link - recipients see an album with the photos you selected.

**Managing quick links:**

- View all quick links in the Sharing tab under "Quick links"
- Quick links can be converted to regular albums if needed
- Removing a link doesn't delete the photos

## Link features

Public links support powerful customization, security, and control features:

### Album layout

Choose how recipients view your public links with these layout options:

**Masonry** (default): A dynamic grid that adapts to each photo’s size for a seamless layout.

**Trip**: Explore photos on an interactive map and timeline, perfect for travel and location-based albums.

**Grouped**: Photos are organized by date, making it easy to browse memories chronologically.

> [!NOTE]
>
> Trip layout public links are not supported on custom domains yet. When someone tries to access such a link, they will be redirected to the Trip layout public link on the default `albums.ente.com` domain. Other layouts will work perfectly on your custom domain.

### Password protection

Add a password to your link for an extra layer of security. Recipients must enter the correct password to view photos.

> [!NOTE]
>
> Password protection is extra access control, not extra encryption.
>
> Password protection adds server-side access control but does not re-encrypt the files. The files remain encrypted with the same key used for the public link. Password protection prevents unauthorized access by requiring authentication before the server grants access to the encrypted content.

**When to use:**

- Sharing sensitive content
- Limiting access to a specific group
- Adding security beyond link secrecy

### Link expiry

Set an expiration date for your link. After this time, the link automatically stops working.

**When to use:**

- Temporary event photo sharing
- Time-limited access
- Automatic cleanup of old shares

**Options:**

- Custom date/time
- Common presets (7 days, 30 days, etc.)
- Can be extended or changed later

### Device limits

Limit how many devices can access the link. This prevents the link from being widely forwarded.

**How devices are identified:**

A "device" is determined by the combination of IP address and browser/app (User-Agent). This means:

- Same browser on the same network = 1 device
- Different browsers on the same device = separate devices
- Same browser from different networks (e.g., home vs mobile data) = separate devices
- Once a device has accessed the link, it can continue accessing it even if the limit is later reached

**When to use:**

- Sharing with a known small group
- Preventing viral spread of the link
- Adding accountability to sharing

### Prevent downloads

Disable the option to download original quality photos. Recipients can still view photos and take screenshots, but can't download the original files.

**When to use:**

- Protecting professional work
- Watermarked preview sharing
- Limited distribution control

> [!NOTE]
>
> This doesn't prevent screenshots or screen recording, but does make it harder for recipients to get high-quality copies.

### Allow joining album

Let people who open the link in their Ente app add the shared album to their account. This is handy when you want other Ente users to keep the album in their Shared tab without sending them individual invites.

#### How joining works

When creating a public link, by default the **Allow joining album** option is enabled.

**On desktop:**

To join a public album, click the "Join album" button, sign in or sign up, and you'll be added to the album.

**On mobile:**

When you open the link on a mobile which also has the Ente Photos mobile app installed:

- Ideally, you'll be automatically redirected to the app, where you'll see a banner to join the album
- If not automatically redirected, the OS will show an option to reopen the link in the mobile app
- If neither happened, tap the "Join album" button on the page to open the app and join the album

If the Ente Photos mobile app is not installed, click the "Join album" button, sign in or sign up, and you'll be added to the album.

> [!NOTE]
>
> When someone joins an album, their email address becomes visible to the album owner and other participants. Disable this option if you need to keep participant identities private while still sharing via a public link.

When disabled, anyone with the link can still view the album in a browser, but they cannot join it from the Ente app.

#### Tips for recipients

- On iOS, Firefox does not show the option to reopen the link in the mobile app - Safari does.

<div align="center">

![Safari showing the Open in Ente banner](/join-ios-safari.jpg){width=320px}

</div>

- The prompt to reopen the link in the app does not work with custom domains; use the default `https://albums.ente.com` link instead.

### Allow adding photos (Collect mode)

Enable photo uploads through the link. Anyone with the link can add photos to the album via web browser - no Ente account needed.

**When to use:**

- Collecting event photos from guests
- Group trip photo gathering
- Wedding or party photo collection

When this option is enabled, the link becomes a "collect link". All photos added through the link count towards your storage quota.

Learn more in the [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration).

### Custom domains

Use your own domain instead of `albums.ente.com` for your public links.

For example: `https://pics.example.org/?t=...` instead of `https://albums.ente.com/?t=...`

Learn more in the [Custom domains guide](/photos/features/sharing-and-collaboration/custom-domains/).

## Managing links

### View all your links

**On mobile:**

- Go to the Sharing tab (bottom navigation)
- See "Shared albums" and "Quick links" sections

### Edit link settings

1. Find the link in your sharing list
2. Tap/click the three dots menu
3. Select "Edit link settings"
4. Modify password, expiry, device limits, or other options
5. Save changes

Changes apply immediately - anyone accessing the link will see the updated settings.

### Delete a link

1. Find the link in your sharing list
2. Tap/click the three dots menu
3. Select "Remove link"
4. Confirm deletion

Deleting a link makes it immediately inaccessible. The photos in the album remain in your account.

### Convert quick link to regular album

Quick links create special albums. You can convert them to regular albums:

1. Go to Sharing tab
2. Find the quick link under "Quick links"
3. Tap/click the three dots menu
4. Select "Convert to album"

The album becomes a regular album in your Albums tab, and the link continues to work.

## How encryption works

Public links are end-to-end encrypted, but with an important caveat:

**What's encrypted:**

- All photo and video files
- Photo metadata and album information
- Everything is encrypted before leaving your device

**The security trade-off:**

- Decryption keys are embedded in the link (in the URL fragment after #)
- Anyone with the link can decrypt and view the content
- The keys never reach Ente's servers (URL fragments aren't sent to servers)

**For sensitive content:**

- Use password protection for an additional security layer
- Set link expiration to limit exposure
- Use device limits to prevent wide sharing
- Consider sharing albums directly with Ente users instead

> Implementation details have been documented in our blog post: [Building shareable links](https://ente.com/blog/building-shareable-links/).

## Availability

Public links (including collect links and quick links) are available on all plans, including the free tier. Free plan users can create public links with a [device limit](https://ente.com/help/photos/features/sharing-and-collaboration/public-links#device-limits) of 5.

**Free users can:**

- Create public links ([device limit](https://ente.com/help/photos/features/sharing-and-collaboration/public-links#device-limits) of 5)
- View public links shared with them
- Add photos to collect links shared with them
- Create and receive shared albums

**Paid users can:**

- Create public links with no device limit
- Access all other premium features

## Related topics

- [Collaboration](/photos/features/sharing-and-collaboration/collaboration) - Collaborate with Ente users or collect photos from anyone
- [Custom domains](/photos/features/sharing-and-collaboration/custom-domains/) - Use your own domain for public links
- [Sharing overview](/photos/features/sharing-and-collaboration/share) - All sharing methods explained

## Related FAQs

- [What's the difference between public links and quick links?](/photos/faq/sharing-and-collaboration#link-types)
- [Can I use my own domain for public links?](/photos/faq/sharing-and-collaboration#custom-domains)
- [Can I set limits on public links?](/photos/faq/sharing-and-collaboration#link-limits)
- [Are public links end-to-end encrypted?](/photos/faq/sharing-and-collaboration#public-link-encryption)
- [Can I convert a quick link to a regular album?](/photos/faq/sharing-and-collaboration#quick-link-convert)
- [Who can create public links?](/photos/faq/sharing-and-collaboration#who-can-share)
