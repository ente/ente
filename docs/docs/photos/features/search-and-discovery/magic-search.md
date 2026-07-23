---
title: Magic search
description: Search your photos using natural language with Ente's on-device AI-powered magic search
---

# Magic Search

Magic search lets you find photos using natural language descriptions of their content. Using on-device AI, you can search for objects, scenes, colors, and activities without your photos or search queries ever leaving your device.

## What is Magic Search?

Magic search uses AI models (specifically CLIP - Contrastive Language-Image Pre-training) to understand the content of your photos. This enables semantic search where you can describe what you're looking for in natural language, and the app will find matching photos.

You can search for:

- **Objects**: "car", "dog", "food", "bicycle", "book"
- **Scenes**: "beach", "sunset", "mountain", "city skyline", "forest"
- **Colors**: "red flowers", "blue car", "orange sunset"
- **Activities**: "birthday cake", "swimming", "hiking", "cooking"
- **Complex queries**: "the red motorcycle next to a fountain", "dog playing in snow"

## How It Works

### On-device AI

Magic search runs entirely on your device:

1. When you enable magic search, the app downloads your photos
2. An AI model analyzes each photo locally on your device
3. The model creates a semantic understanding of what's in each photo
4. This understanding is stored as an encrypted index
5. When you search, the query is matched against the index locally

**Privacy guarantee**: Your photos, search queries, and AI-generated indexes never leave your device in unencrypted form. Ente's servers cannot see what's in your photos or what you're searching for.

### CLIP-based understanding

The AI model understands:

- What objects appear in photos
- What scenes or environments are depicted
- Colors and visual attributes
- Relationships between objects
- Activities and actions

This allows for flexible, natural language searches that go beyond simple keyword matching.

## Enabling Magic Search

Magic search is part of Ente's machine learning features. You must enable it manually (it's off by default).

**On mobile:**

Open `Settings > Machine learning`, enable **Machine learning** and/or **Local indexing**, and wait for indexing to complete.

**On desktop:**

Open `Settings > Preferences > Machine learning`, enable **Machine learning** and/or **Local indexing**, and monitor indexing progress.

> [!NOTE]
>
> Magic search is not available on photos.ente.com. You must use the mobile or desktop app.

### Initial Indexing

After enabling magic search:

- The app downloads your photos to index them locally
- Progress is shown as a percentage
- This is faster over WiFi and on desktop computers
- Once complete, you can immediately start using magic search

**Indexing tips:**

- For large libraries, enable on desktop first (faster indexing)
- Enable before importing photos to avoid downloading them twice
- Once indexed on one device, the indexes sync to other devices

Learn more about [Machine learning](/photos/features/search-and-discovery/machine-learning).

## Using Magic Search

### Simple searches

Type natural language descriptions in the search bar:

- **"sunset"** - finds photos of sunsets
- **"beach"** - finds beach photos
- **"dog"** - finds photos with dogs
- **"food"** - finds photos of meals and food
- **"car"** - finds photos containing cars

### Complex searches

Magic search understands more complex, descriptive queries:

- **"red car"** - finds photos of red-colored cars
- **"dog playing in snow"** - finds photos matching this description
- **"birthday cake with candles"** - finds relevant celebration photos
- **"mountain landscape"** - finds scenic mountain photos
- **"night city"** - finds urban nighttime photos

### Search best practices

**Be descriptive:**

- More specific queries often work better
- Try variations if the first query doesn't return what you want

**Combine terms:**

- Use multiple descriptive words: "red flower garden"
- Add color, setting, or context: "beach sunset orange sky"

**Try different phrasings:**

- If "car" doesn't work well, try "automobile" or "vehicle"
- Use common, clear terms rather than very specific jargon

**Use with other search types:**

- Combine magic search with date filters
- Search within specific albums
- Use alongside face recognition to find photos of people doing specific activities

## Search by Descriptions

Magic search works even better when combined with descriptions (captions) you've added to photos.

### Adding descriptions to photos

**On mobile and desktop:**

1. Open a photo
2. Tap the overflow menu (⋮) and select **Info** on mobile, or click the info button (i) on desktop
3. Enter your description or caption
4. Save

Your descriptions become searchable, making it easy to find photos you've documented with specific details, memories, or context.

**Example**: Add "Sarah's graduation ceremony at the park" as a description, and you can later search for any of those terms to find the photo.

