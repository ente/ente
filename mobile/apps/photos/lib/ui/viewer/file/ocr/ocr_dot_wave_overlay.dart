import "package:flutter/material.dart";

/// White dot grid that pulses in a radial wave from center outward.
class OcrDotWaveOverlay extends StatefulWidget {
  final Color backgroundColor;
  final Color dotColor;

  const OcrDotWaveOverlay({
    super.key,
    this.backgroundColor = const Color(0x66000000),
    this.dotColor = Colors.white,
  });

  @override
  State<OcrDotWaveOverlay> createState() => _OcrDotWaveOverlayState();
}

class _OcrDotWaveOverlayState extends State<OcrDotWaveOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _OcrDotWavePainter(
              progress: _controller.value,
              dotColor: widget.dotColor,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _OcrDotWavePainter extends CustomPainter {
  static const double _spacing = 16.0;
  static const double _maxDelay = 0.85;

  final double progress;
  final Color dotColor;

  _OcrDotWavePainter({required this.progress, required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double maxDist = Offset(cx, cy).distance;

    final int cols = (size.width / _spacing).floor();
    final int rows = (size.height / _spacing).floor();
    final double offsetX = (size.width - (cols - 1) * _spacing) / 2;
    final double offsetY = (size.height - (rows - 1) * _spacing) / 2;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final double x = offsetX + c * _spacing;
        final double y = offsetY + r * _spacing;

        final double dist = (Offset(x, y) - Offset(cx, cy)).distance;
        final double delay = (dist / maxDist) * _maxDelay;

        double phase = (progress - delay) % 1.0;
        if (phase < 0) phase += 1.0;

        double t;
        if (phase < 0.5) {
          t = _easeInOut(phase * 2);
        } else {
          t = _easeInOut((1.0 - phase) * 2);
        }

        if (t < 0.01) continue;

        final double radius = 3.0 * t;
        final double opacity = 0.5 * t;

        final paint = Paint()..color = dotColor.withValues(alpha: opacity);
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  static double _easeInOut(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  @override
  bool shouldRepaint(_OcrDotWavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.dotColor != dotColor;
}
