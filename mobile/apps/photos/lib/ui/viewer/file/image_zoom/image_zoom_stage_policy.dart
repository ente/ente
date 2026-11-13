import "package:flutter/foundation.dart";

const double _kZoomStageEpsilon = 0.001;

enum ImageZoomStage { initial, covering, originalSize, gesture }

@immutable
final class ImageZoomStagePolicy {
  final double initialScale;
  final double coverScale;
  final double originalScale;
  final double maxScale;

  const ImageZoomStagePolicy({
    required this.initialScale,
    required this.coverScale,
    required this.originalScale,
    required this.maxScale,
  });

  double targetScale(ImageZoomStage stage) {
    final scale = switch (stage) {
      ImageZoomStage.initial || ImageZoomStage.gesture => initialScale,
      ImageZoomStage.covering => coverScale,
      ImageZoomStage.originalSize => originalScale,
    };
    return scale.clamp(initialScale, maxScale);
  }

  ImageZoomStage? nextDoubleTapStage({
    required ImageZoomStage currentStage,
    required double currentScale,
  }) {
    if (currentStage == ImageZoomStage.gesture) {
      return ImageZoomStage.initial;
    }

    var candidate = currentStage;
    for (var i = 0; i < 3; i++) {
      candidate = switch (candidate) {
        ImageZoomStage.initial => ImageZoomStage.covering,
        ImageZoomStage.covering => ImageZoomStage.originalSize,
        ImageZoomStage.originalSize ||
        ImageZoomStage.gesture => ImageZoomStage.initial,
      };
      if ((targetScale(candidate) - currentScale).abs() > _kZoomStageEpsilon) {
        return candidate;
      }
    }
    return null;
  }
}
