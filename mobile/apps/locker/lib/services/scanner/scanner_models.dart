import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

enum ScanColorMode { color, grayscale }

class ScanQuad {
  ScanQuad._(List<Offset> corners) : corners = List.unmodifiable(corners);

  factory ScanQuad(List<Offset> corners) {
    final quad = tryFromOrdered(corners);
    if (quad == null) {
      throw ArgumentError.value(corners, 'corners', 'Expected a convex quad');
    }
    return quad;
  }

  final List<Offset> corners;

  factory ScanQuad.fullFrame() => ScanQuad._(const [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 1),
    Offset(0, 1),
  ]);

  static ScanQuad? tryFromOrdered(List<Offset> corners) {
    if (corners.length != 4 || corners.any((point) => !point.isFinite)) {
      return null;
    }
    var extent = 0.0;
    for (final a in corners) {
      for (final b in corners) {
        extent = math.max(extent, (a - b).distanceSquared);
      }
    }
    if (!extent.isFinite || extent <= 0) return null;
    final tolerance = extent * 128 * 2.220446049250313e-16;
    for (var i = 0; i < 4; i++) {
      final a = corners[(i + 1) % 4] - corners[i];
      final b = corners[(i + 2) % 4] - corners[(i + 1) % 4];
      final cross = a.dx * b.dy - a.dy * b.dx;
      if (!cross.isFinite || cross <= tolerance) return null;
    }
    final quad = ScanQuad._(corners);
    return quad.area.isFinite && quad.area > tolerance ? quad : null;
  }

  static ScanQuad? tryFromUnordered(List<Offset> corners) {
    if (corners.length != 4 || corners.any((point) => !point.isFinite)) {
      return null;
    }
    final center = corners.reduce((a, b) => a + b) / 4;
    if (!center.isFinite) return null;
    final sorted = [...corners]
      ..sort((a, b) {
        final aAngle = math.atan2(a.dy - center.dy, a.dx - center.dx);
        final bAngle = math.atan2(b.dy - center.dy, b.dx - center.dx);
        return aAngle.compareTo(bAngle);
      });
    var start = 0;
    for (var i = 1; i < 4; i++) {
      final candidate = sorted[i];
      final current = sorted[start];
      final score = (candidate.dx + candidate.dy).compareTo(
        current.dx + current.dy,
      );
      if (score < 0 ||
          (score == 0 &&
              (candidate.dx < current.dx ||
                  (candidate.dx == current.dx && candidate.dy < current.dy)))) {
        start = i;
      }
    }
    return tryFromOrdered([
      for (var i = 0; i < 4; i++) sorted[(start + i) % 4],
    ]);
  }

  factory ScanQuad.fromSourcePixels(List<Offset> corners, Size sourceSize) {
    _validateSize(sourceSize);
    return ScanQuad([
      for (final corner in corners)
        Offset(corner.dx / sourceSize.width, corner.dy / sourceSize.height),
    ]);
  }

  List<Offset> toSourcePixels(Size sourceSize) {
    _validateSize(sourceSize);
    final result = [
      for (final corner in corners)
        Offset(corner.dx * sourceSize.width, corner.dy * sourceSize.height),
    ];
    if (result.any((point) => !point.isFinite)) {
      throw ArgumentError.value(sourceSize, 'sourceSize');
    }
    return result;
  }

  double get area {
    final a = corners[1] - corners[0];
    final b = corners[2] - corners[0];
    final c = corners[3] - corners[0];
    return (a.dx * b.dy - a.dy * b.dx + b.dx * c.dy - b.dy * c.dx) / 2;
  }

  double maxCornerDistanceTo(ScanQuad other) {
    var distance = 0.0;
    for (var i = 0; i < 4; i++) {
      distance = math.max(distance, (corners[i] - other.corners[i]).distance);
    }
    return distance;
  }

  double relativeMotionTo(ScanQuad other) =>
      maxCornerDistanceTo(other) / math.sqrt(math.min(area, other.area));

  ScanQuad alignedTo(ScanQuad reference) {
    var best = this;
    var distance = maxCornerDistanceTo(reference);
    for (var shift = 1; shift < 4; shift++) {
      final candidate = ScanQuad._([
        for (var i = 0; i < 4; i++) corners[(i + shift) % 4],
      ]);
      final candidateDistance = candidate.maxCornerDistanceTo(reference);
      if (candidateDistance < distance) {
        best = candidate;
        distance = candidateDistance;
      }
    }
    return best;
  }

  ScanQuad interpolateTo(ScanQuad other, double fraction) {
    if (!fraction.isFinite || fraction < 0 || fraction > 1) {
      throw ArgumentError.value(fraction, 'fraction');
    }
    final aligned = other.alignedTo(this);
    return tryFromOrdered([
          for (var i = 0; i < 4; i++)
            Offset.lerp(corners[i], aligned.corners[i], fraction)!,
        ]) ??
        aligned;
  }

  ScanQuad rotatedClockwise(int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(degrees, 'degrees', 'Expected quarter turns');
    }
    var result = this;
    for (var turn = 0; turn < (degrees ~/ 90) % 4; turn++) {
      result = ScanQuad._([
        for (var i = 0; i < 4; i++)
          Offset(
            1 - result.corners[(i + 3) % 4].dy,
            result.corners[(i + 3) % 4].dx,
          ),
      ]);
    }
    return result;
  }

  static void _validateSize(Size size) {
    if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) {
      throw ArgumentError.value(size, 'sourceSize');
    }
  }
}

class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.sourceJpeg,
    required this.processedJpeg,
    required this.quad,
    required this.rotationDegrees,
    required this.resolvedColorMode,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
  });

  final String id;

  final File sourceJpeg;

  final File processedJpeg;

  final ScanQuad quad;

  final int rotationDegrees;

  final ScanColorMode resolvedColorMode;

  final int sourceWidth;
  final int sourceHeight;

  final int width;
  final int height;

  ScannedPage copyWith({
    File? processedJpeg,
    ScanQuad? quad,
    int? rotationDegrees,
    ScanColorMode? resolvedColorMode,
    int? width,
    int? height,
  }) => ScannedPage(
    id: id,
    sourceJpeg: sourceJpeg,
    processedJpeg: processedJpeg ?? this.processedJpeg,
    quad: quad ?? this.quad,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    resolvedColorMode: resolvedColorMode ?? this.resolvedColorMode,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    width: width ?? this.width,
    height: height ?? this.height,
  );
}
