---
title: Detect Text (OCR)
description: Copy text from your photos on iOS and Android using on-device OCR in Ente Photos
---

# Detect Text (OCR)

Detect Text lets you pull text out of your photos without leaving Ente Photos. Recognition runs entirely on your device, so your images and the text you extract never leave your phone.

## Availability

- **Platforms**: iOS and Android mobile apps
- **Supported files**: Photos and Live Photos (videos are not supported)
- **Viewer contexts**: Available in the standard photo viewer for supported files. It is not available for Trash items or guest views.

> [!NOTE]
>
> On Android, the first scan downloads the OCR models. Keep a network connection for that download. Later scans work offline.

## Use Detect Text

**On mobile:**

1. Open a photo or screenshot in the viewer.
2. Touch and hold on the text in the photo.
3. Ente detects the text on-device and shows a text-selection overlay.
4. Drag the selection handles, or double tap a line, to highlight exactly what you need.
5. Tap **Copy** to copy the selected text, or tap **Select all** to copy everything Ente detected.
6. Tap outside the selection or return to the viewer when you are done.

After copying, the text stays on your clipboard so you can paste it into messages, notes, or other apps.

## Tips

- The first long press may take a moment while Ente checks the image and prepares the text overlay.
- Ente caches detection results, so revisiting the same photo often makes text selection feel faster.
- If text selection does not appear, make sure the original file has finished downloading and that the image contains readable text.
- Long-press text detection pairs well with [QR code detection in photos](/photos/features/utilities/qr-codes-in-photos) when screenshots or posters contain both text and QR codes.

## Limitations

Detect Text runs on demand and does not build a searchable index across your library, so searches still rely on metadata, machine learning tags, and descriptions. Magic search may occasionally surface photos with prominent text (thanks to CLIP embeddings), but it is not a dedicated "search by detected text" feature.

Not all languages are currently supported. It works well on Chinese, Japanese, English, and most languages with the Latin scripture.

## Privacy

OCR processing happens completely on-device (Vision on iOS, offline models on Android). Ente never sees your images, detected text, or selections.

## Related topics

- [Search and Discovery overview](/photos/features/search-and-discovery/)
- [Machine learning overview](/photos/features/search-and-discovery/machine-learning)
