import "dart:math" as math;

import "package:flutter/widgets.dart";

class FadingCircleProgressIndicator extends StatefulWidget {
  const FadingCircleProgressIndicator({
    required this.color,
    this.size = 18,
    super.key,
  });

  final Color color;
  final double size;

  @override
  State<FadingCircleProgressIndicator> createState() =>
      _FadingCircleProgressIndicatorState();
}

class _FadingCircleProgressIndicatorState
    extends State<FadingCircleProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FadingCirclePainter(
            color: widget.color,
            progress: _controller,
          ),
        ),
      ),
    );
  }
}

class _FadingCirclePainter extends CustomPainter {
  _FadingCirclePainter({required this.color, required this.progress})
    : super(repaint: progress);

  static const _dotCount = 12;
  static final _dotOffsets = List.generate(_dotCount, (index) {
    final angle = 2 * math.pi * index / _dotCount - math.pi / 2;
    return Offset(math.cos(angle), math.sin(angle));
  });

  final Color color;
  final Animation<double> progress;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.354;
    final dotRadius = size.shortestSide * 0.075;

    for (var index = 0; index < _dotCount; index++) {
      final delay = index / _dotCount;
      final opacity =
          (math.sin((progress.value - delay) * 2 * math.pi) + 1) / 2;
      _paint.color = color.withValues(alpha: color.a * opacity);
      canvas.drawCircle(
        center + _dotOffsets[index] * radius,
        dotRadius,
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FadingCirclePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}