Learn more in [Metadata and Editing FAQ](/photos/faq/metadata-and-editing#descriptions).

## What Content Can Be Detected

### Objects

Cars, dogs, cats, bicycles, books, phones, computers, furniture, plants, flowers, trees, food items, drinks, and many more everyday objects.

### Scenes and environments

Beach, mountain, forest, city, park, garden, indoor/outdoor settings, architectural features, natural landscapes.

### Colors and visual attributes

Basic colors (red, blue, green, etc.), lighting conditions (night, day, sunset), weather conditions.

### Activities

Eating, swimming, hiking, cooking, reading, celebrations, sports, and other common activities (detection varies by photo clarity).

### Limitations

Magic search works best with:

- Clear, well-lit photos
- Common objects and scenes
- Standard perspectives

It may struggle with:

- Very abstract or artistic photos
- Highly specific or technical subjects
- Very dark or unclear images
- Unusual angles or perspectives

## Privacy and Security

Magic search maintains complete privacy:

- **On-device processing**: All AI analysis happens on your device
- **Encrypted indexes**: Search indexes are encrypted before syncing
- **No server access**: Ente's servers never see your photos or what's in them
- **No queries sent**: Your search queries stay on your device
- **Not used for training**: Your photos are never used to train AI models
- **No third parties**: No data is shared with any third party services

Your magic search data is as private and secure as your photos themselves.

Learn more in [Security and Privacy FAQ](/photos/faq/security-and-privacy#ml-privacy).

## Works Offline

Once your photos have been indexed, magic search works completely offline:

- Search without an internet connection
- All processing happens locally
- No data sent to servers
- Instant search results

The initial indexing requires downloading your photos (which is faster over WiFi), but after that magic search works without an internet connection.

## Language Support

Magic search understands queries in multiple languages. The CLIP model has been trained on diverse linguistic data, allowing it to understand common terms in many languages.

However, English queries typically work best due to the model's training data distribution.

## Technical Details

### CLIP model

Magic search uses CLIP (Contrastive Language-Image Pre-training), an AI model developed by OpenAI that understands both images and text. This allows the model to:

- Associate natural language descriptions with visual content
- Understand semantic similarity between queries and images
- Generalize to objects and concepts it hasn't explicitly seen

### Index storage

- Indexes are stored locally on your device
- They're encrypted before being synced to other devices
- Much smaller than the original photos
- Sync automatically using the same encryption as your photos

## Combining with Other Search Features

Magic search works well alongside Ente's other search capabilities:

### With face recognition

- Search for "birthday" to find celebration photos
- Then filter by a specific person's name
- Find photos of people doing specific activities

### With date search

- Use magic search to find "beach" photos
- Then filter by "Summer 2023"
- Narrow down to specific time periods

### With album search

- Search within a specific album
- Use magic search to find particular types of photos
- Organize and find content more efficiently

### With location tags

- Tag locations like "Paris"
- Use magic search within that location for "Eiffel Tower" or "cafe"

Learn more in [Search and Discovery overview](/photos/features/search-and-discovery/).

## Related FAQs

- [What is magic search?](/photos/faq/search-and-discovery#magic-search)
- [How do I enable magic search?](/photos/faq/search-and-discovery#enable-magic-search)
- [Does magic search require internet?](/photos/faq/search-and-discovery#magic-search-offline)
- [Can I search for photos using descriptions I've added?](/photos/faq/search-and-discovery#description-search)
- [Does magic search work offline?](/photos/faq/search-and-discovery#ml-offline)
- [Is my data used to train AI models?](/photos/faq/security-and-privacy#ml-privacy)
- [Magic search not finding relevant photos](/photos/faq/search-and-discovery#magic-search-not-finding)
- [Machine learning features not working](/photos/faq/search-and-discovery#ml-features-not-working)
- [Performance issues during indexing](/photos/faq/search-and-discovery#ml-performance-issues)

## Related topics

- [Machine learning overview](/photos/features/search-and-discovery/machine-learning)
- [Face recognition](/photos/features/search-and-discovery/face-recognition)
- [Search and Discovery overview](/photos/features/search-and-discovery/)
- [Map and location features](/photos/features/search-and-discovery/map-and-location)
- [Search and Discovery FAQ](/photos/faq/search-and-discovery)
- [Security and Privacy FAQ](/photos/faq/security-and-privacy)
