import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class RewindSplat extends StatefulWidget {
  const RewindSplat({
    required this.active,
    required this.finalColor,
    super.key,
  });

  final bool active;
  final Color finalColor;

  @override
  State<RewindSplat> createState() => _RewindSplatState();
}

class _RewindSplatState extends State<RewindSplat>
    with SingleTickerProviderStateMixin {
  static const _gapMs = 180;
  static const _growMs = 1140;
  static const _fadeMs = 420;
  static const _holdMs = 3 * _gapMs + _growMs + 60;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _holdMs + _fadeMs),
  );
  late final _blobs = _Blob.generate(widget.finalColor);

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(RewindSplat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _controller.isDismissed) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed =
            _controller.value * _controller.duration!.inMilliseconds;
        if (_controller.isCompleted) return const SizedBox.shrink();
        final fade = ((elapsed - _holdMs) / _fadeMs).clamp(0.0, 1.0);
        return IgnorePointer(
          child: Opacity(
            opacity: 1 - Curves.easeOut.transform(fade),
            child: CustomPaint(
              painter: _SplatPainter(_blobs, elapsed),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

class _Blob {
  _Blob(this.shape, this.color, this.dots, this.dotColor);

  final Path shape;
  final Color color;
  final List<(Offset, double)> dots;
  final Color dotColor;

  static List<_Blob> generate(Color finalColor) {
    var seed = 11;
    double next() {
      seed = (seed * 9301 + 49297) % 233280;
      return seed / 233280;
    }

    Path outline(List<Offset> points) => Path()..addPolygon(points, true);

    Path cloud(int lobes, double radius, double amount) {
      final phase = next() * 6;
      return outline([
        for (var k = 0; k < 96; k++)
          Offset.fromDirection(
            k / 96 * 2 * pi,
            radius *
                (1 +
                    amount * sin(k / 96 * 2 * pi * lobes + phase) +
                    amount * 0.4 * sin(k / 96 * 2 * pi * (lobes * 2 + 1))),
          ),
      ]);
    }

    Path spikes(int count, double outer, double inner) => outline([
      for (var k = 0; k < count * 2; k++)
        Offset.fromDirection(
          k / (count * 2) * 2 * pi,
          (k.isOdd ? inner : outer) * (0.9 + next() * 0.2),
        ),
    ]);

    List<(Offset, double)> dots() => [
      for (var k = 0; k < 18; k++)
        (
          Offset.fromDirection(next() * 2 * pi, 40 + next() * 50),
          1 + next() * 2.6,
        ),
    ];

    final pinkCloud = cloud(9, 88, 0.07);
    final pinkDots = dots();
    final star = spikes(18, 92, 70);
    final starDots = dots();
    final blueCloud = cloud(7, 90, 0.08);
    final blueDots = dots();
    final lastCloud = cloud(11, 94, 0.05);
    return [
      _Blob(
        pinkCloud,
        const Color(0xFFFF0A7A),
        pinkDots,
        const Color(0xFFFBB72C),
      ),
      _Blob(star, const Color(0xFFFBB72C), starDots, const Color(0xFFFF0A7A)),
      _Blob(blueCloud, const Color(0xFF3F78EE), blueDots, RewindColors.cream),
      _Blob(lastCloud, finalColor, const [], finalColor),
    ];
  }
}

class _SplatPainter extends CustomPainter {
  _SplatPainter(this.blobs, this.elapsed);

  static const _spin = 44.0;

  final List<_Blob> blobs;
  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = RewindColors.cream);
    final scale = max(
      size.width / RewindStage.size.width,
      size.height / RewindStage.size.height,
    );
    final grown = RewindStage.size.height * 2 / 200 * scale;
    for (var i = 0; i < blobs.length; i++) {
      final raw =
          (elapsed - i * _RewindSplatState._gapMs) / _RewindSplatState._growMs;
      final q = RewindMotion.bloom.transform(raw.clamp(0.0, 1.0));
      if (q <= 0) continue;
      final blob = blobs[i];
      final turn = -_spin + i * _spin * 0.6 + (_spin - i * _spin * 0.3) * q;
      canvas
        ..save()
        ..translate(size.width / 2, size.height / 2)
        ..rotate(turn * pi / 180)
        ..scale(grown * q)
        ..drawPath(blob.shape, Paint()..color = blob.color);
      final dotPaint = Paint()..color = blob.dotColor;
      for (final (center, radius) in blob.dots) {
        canvas.drawCircle(center, radius, dotPaint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SplatPainter oldDelegate) =>
      oldDelegate.elapsed != elapsed;
}
