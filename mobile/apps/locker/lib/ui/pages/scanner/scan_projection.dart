import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:locker/services/scanner/scanner_models.dart';

class ScanProjection {
  static Rect? fittedRect(Size viewport, double aspectRatio) {
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.isEmpty ||
        !aspectRatio.isFinite ||
        aspectRatio <= 0) {
      return null;
    }
    final width = math.min(viewport.width, viewport.height * aspectRatio);
    final height = width / aspectRatio;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return null;
    }
    return Rect.fromLTWH(
      (viewport.width - width) / 2,
      (viewport.height - height) / 2,
      width,
      height,
    );
  }

  static Float64List? projectiveTransform(
    List<Offset> source,
    List<Offset> destination,
  ) {
    final from = _Plane.tryCreate(source);
    final to = _Plane.tryCreate(destination);
    if (from == null || to == null) return null;
    final equations = <List<double>>[];
    for (var i = 0; i < 4; i++) {
      final a = from.points[i];
      final b = to.points[i];
      equations
        ..add([a.dx, a.dy, 1, 0, 0, 0, -b.dx * a.dx, -b.dx * a.dy, b.dx])
        ..add([0, 0, 0, a.dx, a.dy, 1, -b.dy * a.dx, -b.dy * a.dy, b.dy]);
    }
    const tolerance = 4096 * 2.220446049250313e-16;
    for (var column = 0; column < 8; column++) {
      var pivot = column;
      for (var row = column + 1; row < 8; row++) {
        if (equations[row][column].abs() > equations[pivot][column].abs()) {
          pivot = row;
        }
      }
      final divisor = equations[pivot][column];
      if (!divisor.isFinite || divisor.abs() <= tolerance) return null;
      final swapped = equations[column];
      equations[column] = equations[pivot];
      equations[pivot] = swapped;
      for (var j = column; j <= 8; j++) {
        equations[column][j] /= divisor;
      }
      for (var row = 0; row < 8; row++) {
        if (row == column) continue;
        final factor = equations[row][column];
        for (var j = column; j <= 8; j++) {
          equations[row][j] -= factor * equations[column][j];
        }
      }
    }
    final normalized = [for (final row in equations) row[8], 1.0];
    var sign = 0.0;
    for (var i = 0; i < 4; i++) {
      final point = from.points[i];
      final denominator =
          normalized[6] * point.dx + normalized[7] * point.dy + normalized[8];
      if (!denominator.isFinite || denominator.abs() <= tolerance) return null;
      if (sign != 0 && sign != denominator.sign) return null;
      sign = denominator.sign;
      final projected = Offset(
        (normalized[0] * point.dx + normalized[1] * point.dy + normalized[2]) /
            denominator,
        (normalized[3] * point.dx + normalized[4] * point.dy + normalized[5]) /
            denominator,
      );
      if (!projected.isFinite ||
          (projected - to.points[i]).distance > math.sqrt(tolerance)) {
        return null;
      }
    }
    final matrix = _multiply(
      [to.scale, 0, to.center.dx, 0, to.scale, to.center.dy, 0, 0, 1],
      _multiply(normalized, [
        1 / from.scale,
        0,
        -from.center.dx / from.scale,
        0,
        1 / from.scale,
        -from.center.dy / from.scale,
        0,
        0,
        1,
      ]),
    );
    if (matrix.any((value) => !value.isFinite)) return null;
    return Float64List.fromList([
      matrix[0],
      matrix[3],
      0,
      matrix[6],
      matrix[1],
      matrix[4],
      0,
      matrix[7],
      0,
      0,
      1,
      0,
      matrix[2],
      matrix[5],
      0,
      matrix[8],
    ]);
  }

  static List<double> _multiply(List<double> a, List<double> b) => [
    for (var row = 0; row < 3; row++)
      for (var column = 0; column < 3; column++)
        a[row * 3] * b[column] +
            a[row * 3 + 1] * b[3 + column] +
            a[row * 3 + 2] * b[6 + column],
  ];
}

class _Plane {
  const _Plane(this.points, this.center, this.scale);

  final List<Offset> points;
  final Offset center;
  final double scale;

  static _Plane? tryCreate(List<Offset> points) {
    if (points.length != 4 || points.any((point) => !point.isFinite)) {
      return null;
    }
    final center = points.reduce((a, b) => a + b) / 4;
    var scale = 0.0;
    for (final point in points) {
      scale = math.max(scale, (point - center).distance);
    }
    if (!center.isFinite || !scale.isFinite || scale <= 0) return null;
    final normalized = [for (final point in points) (point - center) / scale];
    if (ScanQuad.tryFromOrdered(normalized) == null &&
        ScanQuad.tryFromOrdered(normalized.reversed.toList()) == null) {
      return null;
    }
    return _Plane(normalized, center, scale);
  }
}
