---
title: Home Widgets
description: Add beautiful photo widgets to your phone's home screen with Ente Photos
---

# Home Widgets

Ente Photos offers home screen widgets that display your photos directly on your phone's home screen. Widgets automatically refresh with new photos from your library, bringing your memories to life throughout the day.

> [!NOTE]
>
> Home widgets are available on mobile apps only (iOS and Android).

## Widget Types

Ente provides three types of home screen widgets:

### Memories Widget

Displays photos from your memories, including:

- **On This Day**: Photos from the same date in previous years
- **Past Years**: Memories from past years
- **Smart Memories**: AI-curated memorable moments

The Memories widget automatically rotates through your memories, surfacing nostalgic moments right on your home screen.

### Albums Widget

Shows photos from your selected albums. By default, it displays photos from your **Favorites** album, but you can customize which albums to include.

### People Widget

Displays photos featuring selected people from your library. This widget helps you keep photos of your loved ones front and center.

**Requirement**: The People widget requires [face recognition](/photos/features/search-and-discovery/face-recognition) to be enabled. You must first enable machine learning and allow face recognition to detect and group people in your photos.

## Adding Widgets to Your Home Screen

### On iOS

1. Long press on your home screen until apps start jiggling
2. Tap the **+** button in the top left corner
3. Search for "Ente" or scroll to find Ente Photos
4. Choose the widget type (Memories, Albums, or People)
5. Select your preferred widget size
6. Tap **Add Widget**
7. Position the widget and tap **Done**

### On Android

1. Long press on an empty area of your home screen
2. Tap **Widgets**
3. Find and expand **Ente Photos**
4. Long press your desired widget and drag it to your home screen
5. Resize the widget if needed

## Configuring Widgets

### Widget Settings

Open `Settings > Widgets` in the Ente app to configure your widgets.

### Configuring the Albums Widget

1. Open `Settings > Widgets > Albums widget`
2. Select which albums you want to display on your home screen
3. By default, the **Favorites** album is selected
4. You can select multiple albums to include more variety

### Configuring the People Widget

1. Open `Settings > Widgets > People widget`
2. Select which people you want to feature
3. Only people detected by face recognition will appear as options

> [!NOTE]
>
> You must enable [face recognition](/photos/features/search-and-discovery/face-recognition) before configuring the People widget.

### Configuring the Memories Widget

1. Open `Settings > Widgets > Memories widget`
2. Toggle which memory types to include:
    - **On This Day**: Photos from this date in previous years
    - **Past Years**: Yearly memories
    - **Smart Memories**: AI-curated memorable moments

## How Widgets Work

### Data Synchronization

Widgets sync photos from your Ente library to your device's widget storage:

1. The app selects photos based on your widget configuration
2. Thumbnails are rendered and cached locally (512px resolution)
3. Up to 50 photos are cached per widget type
4. Widgets read from this local cache to display photos
5. The album widget cache is periodically rebuilt to rotate in more photos from your selected albums

### Automatic Refresh

Widgets automatically refresh approximately every **15 minutes** from their local cache. For album widgets, the app periodically refreshes that cache so a broader set of selected album photos can appear over time.

### Tapping Widgets

When you tap a photo on a widget:

- The Ente app opens directly to that photo
- For Memories widgets, you'll see the memory collection
- For Albums widgets, you'll see the photo in its album context
- For People widgets, you'll see photos of that person

## Tips for Best Experience

### Ensure Photos Are Backed Up

Widgets display photos that are backed up to Ente. Make sure your photos are synced for the best widget experience.

### Enable Face Recognition Early

If you want to use the People widget, enable face recognition in advance so the app can detect and group faces in your photos.

Open `Settings > Machine learning` and enable face recognition.

### Keep the App Updated

Widget improvements are released regularly. Keep the Ente app updated for the best performance and new features.

### Add Favorite Photos

The Albums widget defaults to your Favorites album. Add photos to Favorites by tapping the heart icon on any photo. This ensures your most cherished photos appear on your home screen.

## Platform Availability

| Platform    | Home Widgets     |
| ----------- | ---------------- |
| iOS app     | ✅ Supported     |
| Android app | ✅ Supported     |
| Desktop app | ❌ Not available |
| Web browser | ❌ Not available |

## Privacy and Security

Home widgets maintain Ente's privacy standards:

- **Local storage**: Widget images are stored locally on your device
- **Encrypted sync**: Data synced from Ente servers is end-to-end encrypted
- **No external access**: Widget data is only accessible by the Ente app and system widget framework
- **Secure deep links**: Tapping widgets uses secure internal links to open photos

## Related FAQs

- [How do I add a home widget?](/photos/faq/advanced-features#add-home-widget)
- [How do I configure which albums appear on my widget?](/photos/faq/advanced-features#configure-widget-albums)
- [Why does the People widget require face recognition?](/photos/faq/advanced-features#people-widget-face-recognition)
- [How often do widgets refresh?](/photos/faq/advanced-features#widget-refresh-rate)
- [Widget not showing photos](/photos/faq/advanced-features#widget-not-showing-photos)

## Related Topics

- [Face recognition guide](/photos/features/search-and-discovery/face-recognition)
- [Machine learning guide](/photos/features/search-and-discovery/machine-learning)
- [Notifications](/photos/features/utilities/notifications)
