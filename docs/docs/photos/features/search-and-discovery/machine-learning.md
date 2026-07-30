---
title: Machine learning
description: Ente supports on-device machine learning for face recognition and natural language search
---

# Machine Learning

Ente supports on-device machine learning, allowing you to use the latest advances in AI while maintaining your privacy. All machine learning happens entirely on your device - your photos and ML data are never sent to Ente's servers.

## What Machine Learning Enables

Machine learning in Ente powers two main features:

### Face recognition

Search for your photos by the people in them. Ente will:

- Detect all faces in your photos
- Group similar faces together to create clusters of people
- Let you name persons for easy searching
- Help you find all photos with specific people

Learn more in the [Face recognition guide](/photos/features/search-and-discovery/face-recognition).

### Magic search

Search for your photos using natural language descriptions. You can search for:

- Objects: "car", "dog", "food"
- Scenes: "beach", "sunset", "mountain"
- Colors: "red flowers", "blue sky"
- Activities: "birthday cake", "swimming"
- Complex queries: "the red motorcycle next to a fountain"

Learn more in the [Magic search guide](/photos/features/search-and-discovery/magic-search).

## Enable Machine Learning

You can enable machine learning on either the mobile app or the desktop app.

**On mobile:**

Open `Settings > Machine learning` and enable **Machine learning** and/or **Local indexing**.

**On desktop:**

Open `Settings > Preferences > Machine learning` and enable **Machine learning** and/or **Local indexing**.

> [!NOTE]
>
> Machine learning is not available on photos.ente.com. You must use the mobile or desktop apps.

## The Indexing Process

After enabling machine learning, the app needs to download and index your photos locally.

### What happens during indexing

1. **Download**: The app downloads your original photos to your device
2. **Process**: ML models analyze each photo on your device
3. **Index**: Search indexes are created locally
4. **Encrypt & sync**: Indexes are encrypted and synced to your other devices

### Indexing performance

- **WiFi recommended**: Downloading photos is faster over WiFi
- **Desktop is faster**: Desktop computers can index faster than mobile devices
- **Time varies**: Indexing time depends on library size and device performance

### Monitoring progress

While indexing is in progress:

- **Mobile**: Check `Settings > Machine learning` for indexing status
- **Desktop**: Progress shown in the app
- **Search bar**: May show indexing status when clicked

## Tips for Faster Indexing

### Enable on desktop first

> [!TIP]
>
> If you have a large library on Ente, we recommend enabling machine learning on the desktop app first. Desktop computers can index your existing photos faster than mobile devices. Once your existing photos have been indexed, the indexes sync to your mobile devices, and your mobile app can then quickly index new photos as they're backed up.
>
> Indexing can run on multiple clients/devices in parallel (each client checks whether a file has already been indexed to avoid duplication or conflicts) However, this does **not** speed up the overall process, so desktop indexing is still recommended.

### Enable before importing

> [!TIP]
>
> If you're migrating a large library to Ente, enable machine learning before importing your photos. This allows the app to index your files as they're being uploaded, avoiding the need to download them again later for indexing.

## Privacy and Security

Machine learning in Ente maintains the same privacy guarantees as the rest of the app:

- **On-device processing**: All ML analysis happens on your device
- **Encrypted indexes**: Search indexes are encrypted before syncing
- **No server access**: Ente's servers never see your unencrypted photos or ML data
- **Not used for training**: Your photos are never used to train AI models

Your face recognition data, magic search indexes, and photos remain private and encrypted.

Learn more in [Security and Privacy FAQ](/photos/faq/security-and-privacy#ml-privacy).

## Syncing Indexes Across Devices

The indexes created by machine learning are synced across all your devices automatically using end-to-end encryption. This means:

- Index on one device, use on all devices
- New photos are indexed incrementally on each device
- Indexes are encrypted before syncing
- No need to re-index on every device

## Local Indexing

### Disabling local indexing on mobile

On mobile devices with low RAM (4-6GB) and large photo libraries, indexing might affect app performance. In such cases, you can disable local indexing on mobile and let your desktop handle it instead.

**To disable local indexing on mobile:**

Open `Settings > Machine learning` and disable local indexing.

This way, you can continue to use ML features without impacting your phone's performance. The desktop app will handle indexing, and the indexes will sync to your mobile device.

## Platform Differences

### Mobile apps (iOS and Android)

- Full ML support: face recognition and magic search
- Can modify face groupings (merge, de-merge, ignore)
- Can name persons and manage face clusters
- Local indexing can be disabled for low-end devices

### Desktop apps (Mac, Windows, Linux)

- Full ML support: face recognition and magic search
- Faster indexing than mobile
- Cannot currently modify face groupings (view only)
- Face grouping management must be done on mobile

### Web (photos.ente.com)

- ML features not available
- Basic search only (date, file name, description, album)

## Works Offline

Once your photos have been indexed, both face recognition and magic search work completely offline. The initial indexing requires downloading your photos (which is faster over WiFi), but after that all searches happen locally on your device without requiring an internet connection.

## Related FAQs

- [How do I enable face recognition?](/photos/faq/search-and-discovery#enable-face-recognition)
- [What is magic search?](/photos/faq/search-and-discovery#magic-search)
- [Can I merge or de-merge persons?](/photos/faq/search-and-discovery#merge-persons)
- [Does machine learning work offline?](/photos/faq/search-and-discovery#ml-offline)
- [Is my data used to train AI models?](/photos/faq/security-and-privacy#ml-privacy)
- [Why is face recognition faster on desktop?](/photos/faq/search-and-discovery#desktop-faster)
- [Indexing stuck at 100% but faces don't appear](/photos/faq/search-and-discovery#indexing-stuck-no-faces)
- [Machine learning features not working](/photos/faq/search-and-discovery#ml-features-not-working)
- [Performance issues during indexing](/photos/faq/search-and-discovery#ml-performance-issues)

## Related topics

- [Face recognition detailed guide](/photos/features/search-and-discovery/face-recognition)
- [Magic search detailed guide](/photos/features/search-and-discovery/magic-search)
- [Search and Discovery overview](/photos/features/search-and-discovery/)
- [Search and Discovery FAQ](/photos/faq/search-and-discovery)
- [Security and Privacy FAQ](/photos/faq/security-and-privacy)
