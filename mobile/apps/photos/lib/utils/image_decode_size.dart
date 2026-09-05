import 'dart:math';

import 'package:flutter/painting.dart';

const int lowMemoryImageDecodePixelLimit = 8 * 1000 * 1000;
const int defaultImageDecodePixelLimit = 16 * 1000 * 1000;

/// Returns a decode size that is sharp for the current display without
/// materializing the entire camera bitmap in memory.
///
/// Flutter decodes images to roughly four bytes per pixel. A 50 MP camera
/// image therefore needs about 200 MB even when its compressed file is only a
/// few megabytes. Two such images overlap while a [PageView] is swiped.
Size? imageDecodeSizeForDisplay({
  required int sourceWidth,
  required int sourceHeight,
  required Size viewportSize,
  required double devicePixelRatio,
  required int maxDecodedPixels,
  double zoomReserve = 2,
  BoxFit fit = BoxFit.contain,
}) {
  if (sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      viewportSize.isEmpty ||
      !viewportSize.isFinite ||
      devicePixelRatio <= 0 ||
      zoomReserve <= 0 ||
      maxDecodedPixels <= 0) {
    return null;
  }

  final sourcePixels = sourceWidth * sourceHeight;
  final widthScale = viewportSize.width / sourceWidth;
  final heightScale = viewportSize.height / sourceHeight;
  final fittedScale = fit == BoxFit.cover
      ? max(widthScale, heightScale)
      : min(widthScale, heightScale);
  final displayScale = min(1.0, fittedScale * devicePixelRatio * zoomReserve);
  final memoryScale = min(1.0, sqrt(maxDecodedPixels / sourcePixels));
  final decodeScale = min(displayScale, memoryScale);

  if (decodeScale >= 0.999) return null;
  return Size(
    max(1, (sourceWidth * decodeScale).round()).toDouble(),
    max(1, (sourceHeight * decodeScale).round()).toDouble(),
  );
}
