---
title: Share
description: Securely share photos and videos stored in Ente Photos
---

# Sharing

Ente makes it easy to share your photos and videos while maintaining end-to-end encryption and privacy. You have complete control over who can view, add, or download your shared content.

## How sharing works

Your photos and videos remain encrypted at all times. When you share content, only the people you share with receive the decryption keys needed to view your photos. Ente's servers never have access to your unencrypted files.

## Ways to share

### Share with Ente users

If the person you want to share with has an Ente account, you can share an album directly with them by entering their email address. They'll receive a notification and can access the shared album from their Ente app.

**To invite someone to Ente**: Send them an invite from the app. Once they create an account, you can share albums with them.

### Share via public links

Create shareable links that anyone can access without an Ente account. Public links are perfect for sharing with large groups or people who don't use Ente.

**Security note**: While files remain end-to-end encrypted, the decryption keys are embedded in the link. Anyone with the link can view the content and potentially share the link with others. Use password protection and expiration settings for sensitive content.

Both shared albums and public links support [collaboration](/photos/features/sharing-and-collaboration/collaboration), allowing recipients to add their own photos.

## Links

You can create links to your albums by opening an album and clicking on the Share icon. They are publicly accessible by anyone who you share the link with. They don't need an app or account.

These links can be password protected, or set to expire after a while.

You can read more about the features supported by Links [here](https://ente.com/blog/powerful-links/).

## Albums

If your loved ones are already on Ente, you can share an album with their registered email address.

If they are your partner, you can share your `Camera` folder on Android, or `Recents` on iOS. Whenever you click new photos, they will automatically be accessible on your partner's device.

## Collaboration

You can allow other Ente users to add photos to your album. This is a great way for you to build an album together with someone. You can control access to the same album - someone can be added as a `Collaborator`, while someone else as a `Viewer`.

If you wish to collect photos from folks who are not Ente, you can do so with our Links. Simply tick the box that says "Allow uploads", and anyone who has access to the link will be able to add photos to your album.

## Organization

You can favorite items that have been shared with you, and organize them into your own albums.

When you perform these operations, Ente will create a hard copy of these items, that you fully own. This means, these copied items will count against your storage space.

We understand there are use cases where this approach will consume extra space (for eg. if you are organizing photos of a family member). We chose hard copies as a first version to avoid complexities regarding the ownership of shared items, in case the original owner were to delete it from their own library.

We plan to tackle these complexities in the future, by copying a reference to the item that was shared, instead of the actual file, so that your storage will only get consumed if the original owner deletes it from their library. If this sounds useful to you, please participate in [this discussion](https://github.com/ente/ente/discussions/790).

## Technical details

More details, including technical aspect about how the sharing features were implemented, are in various blog posts announcing these features.

- [Collaborative albums](https://ente.com/blog/collaborative-albums)

- [Collect photos from people not on ente](https://ente.com/blog/collect-photos)

- [Shareable links for albums](https://ente.com/blog/shareable-links), [and their underlying technical implementation](https://ente.com/blog/building-shareable-links). Since then, we have also added the ability to password protect public links, and configure a duration after which the link will automatically expire.

## Limitations

Peer-to-peer sharing between Ente users and creating public links are available on every plan, including the free tier. Free plan users can create public links with a device limit of 5, while paid users can create public links with no device limit.

## Related topics

- [Collaboration](/photos/features/sharing-and-collaboration/collaboration) - Collaborate with Ente users or collect photos from anyone
- [Public links](/photos/features/sharing-and-collaboration/public-links) - Share via links (includes quick links and collect mode)
- [Custom domains](/photos/features/sharing-and-collaboration/custom-domains/) - Use your own domain for public links

## Related FAQs

- [What are the different ways to share in Ente?](/photos/faq/sharing-and-collaboration#sharing-methods)
- [What's the difference between public links and quick links?](/photos/faq/sharing-and-collaboration#link-types)
- [Can I use my own domain for public links?](/photos/faq/sharing-and-collaboration#custom-domains)
- [How do I share an album with other Ente users?](/photos/faq/sharing-and-collaboration#share-with-users)
- [Can people without Ente add photos to my album?](/photos/faq/sharing-and-collaboration#collect-without-account)
- [Why does adding shared photos count against my storage?](/photos/faq/sharing-and-collaboration#add-shared-photos)
- [Are public links end-to-end encrypted?](/photos/faq/sharing-and-collaboration#public-link-encryption)
- [Who can create collaborative albums or public links?](/photos/faq/sharing-and-collaboration#who-can-share)
