# Updating the iOS app icon

The iOS app icon is based on a 1024×1024 transparent foreground image centered on a square canvas. From this we create three assets with differing backgrounds and add them to `AppIcon.appiconset`.

## Steps

1. Open the transparent source PNG.
2. Ensure the foreground is centered on a 1024×1024 canvas. If the source is a different size, rescale to 1024×1024 first without adding padding.
3. Export three variants:
   - **Any**: `IconOGAny.png` — #FFEEDD background
   - **Dark**: `IconOGDark.png` — transparent background (so the system dark gradient can show)
   - **Tinted**: `IconOGTinted.png` — white background (so tinting behaves correctly)
4. Replace the corresponding files in [`Ensu/Assets.xcassets/AppIcon.appiconset/`](../Ensu/Assets.xcassets/AppIcon.appiconset/).
5. Rebuild the app in Xcode to refresh the asset catalog.
