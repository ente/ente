---
title: Sharing and Collaboration FAQ
description: Frequently asked questions about sharing photos and collaborating in Ente Photos
---

# Sharing and Collaboration

## Understanding Sharing Methods

### What are the different ways to share in Ente? {#sharing-methods}

Ente offers three main ways to share photos, each designed for different use cases:

**1. Shared albums (with Ente users)**

Share directly with specific people who have Ente accounts:

- Invite by email address
- Recipients need an Ente account
- Choose Viewer, Collaborator, or Admin permissions
- Each photo's storage counts towards whoever uploaded it
- Perfect for ongoing collaboration with family and friends

Learn more: [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration)

**2. Public links (for anyone)**

Share via links that anyone can access without an account:

- **Regular public links**: View-only access to an album
- **Quick links**: Select photos → create link (Ente creates special album automatically)
- **Collect links**: Enable "Allow adding photos" so anyone can contribute
- Password protection, expiry, and device limits available
- Custom domains supported

Learn more: [Public links guide](/photos/features/sharing-and-collaboration/public-links)

**3. Collaborative albums (Ente users working together)**

Multiple Ente users can add photos to the same album:

- All collaborators can contribute photos
- Each person's uploads count towards their own storage
- Owner controls permissions and membership
- Supported on mobile, web, and desktop

Learn more: [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration)

For a complete overview, see [Sharing documentation](/photos/features/sharing-and-collaboration/share).

### Can I use "Send link" to share photos with another Ente user? {#send-link-vs-ente-sharing}

You can, but it isn't the intended way. **Send link** (also called a quick link) creates a public link that anyone with the URL can open; it doesn't matter whether the recipient has an Ente account.

For Ente-to-Ente sharing, create an album and share it directly with the other user's Ente email instead. They get end-to-end encrypted access in their own app, can comment and like, and you can grant Viewer, Collaborator, or Admin permissions. See [How do I share an album with other Ente users?](#share-with-users).

Use **Send link** when you want to share with someone who doesn't use Ente or when you don't need permissions and album-level controls.

### What's the difference between public links and quick links? {#link-types}

Quick links ARE public links - just with a different creation method:

**Public links:**

- Create from an existing album
- Share the entire album via link

**Quick links:**

- Select specific photos anywhere in Ente
- Ente creates a special album automatically
- Share via link (works exactly like a public link)
- Can convert to regular album later

Both support the same features: password protection, expiry, device limits, collect mode, and custom domains.

Learn more: [Public links guide](/photos/features/sharing-and-collaboration/public-links)

### Can I use my own domain for public links? {#custom-domains}

Yes! Ente's custom domains feature lets you serve your public album links using your own personalized domain instead of `albums.ente.com`.

For example, instead of:

```
https://albums.ente.com/...#...
```

You can use:

```
https://pics.example.org/...#...
```

**Requirements:**

- Your own domain or subdomain
- Ability to add a CNAME DNS record

**Setup:**

1. Link your domain in `Settings > Preferences > Custom domains` (currently web only)
2. Add a CNAME DNS record pointing your domain to `my.ente.com`
3. Wait for DNS changes to propagate (usually a few minutes)

Once configured, Ente automatically uses your custom domain when creating new public links. Ente still hosts and serves your albums - only the URL changes.

Learn more in the [Custom domains guide](/photos/features/sharing-and-collaboration/custom-domains/).

### Do Trip albums work with custom domains? {#trip-custom-domains}

Trip albums (albums with the Trip layout feature) are not currently supported on custom domains. When someone tries to access a Trip album through your custom domain, they will be automatically redirected to the default `albums.ente.com` domain.

Regular albums continue to work perfectly on your custom domain - only the Trip layout feature has this limitation.

Learn more in the [Custom domains guide](/photos/features/sharing-and-collaboration/custom-domains/).

### How can my partner and I automatically share all photos we take with each other? {#auto-share-partners}

