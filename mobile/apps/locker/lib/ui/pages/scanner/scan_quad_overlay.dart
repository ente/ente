import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:locker/services/scanner/scan_geometry.dart';
import 'package:locker/services/scanner/scanner_models.dart';

class ScanQuadOverlay extends StatefulWidget {
  const ScanQuadOverlay({super.key, required this.quad, required this.color});

  static const double _smoothing = 0.15;

  final ScanQuad? quad;
  final Color color;

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
    final next = current == null
        ? target
        : lerpQuad(current, target, ScanQuadOverlay._smoothing);
    setState(() => _displayed = next);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _QuadPainter(quad: _displayed, color: widget.color),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter({required this.quad, required this.color});

  final ScanQuad? quad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final source = quad;
    if (source == null || size.isEmpty) return;
    final points = [
      for (final c in source.corners)
        Offset(
          c.dx / ScanQuad.maskSide * size.width,
          c.dy / ScanQuad.maskSide * size.height,
        ),
    ];
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.color != color;
}
