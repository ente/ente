---
title: Face recognition
description: Use on-device face recognition to find and organize photos by people in Ente Photos
---

# Face Recognition

Face recognition in Ente helps you find and organize photos by the people in them. All face recognition happens entirely on your device, maintaining your privacy while providing powerful search capabilities.

## How Face Recognition Works

When you enable face recognition:

1. Ente detects all faces in your photos
2. Similar faces are automatically grouped together
3. You can name these groupings to identify people
4. Search for specific people by name
5. Find all photos containing particular persons

All of this happens on your device. Your photos and face data are never sent to Ente's servers.

## Enabling Face Recognition

Face recognition is part of Ente's machine learning features. You must enable it manually (it's off by default).

**On mobile:**

Open `Settings > Machine learning`, enable **Machine learning** and/or **Local indexing**, and wait for indexing to complete.

**On desktop:**

Open `Settings > Preferences > Machine learning`, enable **Machine learning** and/or **Local indexing**, and monitor indexing progress.

> [!NOTE]
>
> Face recognition is not available on photos.ente.com. You must use the mobile or desktop app.

### Initial Indexing

After enabling face recognition:

- The app downloads your photos to index them locally
- Progress is shown as a percentage (e.g., "Indexing... 45%")
- This is faster over WiFi and on desktop computers
- Once complete, faces are grouped automatically

**Indexing tips:**

- For large libraries, enable on desktop first (faster indexing)
- Keep the app open during initial indexing
- Once indexed on one device, the indexes sync to other devices

Learn more about [Machine learning](/photos/features/search-and-discovery/machine-learning).

## Using Face Recognition

### Viewing recognized faces

**On mobile:**

1. Tap the search icon at the bottom right
2. Scroll to the **People** section
3. Browse all recognized face groupings

**On desktop:**

- Access the People section through the top tab

### Naming persons

Once faces are grouped, you can assign names to identify people:

**On mobile:**

1. Open the People section
2. Tap on a person cluster
3. Tap **Add name** or the edit icon
4. Enter the person's name
5. The person is now searchable by name

**On desktop:**

1. Open a person grouping
2. Click **Add a name**
3. Enter the person's name

After naming, you can search for that person by typing their name in the search bar.

### Searching for specific people

Once you've named persons:

- Type the person's name in the search bar
- All photos containing that person will appear
- Works across all your albums
- Search is instant and happens on your device

## Managing Face Groupings

### Merging persons

If the same person is split into multiple groupings, you can merge them by assigning the same name.

**On mobile:**

1. Make sure one grouping has a name assigned
2. Open the second grouping
3. Tap the **Add a name** banner
4. Instead of typing, tap the existing name from the list
5. The two groupings are now merged

**On desktop:**

- Similarly, use the **Add a name** button
- Select an existing person from the list to merge

### De-merging persons

If incorrectly grouped faces were merged, you can undo the merge.

**On mobile:**

1. Open the person
2. Tap **Review suggestions**
3. Tap the **History icon** (top right)
4. Tap the **minus icon** beside the group you want to de-merge

**On desktop:**

1. Open the person
2. Click **Review suggestions**
3. Click the **history icon** (top right)
4. Undo previous merges if necessary

### Removing incorrect faces from a person

Sometimes the wrong face gets grouped with a person. You can remove incorrect faces:

**On mobile:**

1. Open the person from the People section
2. Tap the three dots (overflow menu)
3. Select **Edit**
4. Long-press on photos with incorrect faces
5. Select the photos to remove
6. Tap **Remove** from the action bar

**On desktop:**

- Currently, editing face groupings is only supported on mobile
- Desktop can view and name persons, but not modify groupings

### Changing the cover photo for a person

**On mobile:**

1. Open the person grouping
2. Long-press the image you want as the cover
3. Tap **Use as cover**

**On desktop:**

- Desktop currently doesn't support picking a cover
- It defaults to the most recent image

### Ignoring certain persons

You can tell the app not to show certain face groupings.

**On mobile:**

1. Make sure the person is **not named** (if named, tap **Remove person label** first)
2. Inside the unnamed grouping, tap **Ignore person** from the top right menu