You can do this by adding your partner as a viewer or collaborator to your camera folder, and asking them to do the same for you. On Android this is the **Camera** folder, and on iOS this is **Recents** (or equivalent).

Any new photos backed up to these folders will automatically be shared and synced to the other person's device. This results in two separate albums - one for your photos and one for your partner's - where both of you can view and add photos.

### Does Ente have a shared library feature where all photos are shared with another account (similar to Google Photos Partner Sharing/iCloud Shared Photo Library)? {#shared-library}

Ente has shared albums but does not support sharing your entire library in one click. However, you can share all albums by selecting one album, choosing the "all" option on the bottom right, which selects all albums and then you can share in one go with a partner (they can be [viewer/collaborator/admin](/photos/features/sharing-and-collaboration/collaboration#collaborating-with-ente-users)).

[Smart albums](/photos/features/albums-and-organization/auto-add-people#auto-add-people-to-albums-smart-albums) let you auto-add specific people to albums as well.

## Collaboration

### How do I share an album with other Ente users? {#share-with-users}

1. Open the album you want to share
2. Tap/click the Share icon
3. Select "Share with Ente users" or enter email addresses
4. Choose permissions (Viewer, Collaborator, or Admin)
5. Send the invitation

The recipient will receive a notification and can access the shared album from their Ente app. They must have an Ente account to receive shared albums.

### Who pays for storage in collaborative albums? {#collab-storage}

In collaborative albums (shared with other Ente users):

- Each photo's storage is counted towards **the person who uploaded it**
- Since collaborators usually already have the photo in their account, they effectively don't pay extra
- The album owner does not pay for photos uploaded by collaborators

In collect links (public links with upload enabled):

- All photos added via the link count towards **the album owner's storage**
- The owner has full control to remove photos at any time
- People adding photos via the link don't need Ente accounts and don't pay anything

Learn more: [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration)

### Can collaborators delete photos from shared albums? {#collab-permissions}

Permissions depend on your role:

**Viewers can:**

- View all photos in the album
- Download photos
- Add photos to their own albums (creates a copy)

**Collaborators can:**

- Everything viewers can do, plus:
- Add photos to the shared album
- Delete photos they uploaded themselves

**Admins can:**

- Everything collaborators can do, plus:
- Remove any photo from the album (including photos uploaded by others)
- Add or remove participants (as Admin, Collaborator, or Viewer)
- Suggest deletion for photos owned by others

**Album owner can:**

- Everything admins can do, plus:
- Manage link settings (passwords, expiry, device limits)
- Delete the entire album

### What happens when I remove a collaborator from an album? {#remove-collaborator}

When a collaborator is removed from a shared album (or when they leave the album voluntarily):

- Any photos they uploaded to the album will also be removed from that album
- Those photos remain in the collaborator's own account
- Photos uploaded by other collaborators or the owner remain in the album
- The removed collaborator loses access to view the album

### Is collaboration available on all platforms? {#collaboration-platforms}

**Collaborative albums** (sharing with other Ente users):

- Fully supported on mobile apps (iOS and Android), web, and desktop
- Can view, add, and manage photos

**Collaborative links** (collect links):

- Can be created on all platforms (mobile, web, desktop)
- Anyone with the link can add photos via web browser

### What can admins do in shared albums? {#admin-permissions}

Admins have elevated permissions that help them manage shared albums:

**Admins can:**

- Everything collaborators can do (view, add photos)
- Remove any photo from the album (including photos uploaded by others)
- Add or remove participants (as Admin, Collaborator, or Viewer)
- Suggest deletion for photos owned by others

**Admins cannot:**

- Manage link settings (passwords, expiry, device limits)
- Delete the album itself
- Permanently delete photos they don't own

Admins are ideal for trusted participants who help curate and manage the album, such as family members or event co-organizers.

Learn more: [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration#permissions-explained)

### How do I add someone as an admin? {#add-admin}

1. Open the album you want to share
2. Tap/click the Share icon
3. Enter the person's email address
4. Select "Admin" as the permission level
5. Send the invitation

You can also change an existing participant's role to Admin by opening the album's sharing settings and updating their permissions.

### What's the difference between admin and collaborator? {#admin-vs-collaborator}

| Permission               | Collaborator | Admin |
| ------------------------ | ------------ | ----- |
| View and download photos | ✓            | ✓     |
| Add photos to album      | ✓            | ✓     |
| Remove own photos        | ✓            | ✓     |
| Remove any photo         | ✗            | ✓     |
| Manage participants      | ✗            | ✓     |
| Suggest deletion         | ✗            | ✓     |
| Manage link settings     | ✗            | ✗     |

Use **Collaborator** for participants who should only add and view photos. Use **Admin** for trusted participants who help manage the album.

### Can admins manage link settings? {#admin-link-settings}

No, only the album owner can manage link settings (passwords, expiry, device limits). Admins can manage participants and photos, but cannot change link settings or delete the album.

### What is suggest deletion? {#suggest-deletion}

Suggest deletion allows album owners and admins to suggest that other participants delete their photos from shared albums.

**How it works:**

1. Open a shared album where you are owner or admin
2. Select photos owned by other participants
3. Tap the suggest deletion action
4. Confirm the suggestion

**What happens:**

- Photos are immediately removed from the album
- Photo owners receive the suggestion in their Delete Suggestions queue
- Photo owners can accept (delete) or reject (keep) each suggestion

This is useful for curating shared albums after group trips or events by suggesting removal of blurry, duplicate, or unwanted shots.

> [!NOTE]
>
> Suggest deletion is currently available on mobile apps only.

Learn more: [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration#suggest-deletion)

### How do I suggest deleting photos in a shared album? {#use-suggest-deletion}

**On mobile:**

1. Open a shared album where you are owner or admin
2. Select photos that belong to other participants
3. Tap the suggest deletion action (flag icon)
4. Confirm the suggestion

The photos will be removed from the album immediately, and the photo owners will receive delete suggestions to review.

> [!NOTE]
>
> Suggest deletion is currently available on mobile apps only.

### How do I review delete suggestions? {#review-delete-suggestions}

If album owners or admins suggest deleting your photos, you can review these suggestions:

**On mobile:**

Open `Settings > Backup > Free up space > Delete suggestions` to see photos suggested for deletion.

For each suggestion, you can:

- **Accept**: Move the photo to Trash (can be recovered within 30 days)
- **Reject**: Keep the photo and dismiss the suggestion

The photo was already removed from the shared album when the suggestion was made. Accepting deletes the photo from your account. Rejecting keeps it in your account (but not in the album).

> [!NOTE]
>
> Delete suggestions is currently available on mobile apps only.

Learn more: [Storage optimization guide](/photos/features/albums-and-organization/storage-optimization#delete-suggestions)

### Is suggest deletion available on web? {#suggest-deletion-web}

No, suggest deletion and reviewing delete suggestions are currently available on mobile apps (iOS and Android) only. We're working on adding this feature to web and desktop in the future.

### Why am I not getting notifications when photos are added to shared albums? {#shared-album-notifications}

**On iOS:**

Notification limitations on iOS are due to Apple's platform restrictions:

⚠️ **Notifications only work when the app is running in the background**, not if you've force-closed it from the app switcher.

**Why this happens:**

- iOS delivers notifications via silent push notifications
- These "wake up" the app to check for new photos
- If you force-kill the app, iOS won't deliver these notifications
- This is an Apple platform limitation, not an Ente bug

**To receive notifications on iOS:**

1. Enable notifications in device `Settings > Ente > Notifications`
2. Enable Background App Refresh in device `Settings > Ente`
3. **Don't force-close the Ente app** from the app switcher
4. The app can run in the background without draining battery

**On Android:**

Notifications work more reliably on Android, but can still be affected by:

- Battery optimization settings restricting the app
- Force-closing the app from recents
- Notification permissions not granted

**To receive notifications on Android:**

1. Open device `Settings > Ente > Notifications` and ensure all notification categories are enabled
2. Disable battery optimization for Ente in system settings
3. Don't force-close the app from recents

**Alternative:** If you need real-time updates, keep the app open or check the shared album manually by opening it in the app.

- No platform restrictions for link recipients

## Public Links

### How do I create a collect link to gather photos from others? {#create-collect-link}

Collect links let anyone add photos to your album without needing an Ente account - perfect for gathering photos from events, parties, or trips.

**On mobile:**

1. Open the album you want to use for collecting photos
2. Tap the Share icon in the top right corner
3. Select "Collect photos"
4. Tap "Copy link"
5. Share the link with anyone you want to collect photos from

**On web/desktop:**

1. Open the album
2. Click the share album icon
3. Select "Collect photos"
4. Click "Copy link"
5. Share the link via email, messaging, or however you prefer

Anyone with the link can view existing photos and add their own through their web browser. All collected photos count toward your storage quota. Learn more in the [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration).

### Can people without Ente add photos to my album? {#collect-without-account}

Yes! When you create a collect link (public link with "Allow adding photos" enabled), anyone with the link can view and add photos using just their web browser - no Ente account or app installation required.

This is perfect for collecting event photos from a large group of people, like weddings, parties, or trips, where not everyone uses Ente.

To enable this, create a public link and enable the "Allow adding photos" option. Learn more in the [Collaboration guide](/photos/features/sharing-and-collaboration/collaboration).

### Do collected photos count against my storage? {#collect-storage}

Yes, photos added to your album through a collect link count towards your storage quota as the album owner.

When someone adds a photo via a collect link:

- The photo is stored in your account
- You have full control to remove these photos at any time
- The storage counts against your plan's total storage limit

Make sure you have sufficient storage available if you're expecting many people to add photos.

### Can I let others view a shared album without allowing download of the photos? {#disable-downloads-public-link}

Yes. When creating or managing a public link, you can turn off downloads.

Open the album, create or manage the public link, and disable **Allow downloads**.

This lets people view the album through the link without showing them a download option.

### Can I set limits on public links? {#link-limits}

Yes! Public links (including collect links) support several protective features:

- **Link expiry**: Set the link to automatically expire after a duration you define
- **Device limits**: Limit how many devices can access the link (a "device" is identified by the combination of IP address and browser/app, so the same browser on a different network counts as a separate device)
- **Password protection**: Add an additional password that users must enter to access the link
- **Prevent downloads**: Disable the option to download original photos (though screenshots can't be prevented)

These options help you maintain control over who can access and contribute to your shared albums.

### Can I stop people from adding more photos to a collect link? {#disable-collect-link}

Yes, you have several options:

1. **Remove the link entirely**: Delete the public link from your sharing settings
2. **Set an expiry date**: Configure the link to automatically expire after a certain time
3. **Disable uploads**: Edit the link settings and turn off "Allow adding photos"
4. **Change to view-only**: Convert the collect link to a regular public link (view only)

You can manage these settings by opening the shared album (under the "Shared" tab in the Albums section) and selecting the link you want to modify.

### Can I see who added photos to my collect link? {#collect-link-attribution}

When photos are added via a collect link (by people without Ente accounts), you cannot see specifically who added each photo. The photos will appear in your album without attribution.

In collaborative albums (with other Ente users), you can see who uploaded each photo by viewing the photo's info.

### Will upgrading to a paid plan automatically remove device limits for existing public links that were shared while on free plan? {#device-limit-upgrade}

For existing album links shared while on the free plan, the device limit will not be removed automatically. You can edit the device limit from manage link option (open album>link icon on top)

Once you upgrade to a paid plan, all future public links will have no device limit unless you set one yourself.

### Why do emails on my feed appear masked for public links? {#masked-emails-public-links}

On public links, contributor emails are masked by default to protect privacy.

If you're an album member viewing comments or likes in the mobile app, you'll see names instead of masked emails - but only for people you've already added to your People list with their linked email address.

Anonymous viewers (people without an Ente account) can also show a name if they've entered one themselves when liking or commenting.

## Public Link Features

### Can I convert a quick link to a regular album? {#quick-link-convert}

Yes! Quick links automatically create a special album behind the scenes. You can convert this to a regular album at any time:

1. Open the Albums tab in the Ente app
2. Tap on 'v' icon at the right.
3. Tap "Links"
4. Find the quick link and select the option to convert it to a regular album

This gives you more control over the album, including the ability to rename it and organize it like any other album.

### How do I create a quick link? {#create-quick-link}

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
4. Copy and share the link

Ente creates a special album behind the scenes with the selected photos. Quick links work like public links and support the same features (password protection, expiry, etc.).

## Managing Shared Content

### Can I add photos from a shared album to my own albums? {#add-shared-photos}

Yes, on Ente's mobile, web, and desktop apps, you can add photos from an album that's shared with you into one of your own albums.

> [!IMPORTANT]
>
> This creates a copy of the photo that you fully own, and it will count against your storage quota. This is different from just viewing shared photos, which doesn't use your storage.

The reason for creating copies is to avoid complications around ownership - if the original owner deletes the photo from their library, your copy remains safe in your account.

### Can I upload, add, or move files in shared albums on web/desktop? {#manage-shared-album-files}

Yes. On web and desktop, collaborators, admins, and owners can upload files from their device to shared albums, and can add files already in their Ente library to shared albums.

### Why does adding shared photos to my albums count against my storage? {#shared-storage-count}

When you add a shared photo to your own album, Ente creates a hard copy that you fully own. This ensures that:

1. **You maintain control**: The photo remains in your account even if the original owner deletes it
2. **Ownership is clear**: There's no ambiguity about who owns which version of the photo
3. **No dependency**: Your organized albums don't break if someone stops sharing with you

We understand this uses extra storage in some use cases (like family photo sharing). We're exploring reference-based solutions in the future where storage would only count if the original is deleted. See [this discussion](https://github.com/ente/ente/discussions/790) for more details.

### Why don't photos added via a shared link appear in my feed? {#shared-link-photos-not-in-feed}

Only photos added by Ente users who joined the album directly will appear in your feed. Photos added through a public link by someone without an Ente account are not shown in the feed.

### Why do photos shared by others appear in my main gallery? {#shared-photos-in-gallery}

By default, shared items can appear in your home gallery.

To hide them, open `Settings > Appearance > Gallery` and enable **Hide shared items from home gallery**.

### Can I remove myself from a shared album? {#leave-shared-album}

Yes, if someone has shared an album with you, you can leave it at any time:

1. Open the shared album
2. Tap/click the three dots menu
3. Select "Leave album"

After leaving, you'll no longer have access to the album. If you were a collaborator and uploaded photos, those photos will be removed from the album but remain in your own account.

### What happens to the photos in a shared album if it's deleted or sharing stops? {#shared-album-deleted-content}

It depends on who uploaded each photo:

- **Photos you uploaded**: These always stay in your personal library, no matter what happens to the shared album. You don't lose anything you added yourself.
- **Photos uploaded by others**: You lose access to these if the album is deleted, or if you leave or are removed from it. There is no automatic saving and no advance warning when this happens.

When the album owner deletes a shared album, they see a dialog warning that the album will be deleted for everyone and that they will lose access to photos uploaded by others.

**To save others' photos before that happens:**

1. Open the shared album.
2. Long-press to select photos, then tap **Select all**.
3. Tap **Add to album** and choose one of your own albums.

This creates copies that you fully own, so they remain in your library even if the shared album later goes away. Note that copies count towards your own storage. See [Why does adding shared photos to my albums count against my storage?](#shared-storage-count).

### Why are there duplicate photos in a shared album we both add to? {#shared-album-duplicates}

When two people add photos to a shared album, Ente does not detect or warn about duplicates across the different owners. If you and another member each add the same video or photo (for example, one received it through another sharing method and already had it), both copies appear in the album.

Deduplication and the similar-images tool only work within albums you own, not across photos owned by different people in a shared album.

### How do I see all my shared albums? {#view-shared-albums}

**On mobile:**

- Open the Albums tab
- Tap the "Shared" tab to see albums you've shared, or the "Received" tab to see albums shared with you

**On web/desktop:**

- Shared albums appear in your album list
- They're marked with a sharing icon

## Permissions and Access

### Who can create collaborative albums or public links? {#who-can-share}

Album sharing and public links are now available on every plan, including the free tier. Free plan users can create public links with a [device limit](https://ente.com/help/photos/features/sharing-and-collaboration/public-links#device-limits) of 5. This limitation helps safeguard against potential platform abuse.

Free users can:

- Create and receive shared albums
- Share albums directly with other Ente users
- Create public links ([device limit](https://ente.com/help/photos/features/sharing-and-collaboration/public-links#device-limits) of 5)
- View public links shared with them
- Add photos to collect links that allow uploads

Paid users can:

- Create public links with no device limit
- Access all other premium features

### Can I change permissions for collaborators after sharing? {#change-permissions}

Yes, the album owner or admins can change permissions at any time:

1. Open the shared album
2. Open sharing settings
3. Find the participant
4. Change their role (Viewer, Collaborator, or Admin)

Viewers can only view and download photos. Collaborators can also add photos. Admins can manage photos and participants.

### What happens to shared albums if I cancel my subscription? {#cancel-subscription-impact}

If you're the owner of shared albums and your paid subscription expires:

- Existing shared albums will remain accessible to collaborators
- You won't be able to create new shares
- You won't be able to modify existing share settings

Receiving shared albums works on free accounts, so if someone shares with you, you can still access those albums even without a paid plan.

## Security and Privacy

### Are public links end-to-end encrypted? {#public-link-encryption}

Yes, content shared via public links remains end-to-end encrypted. However, the decryption keys are embedded in the link itself (as a URL fragment that never reaches our servers). This means anyone with the link can decrypt and view the content. For sensitive content, use password protection and link expiration features to add extra security layers.

Learn more about [public link encryption](/photos/faq/security-and-privacy#public-link-encryption) in our Security and Privacy FAQ.

### How does sharing work with encryption? {#sharing-encryption-technical}

The information required to decrypt an album is encrypted with the recipient's public key such that only they can decrypt them.

You can read more about this in our [architecture documentation](https://ente.com/architecture#sharing).

In case of sharable links, the key to decrypt the album is appended by the client as a [fragment to the URL](https://en.wikipedia.org/wiki/URI_fragment), and is never sent to our servers.

### Can Ente see my shared photos? {#ente-see-shared}

No. Ente has no information about:

- Whether you have shared an album
- What photos are in shared albums
- Who you've shared with
- What's in public links

All sharing happens with end-to-end encryption. Only people you share with (or who have the link) can decrypt and view the content.

## Embedding Albums

### How do I embed an album on my website? {#embed-albums}

Ente allows you to embed public albums on your own website or blog using an iframe, similar to how you would embed a YouTube video.

**Easy method:**

Open the album in Ente (web or mobile app), create a public link, open link settings, and tap/click "Copy embed HTML".

**Manual method:**

Create a public link for your album, then add an iframe to your HTML with the URL, replacing `albums.ente.com` with `embed.ente.com`:

```html
<iframe
    src="https://embed.ente.com/...#..."
    width="800"
    height="600"
    frameborder="0"
    allowfullscreen
>
</iframe>
```

For complete details, see the [Embed albums guide](/photos/features/sharing-and-collaboration/embed).

### Do embedded albums work with custom domains? {#embed-custom-domains}

Yes, but you need to use `embed.ente.com` instead of your custom domain in the iframe src.

If you're using the easy method (copy embed HTML button), the app automatically handles this for you - it will use `embed.ente.com` regardless of your custom domain setting.

If you're creating the embed code manually and have a custom domain configured:

- Replace your custom domain with `embed.ente.com` in the iframe src
- For example: `https://embed.ente.com/...#...` (not `https://pics.example.org/...#...`)

The embed will still work perfectly - it's just served from the embed subdomain instead of your custom domain.

### Can I embed password-protected albums? {#embed-password}

Yes! Password-protected albums work in embeds. When someone views the embedded album, they'll see a password prompt within the iframe. Once they enter the correct password, they can view the photos.

The embed maintains all the security features of your public link:

- Password protection (if enabled)
- Same end-to-end encryption
- Link expiry (if set)
- Device limits (if set)

### What happens to my embed if I delete the public link? {#embed-deletion}

If you delete the public link, the embed will immediately stop working. The embedded album requires an active public link to function.

If you want to stop people from accessing the embedded album:

1. Delete the public link from the album's sharing settings
2. The embed will show an error or empty state
3. Remove the embed code from your website

If you just want to temporarily disable access, consider using the link's password protection or expiry features instead of deleting it entirely.

### What features are available in embedded albums? {#embed-features}

Embedded albums include:

- Thumbnail grid view
- Full-size image viewer with navigation
- Video playback support
- Fullscreen mode (when `allowfullscreen` attribute is set)
- Password protection (if enabled on the link)
- Automatic updates when you add new photos to the album

You can customize the embed size using iframe width/height attributes, including responsive sizing with percentages.

See the [Embed feature guide](/photos/features/sharing-and-collaboration/embed) for customization examples.

## Partner Sharing and Family Plans

### Can I share my entire library with my partner like Google Photos Partner Sharing? {#partner-sharing}

Not in a single click, but two steps give you the same outcome.

**Step 1: Auto-share every new photo**

Each of you shares your phone's camera folder with the other as admin or collaborator:

1. Open Ente → Recents (or Camera on Android).
2. Tap share → add your partner's Ente email as admin or collaborator.
3. Have your partner do the same in reverse.

From then on, every new photo either of you takes appears in both libraries automatically.

**Step 2: Share past photos**

1. Open Ente → Albums.
2. Long-press an album to enter selection mode.
3. Tap **All** at the bottom right to select every album.
4. Tap share → add your partner's email as admin or collaborator.

If you've both done a Google Takeout, only one of you should upload it to avoid duplicates.

You can also use a single shared account if you prefer, where both phones upload to the same login. This means sharing one password and one recovery key.

### Does a family plan share photos automatically between members? {#family-plan-photo-sharing}

No. Family plans share storage only. Each member gets their own private space and cannot see other members' photos unless they explicitly share albums using Ente's sharing features. Tags, face labels, and ML learnings are not shared between members, and you cannot deduplicate across family accounts.

### Can I change the initial shown on shared photos? {#shared-photo-initial}

The initial comes from the saved contact name. If the contact isn't saved, Ente uses the first letter of their email address. Save the contact under the name you want and the initial will update.

### A shared album contains Android Motion Photos that won't download on my iPhone. What can I do? {#android-motion-photos-iphone}

Android Motion Photos and Apple Live Photos use different pairing formats, so saving an Android-origin motion photo into Apple Photos as a native Live Photo may fail.

As a workaround, open the shared album link in a web browser and use the download option there. For motion photos, the web app downloads a ZIP containing the still image and the motion video as separate files. This preserves both parts, though importing them into Apple Photos as a native Live Photo may still not work automatically.
