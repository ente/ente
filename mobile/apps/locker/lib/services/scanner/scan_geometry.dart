import 'dart:math' as math;
import 'dart:typed_data';
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

Float64List? homographyMatrix(List<Offset> source, List<Offset> target) {
  assert(source.length == 4 && target.length == 4);
  final rows = List.generate(8, (_) => List.filled(9, 0.0));
  for (var i = 0; i < 4; i++) {
    final x = source[i].dx;
    final y = source[i].dy;
    final u = target[i].dx;
    final v = target[i].dy;
    rows[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    rows[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (rows[r][col].abs() > rows[pivot][col].abs()) pivot = r;
    }
    if (rows[pivot][col].abs() < 1e-9) return null;
    if (pivot != col) {
      final swap = rows[pivot];
      rows[pivot] = rows[col];
      rows[col] = swap;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final factor = rows[r][col] / rows[col][col];
      if (factor == 0) continue;
      for (var c = col; c < 9; c++) {
        rows[r][c] -= factor * rows[col][c];
      }
    }
  }
  final h = [for (var i = 0; i < 8; i++) rows[i][8] / rows[i][i], 1.0];
  return Float64List.fromList([
    h[0], h[3], 0, h[6], //
    h[1], h[4], 0, h[7], //
    0, 0, 1, 0, //
    h[2], h[5], 0, h[8], //
  ]);
}
