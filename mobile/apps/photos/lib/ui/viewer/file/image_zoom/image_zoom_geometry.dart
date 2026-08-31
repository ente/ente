import "dart:math" as math;

import "package:flutter/widgets.dart";

const double _imageZoomGeometryEpsilon = 0.001;

@immutable
final class ImageZoomGeometry {
  final Size viewportSize;
  final Size fittedImageSize;
  final double initialScale;
  final double coverScale;
  final double originalScale;
  final double maxScale;

  const ImageZoomGeometry._({
    required this.viewportSize,
    required this.fittedImageSize,
    required this.initialScale,
    required this.coverScale,
    required this.originalScale,
    required this.maxScale,
  });

  static ImageZoomGeometry? calculate({
    required Size viewportSize,
    required Size imageSize,
    required BoxFit initialFit,
    required double maxScaleOverCover,
  }) {
    assert(initialFit == BoxFit.contain || initialFit == BoxFit.cover);
    assert(maxScaleOverCover > 0);

    final fittedImageSize = applyBoxFit(
      BoxFit.contain,
      imageSize,
      viewportSize,
    ).destination;
    if (fittedImageSize.isEmpty) return null;

    final coverScale = math.max(
      viewportSize.width / fittedImageSize.width,
      viewportSize.height / fittedImageSize.height,
    );
    final initialScale = initialFit == BoxFit.cover ? coverScale : 1.0;
    final originalScale = math.max(
      imageSize.width / fittedImageSize.width,
      imageSize.height / fittedImageSize.height,
    );
    final maxScale = maxScaleOverCover.isInfinite
        ? double.infinity
        : math.max(initialScale, coverScale * maxScaleOverCover);

    return ImageZoomGeometry._(
      viewportSize: viewportSize,
      fittedImageSize: fittedImageSize,
      initialScale: initialScale,
      coverScale: coverScale,
      originalScale: originalScale,
      maxScale: maxScale,
    );
  }

  Rect get fittedImageRect =>
      Alignment.center.inscribe(fittedImageSize, Offset.zero & viewportSize);

  Offset get viewportCenter => viewportSize.center(Offset.zero);

  bool coordinatesMatch(ImageZoomGeometry other) =>
      _sizesNearlyEqual(viewportSize, other.viewportSize) &&
      _sizesNearlyEqual(fittedImageSize, other.fittedImageSize) &&
      (initialScale - other.initialScale).abs() <= _imageZoomGeometryEpsilon;

  bool hasSameConfiguration(ImageZoomGeometry other) =>
      viewportSize == other.viewportSize &&
      fittedImageSize == other.fittedImageSize &&
      initialScale == other.initialScale &&
      coverScale == other.coverScale &&
      originalScale == other.originalScale &&
      maxScale == other.maxScale;

  double clampScale(double scale) => scale.clamp(initialScale, maxScale);

  Matrix4 matrixForScaleAndOffset(double scale, Offset offset) =>
      matrixForScaleAndTranslation(
        scale,
        offset - viewportCenter * (scale - 1.0),
      );

  Matrix4 matrixForScaleAndTranslation(double scale, Offset translation) =>
      Matrix4.identity()
        ..translateByDouble(translation.dx, translation.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);

  Matrix4 matrixForFocalPoint(
    Matrix4 currentMatrix,
    Offset viewportPoint,
    double targetScale,
  ) {
    final sceneFocus = scenePoint(currentMatrix, viewportPoint);
    return sanitize(
      matrixForScaleAndTranslation(
        targetScale,
        viewportCenter - sceneFocus * targetScale,
      ),
    );
  }

  Offset scenePoint(Matrix4 matrix, Offset viewportPoint) {
    final inverse = Matrix4.tryInvert(matrix);
    return inverse == null
        ? viewportPoint
        : MatrixUtils.transformPoint(inverse, viewportPoint);
  }

