import "dart:math";

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

abstract final class EnvelopeShape {
  static const width = 390.0;
  static const backTop = 468.0;
  static const dipInset = 124.0;
  static const dipY = 578.0;
  static const apexY = 540.0;
  static const bottom = 920.0;
  static const maxBleed = 60.0;

  static double bleedFor(Size screen) {
    if (screen.isEmpty) return 0;
    return min(
      RewindStage.originFor(screen).dx / RewindStage.scaleFor(screen),
      maxBleed,
    );
  }
}

class _Edges {
  _Edges(double bleed)
    : left = -bleed - _overhang,
      right = EnvelopeShape.width + bleed + _overhang,
      sideTop = _sideTop - bleed * _sideSlope,
      seamY = _seamY + bleed * _seamSlope;

  static const _overhang = 8.0;
  static const _sideTop = 505.0;
  static const _seamY = 664.0;
  static const _sideSlope =
      (EnvelopeShape.dipY - _sideTop) / (EnvelopeShape.dipInset + _overhang);
  static const _seamSlope =
      (_seamY - EnvelopeShape.dipY) / (EnvelopeShape.dipInset + _overhang);

  final double left;
  final double right;
  final double sideTop;
  final double seamY;

  RRect get back => RRect.fromLTRBAndCorners(
    left,
    EnvelopeShape.backTop,
    right,
    EnvelopeShape.bottom,
    topLeft: const Radius.circular(18),
    topRight: const Radius.circular(18),
  );
}

class EnvelopeBackPainter extends CustomPainter {
  const EnvelopeBackPainter({required this.bleed});

  static const _stripe = 34.0;
  static const _lining = [RewindColors.hotPink, RewindColors.blue];

  final double bleed;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = _Edges(bleed).back;
    canvas.drawRRect(outer, Paint()..color = RewindColors.cream);
    canvas
      ..save()
      ..clipRRect(outer.deflate(9));
    for (var i = -6; i < 18; i++) {
      final x = i * _stripe;
      canvas.drawPath(
        Path()
          ..moveTo(x, EnvelopeShape.backTop)
          ..lineTo(x + _stripe, EnvelopeShape.backTop)
          ..lineTo(x + _stripe + 120, EnvelopeShape.backTop + 160)
          ..lineTo(x + 120, EnvelopeShape.backTop + 160)
          ..close(),
        Paint()..color = _lining[i.abs() % _lining.length],
      );
    }
    canvas
      ..restore()
      ..drawRRect(
        outer,
        Paint()
          ..color = RewindColors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(EnvelopeBackPainter oldDelegate) =>
      oldDelegate.bleed != bleed;
}

class EnvelopeFrontPainter extends CustomPainter {
  const EnvelopeFrontPainter({required this.bleed});

  static const _dipLeft = Offset(EnvelopeShape.dipInset, EnvelopeShape.dipY);
  static const _dipRight = Offset(
    EnvelopeShape.width - EnvelopeShape.dipInset,
    EnvelopeShape.dipY,
  );
  static const _apex = Offset(EnvelopeShape.width / 2, EnvelopeShape.apexY);

  final double bleed;

  static Path _silhouette(_Edges edges) => Path()
    ..moveTo(edges.left, edges.sideTop)
    ..lineTo(_dipLeft.dx, _dipLeft.dy)
    ..lineTo(_apex.dx, _apex.dy)
    ..lineTo(_dipRight.dx, _dipRight.dy)
    ..lineTo(edges.right, edges.sideTop)
    ..lineTo(edges.right, EnvelopeShape.bottom)
    ..lineTo(edges.left, EnvelopeShape.bottom)
    ..close();

  @override
  bool hitTest(Offset position) {
    final edges = _Edges(bleed);
    return edges.back.contains(position) &&
        _silhouette(edges).contains(position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final edges = _Edges(bleed);
    final sideLeft = Offset(edges.left, edges.sideTop);
    final sideRight = Offset(edges.right, edges.sideTop);
    final seamLeft = Offset(edges.left, edges.seamY);
    final seamRight = Offset(edges.right, edges.seamY);
    canvas.clipRRect(edges.back);
    final silhouette = _silhouette(edges);
    canvas
      ..drawPath(
        silhouette.shift(const Offset(0, -5)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      )
      ..drawPath(silhouette, Paint()..color = const Color(0xFFF7E8C9))
      ..drawPath(
        Path()
          ..moveTo(_dipLeft.dx, _dipLeft.dy)
          ..lineTo(_apex.dx, _apex.dy)
          ..lineTo(_dipRight.dx, _dipRight.dy)
          ..lineTo(seamRight.dx, seamRight.dy)
          ..lineTo(edges.right, EnvelopeShape.bottom)
          ..lineTo(edges.left, EnvelopeShape.bottom)
          ..lineTo(seamLeft.dx, seamLeft.dy)
          ..close(),
        Paint()..color = const Color(0xFFFFF5E2),
      );
    final seam = Paint()
      ..color = const Color(0xFFDCC59B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(_dipLeft, seamLeft, seam)
      ..drawLine(_dipRight, seamRight, seam)
      ..drawPath(
        Path()
          ..moveTo(sideLeft.dx, sideLeft.dy)
          ..lineTo(_dipLeft.dx, _dipLeft.dy)
          ..lineTo(_apex.dx, _apex.dy)
          ..lineTo(_dipRight.dx, _dipRight.dy)
          ..lineTo(sideRight.dx, sideRight.dy),
        Paint()
          ..color = RewindColors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(EnvelopeFrontPainter oldDelegate) =>
      oldDelegate.bleed != bleed;
}

class EnvelopePhoto extends StatelessWidget {
  const EnvelopePhoto({required this.photo, required this.size, super.key});

  final EnteFile photo;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: RewindColors.photoPaper,
        border: Border.all(color: RewindColors.outline, width: 2.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), offset: Offset(3, 5)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: RewindPhoto(photo),
      ),
    );
  }
}
