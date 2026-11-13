---
title: Sharing FAQ
description: Frequently asked questions about sharing in Ente Locker
---

# Sharing FAQ

Answers to common questions about sharing items and collections in Ente Locker.

## Sharing with Users

### How do I share items with family? {#locker-share-family}

1. Create a collection for the items you want to share (or use an existing one)
2. Add all relevant items to the collection
3. Open the collection and tap the share button
4. Select **Share with Ente user**
5. Enter your family member's Ente email address
6. Tap **Share**

Your family member will receive the shared collection in their Locker app.

### Can I share with non-Ente users? {#locker-share-non-users}

Yes, using public links for individual items or collections. Create a public link that can be opened in any web browser:

#### For an item

1. Long press on the item
2. Tap the share button
3. Tap **Share link**
4. Copy and share the link

#### For a collection

1. Open the collection
2. Tap the share button
3. Tap **Share link**
4. Copy and share the link

Learn more about [Public links](/locker/features/sharing/public-links).

### What happens when I update a shared item? {#locker-update-shared}

When you update an item shared with Ente users:

- Recipients see the updated content next time they view the item
- They see the updated content next time they open it
- No notification is sent for updates

For public links, viewers see the current version when they access the link.

### What happens if I revoke access to shared content? {#locker-revoke-access}

When you remove someone's access:

- They immediately lose the ability to view the content
- The content disappears from their Locker
- Any public links are unaffected (must be revoked separately)

### Can I share individual items with Ente users? {#locker-share-individual-items}

Not directly. To share an individual item with another Ente user:

1. Add the item to a collection
2. Share the collection with them

Alternatively, create a [public link](/locker/features/sharing/public-links) for the item that anyone can access in a browser.

### Can shared users add items to shared content? {#locker-viewer-edit}

No. Shared collections are view-only. Only the owner can add or modify items.

### Can I see who has access to my shared content? {#locker-access-tracking}

Yes. Long press on the shared item or open the collection, tap the share button, and view the list of people with access.

### What happens if I delete a shared collection? {#locker-delete-shared-collection}

When you delete a collection you've shared with others:

- **If you're the owner**: The collection is removed from all shared users' accounts. They lose access to the items.
- **If you're a viewer**: You remove yourself from the shared collection. Other users and the owner retain access.

Items in a deleted shared collection follow the same rules as regular collections - you can choose to keep or delete the items when deleting the collection.

### What happens to shared items if the owner deletes their account? {#locker-owner-deletes-account}

If an account owner deletes their Ente account, all their shared collections become inaccessible to shared users. Viewers lose access to all content shared by that user.

If you need continued access to shared content, consider:

- Asking the owner to transfer ownership before account deletion
- Creating your own copies of important shared items

## Public Links

### Are public links end-to-end encrypted? {#locker-public-link-encryption}

Yes and no. The content remains encrypted on Ente's servers. However, the decryption key is embedded in the URL, so anyone with the link can decrypt and view the content.

### Can I see who viewed my public link? {#locker-link-analytics}

No. Ente does not track who views public links to maintain privacy. We can tell you how many devices have accessed a link, but not who.

### What happens if I share a sensitive password via public link? {#locker-sensitive-public}

Anyone with the link can view the password. Delete the link after use.

### How do I delete a public link? {#locker-revoke-link}

#### For an item

1. Long press on the item
2. Tap the share button
3. Tap **Delete link**

#### For a collection

1. Open the collection
2. Tap the share button
3. Tap **Delete link**

The link immediately stops working.

## Security

### How does sharing work with encryption? {#locker-sharing-encryption}

When sharing with Ente users:

1. Your device encrypts the sharing key with the recipient's public key
2. Only their device can decrypt this key
3. Ente's servers never have access to the decrypted content

For public links:

1. The decryption key is added to the URL fragment
2. The fragment is never sent to servers
3. Anyone with the full URL can decrypt the content

### Is it safe to share passwords via Locker? {#locker-safe-password-sharing}

When sharing with Ente users, yes. The end-to-end encryption protects the content.

When using public links, be cautious:

- Share the link through secure channels
- Delete the link after use

## Related Features

- [Share with users](/locker/features/sharing/share-with-users)
- [Public links](/locker/features/sharing/public-links)
- [Encryption](/locker/features/security/encryption)
