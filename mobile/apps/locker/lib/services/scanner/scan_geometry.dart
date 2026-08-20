import 'dart:math' as math;
import 'dart:ui';

import 'package:locker/services/scanner/scanner_models.dart';

ScanQuad lerpQuad(ScanQuad a, ScanQuad b, double t) => ScanQuad([
  for (var i = 0; i < 4; i++) Offset.lerp(a.corners[i], b.corners[i], t)!,
]);

double maxCornerDistance(ScanQuad a, ScanQuad b) {
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    final d = (a.corners[i] - b.corners[i]).distance;
    if (d > worst) worst = d;
  }
  return worst;
}

double quadArea(List<Offset> corners) {
  var doubled = 0.0;
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % corners.length];
    doubled += a.dx * b.dy - b.dx * a.dy;
  }
  return doubled.abs() / 2;
}

bool isUsableQuad(List<Offset> corners, {required double minAreaFraction}) {
  if (corners.length != 4) return false;
  final area = quadArea(corners);
  if (area < minAreaFraction) return false;
  final minCross = area * 0.02;
  var winding = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    final c = corners[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
    if (cross.abs() < minCross) return false;
    if (winding != 0 && cross.sign != winding) return false;
    winding = cross.sign;
  }
  return true;
}

ScanQuad orderClockwise(List<Offset> corners) {
  assert(corners.length == 4);
  final cx = corners.map((c) => c.dx).reduce((a, b) => a + b) / 4;
  final cy = corners.map((c) => c.dy).reduce((a, b) => a + b) / 4;
  final sorted = [...corners]
    ..sort(
      (a, b) => math
          .atan2(a.dy - cy, a.dx - cx)
          .compareTo(math.atan2(b.dy - cy, b.dx - cx)),
    );
  return ScanQuad(sorted);
}

Rect fittedRect(Size container, double aspect) {
  final containerAspect = container.width / container.height;
  final Size display = aspect > containerAspect
      ? Size(container.width, container.width / aspect)
      : Size(container.height * aspect, container.height);
  return Rect.fromLTWH(
    (container.width - display.width) / 2,
    (container.height - display.height) / 2,
    display.width,
    display.height,
  );
}

class QuadStabilizer {
  static const double maxCornerDrift = 20.0 / 256;
  static const int requiredStableFrames = 3;

  int _stableCount = 0;
  ScanQuad? _lastRawQuad;

  ScanQuad? update(ScanQuad? rawQuad) {
    final previous = _lastRawQuad;
    _lastRawQuad = rawQuad;

    if (rawQuad == null) {
      _stableCount = 0;
      return null;
    }
    if (previous == null) {
      _stableCount = 1;
      return null;
    }

    if (maxCornerDistance(previous, rawQuad) < maxCornerDrift) {
      _stableCount++;
    } else {
      _stableCount = 1;
    }

    return _stableCount >= requiredStableFrames ? rawQuad : null;
  }

  void reset() {
    _stableCount = 0;
    _lastRawQuad = null;
  }
}
