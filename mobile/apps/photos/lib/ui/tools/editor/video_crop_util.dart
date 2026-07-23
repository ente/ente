import 'dart:ui';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:video_editor/video_editor.dart';

/// Crop calculation result
class CropCalculation {
  final int x;
  final int y;
  final int width;
  final int height;

  CropCalculation({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Create Rect from crop calculation
  Rect toRect() => Rect.fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );

  /// FFmpeg crop filter string: crop=w:h:x:y
  String toFFmpegFilter() => 'crop=$width:$height:$x:$y';
}

class VideoCropException implements Exception {
  VideoCropException(this.message);
  final String message;

  @override
  String toString() => 'VideoCropException: $message';
}

/// Helpers to derive display- and file-space crop rectangles for native export
class VideoCropUtil {
  static double _clampNormalized(double value) {
    return value.clamp(0.0, 1.0);
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Calculate the crop rectangle in display-space pixels.
  ///
  /// Returns a Rect in display-space so the native plugins can transform to file-space.
  static Rect calculateDisplaySpaceCropRect({
    required VideoEditorController controller,
  }) {
    return calculateDisplaySpaceCropRectFromData(
      minCrop: controller.minCrop,
      maxCrop: controller.maxCrop,
      videoSize: controller.video.value.size,
    );
  }

  /// Testability helper: bypasses controller and platform checks by accepting
  /// raw crop data. Only used in unit tests.
  @visibleForTesting
  static Rect calculateDisplaySpaceCropRectFromData({
    required Offset minCrop,
    required Offset maxCrop,
    required Size videoSize,
  }) {
    // Both platforms use same path - no rotation-specific logic
    double minX = _clampNormalized(minCrop.dx);
    double maxX = _clampNormalized(maxCrop.dx);
    double minY = _clampNormalized(minCrop.dy);
    double maxY = _clampNormalized(maxCrop.dy);

    if (minX > maxX) {
      final temp = minX;
      minX = maxX;
      maxX = temp;
    }
    if (minY > maxY) {
      final temp = minY;
      minY = maxY;
      maxY = temp;
    }

    // Use raw video dimensions - no special handling for rotation
    final displayWidth = videoSize.width;
    final displayHeight = videoSize.height;

    final widthNormalized = maxX - minX;
    final heightNormalized = maxY - minY;

    if (widthNormalized <= 0 || heightNormalized <= 0) {
      throw VideoCropException('Invalid crop selection: zero or negative span');
    }

    final x = minX * displayWidth;
    final y = minY * displayHeight;
    final w = widthNormalized * displayWidth;
    final h = heightNormalized * displayHeight;

    if (w <= 0 || h <= 0) {
      throw VideoCropException('Invalid crop rectangle after scaling');
    }

    return Rect.fromLTWH(x, y, w, h);
  }

  /// Convert the normalised crop selection into file-space coordinates.
  static CropCalculation calculateFileSpaceCrop({
    required VideoEditorController controller,
  }) {
    final videoSize = controller.video.value.size;
    return calculateFileSpaceCropFromData(
      minCrop: controller.minCrop,
      maxCrop: controller.maxCrop,
      videoSize: videoSize,
    );
  }

  /// Testability helper: skips controller/platform usage to make unit tests
  /// deterministic. Not for production callers.
  @visibleForTesting
  static CropCalculation calculateFileSpaceCropFromData({
    required Offset minCrop,
    required Offset maxCrop,
    required Size videoSize,
  }) {
    final displayCrop = calculateDisplaySpaceCropRectFromData(
      minCrop: minCrop,
      maxCrop: maxCrop,
      videoSize: videoSize,
    );

    // Both iOS and Android produce displayCrop in raw file dimensions,
    // so we use standard file-space crop for both
    return _calculateStandardFileSpaceCrop(videoSize, displayCrop);
  }

  static CropCalculation _calculateStandardFileSpaceCrop(
    Size videoSize,
    Rect displayCrop,
  ) {
    final minX = _clampInt(
      displayCrop.left.round(),
      0,
      videoSize.width.toInt(),
    );
    final minY = _clampInt(
      displayCrop.top.round(),
      0,
      videoSize.height.toInt(),
    );
    final maxX = _clampInt(
      displayCrop.right.round(),
      0,
      videoSize.width.toInt(),
    );
    final maxY = _clampInt(
      displayCrop.bottom.round(),
      0,
      videoSize.height.toInt(),
    );

    final w = maxX - minX;
    final h = maxY - minY;

    // Note: we round to the nearest pixel before clamping so that symmetric
    // crops retain parity after multiple transformations. This avoids repeated
    // floor/ceil adjustments that previously caused ±1px drift.
    if (w <= 0 || h <= 0) {
      throw VideoCropException('Invalid crop dimensions after normalization');
    }

    return CropCalculation(x: minX, y: minY, width: w, height: h);
  }
}
