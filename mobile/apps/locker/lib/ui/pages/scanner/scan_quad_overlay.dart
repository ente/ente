import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:locker/services/scanner/scan_geometry.dart';
import 'package:locker/services/scanner/scanner_models.dart';

class ScanQuadOverlay extends StatefulWidget {
  const ScanQuadOverlay({
    super.key,
    required this.quad,
    required this.color,
    this.armingProgress = 0,
  });

  static const double _smoothing = 0.15;

  static const double _settled = 0.05 / 256;

  final ScanQuad? quad;
  final Color color;
  final double armingProgress;

  @override
  State<ScanQuadOverlay> createState() => _ScanQuadOverlayState();
}

class _ScanQuadOverlayState extends State<ScanQuadOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  ScanQuad? _displayed;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onFrame(Duration _) {
    final target = widget.quad;
    if (target == null) {
      if (_displayed != null) setState(() => _displayed = null);
      return;
    }
    final current = _displayed;
    if (current == null) {
      setState(() => _displayed = target);
      return;
    }
    if (maxCornerDistance(current, target) <= ScanQuadOverlay._settled) return;
    setState(
      () => _displayed = lerpQuad(current, target, ScanQuadOverlay._smoothing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _QuadPainter(
          quad: _displayed,
          color: widget.color,
          armingProgress: widget.armingProgress,
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter({
    required this.quad,
    required this.color,
    required this.armingProgress,
  });

  static const _armedTint = 0.45;

  final ScanQuad? quad;
  final Color color;
  final double armingProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final source = quad;
    if (source == null || size.isEmpty) return;
    final points = [
      for (final c in source.corners)
        Offset(c.dx * size.width, c.dy * size.height),
    ];
    final path = Path()..addPolygon(points, true);
    final progress = armingProgress.clamp(0.0, 1.0);
    final lit = Color.lerp(color, Colors.white, _armedTint)!;
    if (progress > 0) {
      canvas
        ..drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.35 + 0.4 * progress)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 18 + 18 * progress
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              14 + 16 * progress,
            ),
        )
        ..drawPath(
          path,
          Paint()
            ..color = lit.withValues(alpha: 0.45 + 0.55 * progress)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7 + 5 * progress
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 4 * progress),
        );
    }
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      )
      ..drawPath(
        path,
        Paint()
          ..color = Color.lerp(color, lit, progress)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.quad != quad ||
      oldDelegate.color != color ||
      oldDelegate.armingProgress != armingProgress;
}
