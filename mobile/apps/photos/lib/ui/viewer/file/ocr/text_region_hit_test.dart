import "package:flutter/widgets.dart";
import "package:mobile_ocr/models/text_region.dart";

Offset viewportPointBeforeZoom({
  required Offset point,
  required Size viewportSize,
  required double scale,
  required Offset offset,
}) {
  assert(scale > 0 && scale.isFinite);
  final center = viewportSize.center(Offset.zero);
  return center + (point - center - offset) / scale;
}

bool isZoomedViewportPointInTextRegions({
  required Offset point,
  required Size viewportSize,
  required Size imageSize,
  required List<TextRegion> regions,
  required double scale,
  required Offset offset,
  double hitSlop = 0,
}) {
  if (scale <= 0 || !scale.isFinite) return false;
  return isViewportPointInTextRegions(
    point: viewportPointBeforeZoom(
      point: point,
      viewportSize: viewportSize,
      scale: scale,
      offset: offset,
    ),
    viewportSize: viewportSize,
    imageSize: imageSize,
    regions: regions,
    hitSlop: hitSlop / scale,
  );
}

Rect containedImageRect(Size viewportSize, Size imageSize) {
  if (viewportSize.width <= 0 ||
      viewportSize.height <= 0 ||
      imageSize.width <= 0 ||
      imageSize.height <= 0) {
    return Rect.zero;
  }

  final imageAspect = imageSize.width / imageSize.height;
  final viewportAspect = viewportSize.width / viewportSize.height;
  final double displayWidth;
  final double displayHeight;
  if (imageAspect > viewportAspect) {
    displayWidth = viewportSize.width;
    displayHeight = displayWidth / imageAspect;
  } else {
    displayHeight = viewportSize.height;
    displayWidth = displayHeight * imageAspect;
  }
  return Rect.fromLTWH(
    (viewportSize.width - displayWidth) / 2,
    (viewportSize.height - displayHeight) / 2,
    displayWidth,
    displayHeight,
  );
}

bool isViewportPointInTextRegions({
  required Offset point,
  required Size viewportSize,
  required Size imageSize,
  required List<TextRegion> regions,
  double hitSlop = 0,
}) {
  if (regions.isEmpty) return false;
  final photoRect = containedImageRect(viewportSize, imageSize);
  if (photoRect.isEmpty || !photoRect.inflate(hitSlop).contains(point)) {
    return false;
  }

  for (final region in regions) {
    final viewportPoints = region.points
        .map(
          (regionPoint) => Offset(
            photoRect.left + regionPoint.dx / imageSize.width * photoRect.width,
            photoRect.top +
                regionPoint.dy / imageSize.height * photoRect.height,
          ),
        )
        .toList(growable: false);
    if (_isPointInPaddedPolygon(point, viewportPoints, hitSlop)) {
      return true;
    }
  }
  return false;
}

bool _isPointInPaddedPolygon(
  Offset point,
  List<Offset> polygon,
  double padding,
) {
  if (polygon.length < 3) return false;

  final path = Path()..moveTo(polygon.first.dx, polygon.first.dy);
  for (final vertex in polygon.skip(1)) {
    path.lineTo(vertex.dx, vertex.dy);
  }
  path.close();
  if (path.contains(point)) return true;
  if (padding <= 0) return false;

  for (var index = 0; index < polygon.length; index++) {
    final start = polygon[index];
    final end = polygon[(index + 1) % polygon.length];
    if (_distanceToSegment(point, start, end) <= padding) return true;
  }
  return false;
}

double _distanceToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.distanceSquared;
  if (lengthSquared == 0) return (point - start).distance;

  final relative = point - start;
  final projection =
      ((relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared)
          .clamp(0.0, 1.0);
  return (point - (start + segment * projection)).distance;
}