  ImageZoomMatrixState describe(Matrix4 matrix) {
    final absoluteScale = matrix.getMaxScaleOnAxis();
    final relativeScale = absoluteScale / initialScale;
    final translation = Offset(matrix.storage[12], matrix.storage[13]);
    // Convert top-left matrix translation to the center-relative offset used
    // by OCR and the rest of the photo viewer.
    final semanticOffset = translation + viewportCenter * (absoluteScale - 1.0);
    final isInitial =
        (relativeScale - 1.0).abs() <= _imageZoomGeometryEpsilon &&
        semanticOffset.distanceSquared <=
            _imageZoomGeometryEpsilon * _imageZoomGeometryEpsilon;
    return ImageZoomMatrixState(
      absoluteScale: absoluteScale,
      relativeScale: relativeScale,
      semanticOffset: semanticOffset,
      isInitial: isInitial,
    );
  }

  Matrix4 sanitize(Matrix4 matrix) {
    var scale = matrix.getMaxScaleOnAxis();
    if (!scale.isFinite || scale <= 0) scale = initialScale;
    scale = clampScale(scale);

    var translation = Offset(matrix.storage[12], matrix.storage[13]);
    if (!translation.dx.isFinite || !translation.dy.isFinite) {
      translation = -(viewportCenter * (scale - 1.0));
    }
    var offset = translation + viewportCenter * (scale - 1.0);
    final maxOffsetX = math.max(
      0.0,
      (fittedImageSize.width * scale - viewportSize.width) / 2,
    );
    final maxOffsetY = math.max(
      0.0,
      (fittedImageSize.height * scale - viewportSize.height) / 2,
    );
    offset = Offset(
      offset.dx.clamp(-maxOffsetX, maxOffsetX),
      offset.dy.clamp(-maxOffsetY, maxOffsetY),
    );
    translation = offset - viewportCenter * (scale - 1.0);
    return matrixForScaleAndTranslation(scale, translation);
  }
}

@immutable
final class ImageZoomMatrixState {
  final double absoluteScale;
  final double relativeScale;
  final Offset semanticOffset;
  final bool isInitial;

  const ImageZoomMatrixState({
    required this.absoluteScale,
    required this.relativeScale,
    required this.semanticOffset,
    required this.isInitial,
  });
}

@immutable
final class ImageZoomRebase {
  final bool wasInitial;
  final double relativeScale;
  final Offset normalizedFocus;

  const ImageZoomRebase._({
    required this.wasInitial,
    required this.relativeScale,
    required this.normalizedFocus,
  });

  static ImageZoomRebase capture(ImageZoomGeometry geometry, Matrix4 matrix) {
    final state = geometry.describe(matrix);
    final sceneCenter = geometry.scenePoint(matrix, geometry.viewportCenter);
    final imageRect = geometry.fittedImageRect;
    return ImageZoomRebase._(
      wasInitial: state.isInitial,
      relativeScale: state.relativeScale,
      normalizedFocus: Offset(
        (sceneCenter.dx - imageRect.left) / imageRect.width,
        (sceneCenter.dy - imageRect.top) / imageRect.height,
      ),
    );
  }

  Matrix4 resolve(ImageZoomGeometry geometry) {
    if (wasInitial) {
      return geometry.matrixForScaleAndOffset(
        geometry.initialScale,
        Offset.zero,
      );
    }
    final targetScale = geometry.clampScale(
      geometry.initialScale * relativeScale,
    );
    final imageRect = geometry.fittedImageRect;
    final sceneFocus = Offset(
      imageRect.left + normalizedFocus.dx * imageRect.width,
      imageRect.top + normalizedFocus.dy * imageRect.height,
    );
    return geometry.sanitize(
      geometry.matrixForScaleAndTranslation(
        targetScale,
        geometry.viewportCenter - sceneFocus * targetScale,
      ),
    );
  }
}

bool _sizesNearlyEqual(Size first, Size second) =>
    (first.width - second.width).abs() <= _imageZoomGeometryEpsilon &&
    (first.height - second.height).abs() <= _imageZoomGeometryEpsilon;
