---
title: Map and Location
description: View photos on a map and organize them with custom location tags in Ente Photos
---

# Map and Location

Ente provides two complementary ways to explore and organize your photos by location: **Map view** for visualizing photos based on GPS coordinates, and **Location tags** for creating custom location labels.

## Map View

Map view lets you explore your photos on an interactive map based on the GPS location data embedded in your photos.

### How it works

Photos that have GPS coordinates in their metadata will automatically appear on the map. You can:

- See all your photos on a global map
- Zoom into specific locations
- View photos from specific albums on the map
- Explore where your photos were taken around the world

> [!NOTE]
>
> Only photos with GPS location data in their metadata will appear on the map. Photos without location data (like screenshots, downloaded images, or photos taken with location services disabled) won't be shown.

### Enable map view

The map feature can be enabled or disabled in your app settings.

**On mobile:**

Open `Settings` and use the toggle switch to turn the map feature on or off.

**On desktop:**

Open `Settings > Preferences > Advanced > Map` and toggle the map settings on or off.

### View photos on the map

**On mobile:**

1. Tap the search icon at the bottom right
2. Tap the globe icon (Your map) in the location section
3. Explore your photos on the map

**On web/desktop**

1. Click the globe icon in the top right of the header
2. Browse your photos on the map

**View a specific album on the map:**

1. Open the album
2. Tap the three dots in the top right corner
3. Select **Map**
4. View only that album's photos on the map

### Privacy

Your location data is end-to-end encrypted, just like your photos. When you view photos on the map:

- Map view uses encrypted location coordinates stored with your photos
- Ente's servers cannot see where your photos were taken
- All location-based searches happen locally on your device

Learn more in [Security and Privacy FAQ](/photos/faq/security-and-privacy).

## Location Tags

Location tags let you create custom location labels to organize and search for photos by place, regardless of whether they have GPS data.

### What are location tags?

Location tags are custom labels you create to organize photos by location. Unlike map view (which relies on GPS data), location tags let you:

- Create tags like "Home", "Office", "Paris Trip"
- Define a center point and radius for each location
- Find photos within specific areas
- Tag photos that don't have GPS coordinates

### How location tags differ from map view

**Map view:**

- Shows photos based on GPS coordinates embedded in photo metadata
- Displays exact locations where photos were taken
- Only shows photos that have location data

**Location tags:**

- Custom labels you create and manage
- You define the center point and radius
- Can include photos without GPS data
- Useful for organizing photos from frequent places

**When to use each:**

- Use **map view** to explore where your photos were taken geographically
- Use **location tags** to organize photos by meaningful places (home, work, vacation destinations)

### Create location tags

**From a photo:**

1. Open a photo
2. Tap the overflow menu (⋮) and select **Info**
3. Select **Add Location**
4. Enter the location name and define a radius

**From the search tab:**

1. Open the search tab
2. Click **Add new** in the location tags section
3. Select a photo as the center point for the location tag
4. Enter the location name and define a radius

The app will automatically cluster photos falling within that radius under your specified location tag.

### Benefits of location tags

- **Privacy-focused**: All searches run locally on your device
- **Encrypted**: Location tags are stored end-to-end encrypted
- **Flexible**: Tag photos with or without GPS data
- **Organized**: Easy to find photos from frequent places like home, office, and vacation spots
- **Searchable**: Quickly find all photos from a tagged location

## Common Questions

### Why don't all my photos appear on the map?

Photos appear on the map only if they have GPS location data in their metadata. Photos may not appear if:

- Location services were disabled when the photo was taken
- Location data was stripped during export/transfer
- The photo is a screenshot or downloaded image
- The device's GPS was disabled

You can manually add location data to photos. See [Metadata and Editing FAQ](/photos/faq/metadata-and-editing#add-location).

### Can I add photos to the map that don't have GPS data?

The map view itself only shows photos with GPS data. However, you can use **location tags** to organize photos by location regardless of whether they have GPS coordinates. Create a location tag for a specific place, and you can include any photos in that tag.

### Is my location data sent to Ente servers?

No. Your location data is end-to-end encrypted, just like your photos. Ente's servers cannot see:

- Where your photos were taken
- Your location tags
- Map view usage

All location-based searches happen locally on your device.

### Can I view all my albums on the map at once?

Yes! By default, the map view shows photos from all your albums. You can also view a specific album on the map by opening that album and selecting "Map" from the menu.

## Related FAQs

- [Why doesn't the map show all my photos?](/photos/faq/search-and-discovery#missing-photos)
- [Is my location data sent to Ente servers?](/photos/faq/search-and-discovery#privacy)
- [Can I view all albums on the map at once?](/photos/faq/search-and-discovery#all-albums)
- [How are location tags different from map view?](/photos/faq/search-and-discovery#location-tags-vs-map)
- [Are my location tags encrypted?](/photos/faq/search-and-discovery#location-tags-encryption)

## Related topics

- [Search and Discovery overview](/photos/features/search-and-discovery/)
- [Machine learning](/photos/features/search-and-discovery/machine-learning)
- [Search and Discovery FAQ](/photos/faq/search-and-discovery)
- [Security and Privacy FAQ](/photos/faq/security-and-privacy)