**To undo:**

1. Open a photo containing the ignored person
2. Open **file info**
3. Tap the **face thumbnail** of the ignored person
4. Tap **Show person**

**On desktop:**

- Use the **Ignore** option from the top right menu
- To undo, open that person via file info and select **Show person**

## Special Cases

### Photos of babies and toddlers

Face recognition models (including Ente's) struggle with pictures of babies and young children. Faces change rapidly at that age, making grouping difficult.

If you find a mixed grouping with several different babies:

**On mobile:**

1. Open the mixed grouping
2. Tap the **mixed grouping** option in the top right menu
3. The model will re-evaluate with stricter settings
4. This should separate different babies into different groupings

> [!NOTE]
>
> This functionality is currently only available on mobile.

## Platform Differences

### Mobile apps (iOS and Android)

- ✅ View recognized faces
- ✅ Name persons
- ✅ Merge and de-merge persons
- ✅ Remove incorrect faces
- ✅ Change cover photos
- ✅ Ignore persons
- ✅ Handle mixed groupings

### Desktop apps (Mac, Windows, Linux)

- ✅ View recognized faces
- ✅ Name persons
- ✅ Merge persons (by assigning same name)
- ❌ Cannot modify face groupings (edit, remove faces)
- ❌ Cannot change cover photos
- ✅ Can ignore persons

**Current limitation**: Face grouping management (editing clusters, removing incorrect faces) must be done on the mobile app. Desktop apps can view and name persons but cannot modify the groupings themselves.

### Web (photos.ente.com)

- ❌ Face recognition not available
- Must use mobile or desktop apps

## Privacy and Security

Face recognition in Ente maintains complete privacy:

- **On-device processing**: All face detection and grouping happens on your device
- **Encrypted face data**: Face recognition data is encrypted before syncing
- **No server access**: Ente's servers never see your photos or face data
- **Not used for training**: Your photos are never used to train AI models
- **No third parties**: No data is shared with any third party services

Your face recognition data is as private and secure as your photos themselves.

Learn more in [Security and Privacy FAQ](/photos/faq/security-and-privacy#ml-privacy).

## Works Offline

Once your photos have been indexed, face recognition works completely offline:

- Search for people without internet
- View face groupings offline
- Name and manage persons offline
- All operations happen locally on your device

The initial indexing requires downloading your photos (which is faster over WiFi), but after that face recognition works without an internet connection.

## Related FAQs

- [How do I enable face recognition?](/photos/faq/search-and-discovery#enable-face-recognition)
- [Can I merge or de-merge persons?](/photos/faq/search-and-discovery#merge-persons)
- [How can I remove an incorrectly grouped face?](/photos/faq/search-and-discovery#remove-incorrect-face)
- [How do I change the cover for a person?](/photos/faq/search-and-discovery#change-cover)
- [Can I ignore certain persons?](/photos/faq/search-and-discovery#ignore-person)
- [How well does the app handle photos of babies?](/photos/faq/search-and-discovery#babies)
- [Does face recognition work offline?](/photos/faq/search-and-discovery#ml-offline)
- [Is my face data used to train AI models?](/photos/faq/security-and-privacy#ml-privacy)
- [Why is face recognition faster on desktop?](/photos/faq/search-and-discovery#desktop-faster)
- [Indexing stuck at 100% but faces don't appear](/photos/faq/search-and-discovery#indexing-stuck-no-faces)
- [Faces not being grouped correctly](/photos/faq/search-and-discovery#faces-not-grouped-correctly)
- [Can't modify face groupings on desktop](/photos/faq/search-and-discovery#cant-modify-faces-desktop)
- [Performance issues during indexing](/photos/faq/search-and-discovery#ml-performance-issues)

## Related topics

- [Machine learning overview](/photos/features/search-and-discovery/machine-learning)
- [Magic search](/photos/features/search-and-discovery/magic-search)
- [Search and Discovery overview](/photos/features/search-and-discovery/)
- [Search and Discovery FAQ](/photos/faq/search-and-discovery)
- [Security and Privacy FAQ](/photos/faq/security-and-privacy)
