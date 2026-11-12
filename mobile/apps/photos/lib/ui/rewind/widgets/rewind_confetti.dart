import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";

class RewindConfetti extends StatefulWidget {
  const RewindConfetti({
    required this.count,
    required this.active,
    this.delayMs = 0,
    this.seed = 7,
    super.key,
  });

  final int count;
  final bool active;
  final int delayMs;
  final int seed;

  @override
  State<RewindConfetti> createState() => _RewindConfettiState();
}

class _RewindConfettiState extends State<RewindConfetti>
    with SingleTickerProviderStateMixin {
  static const _fall = Cubic(0.25, 0.6, 0.4, 1);

  late final _bits = _scatter(
    widget.count,
    widget.delayMs,
    Random(widget.seed),
  );
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: _bits.map((bit) => bit.delayMs + bit.fallMs).reduce(max),
    ),
  );

  static List<_Bit> _scatter(int count, int delayMs, Random random) => [
    for (var i = 0; i < count; i++)
      _Bit(
        x: 20 + random.nextDouble() * 350,
        drift: (random.nextDouble() - 0.5) * 120,
        turn: random.nextDouble() * 360,
        fallMs: 1400 + random.nextInt(1400),
        delayMs: delayMs + random.nextInt(300),
        color: RewindColors.confetti[i % RewindColors.confetti.length],
      ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(RewindConfetti oldWidget) {
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
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(_bits, _controller),
      ),
    );
  }
}

class _Bit {
  const _Bit({
    required this.x,
    required this.drift,
    required this.turn,
    required this.fallMs,
    required this.delayMs,
    required this.color,
  });

  final double x;
  final double drift;
  final double turn;
  final int fallMs;
  final int delayMs;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.progress) : super(repaint: progress);

  final List<_Bit> bits;
  final AnimationController progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (!progress.isAnimating) return;
    final elapsed = progress.value * progress.duration!.inMilliseconds;
    final paint = Paint();
    for (final bit in bits) {
      final t = (elapsed - bit.delayMs) / bit.fallMs;
      if (t <= 0 || t >= 1) continue;
      final q = _RewindConfettiState._fall.transform(t);
      canvas.save();
      canvas.translate(bit.x + bit.drift * q, -20 + 920 * q);
      canvas.rotate((bit.turn + 540 * q) * pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 9, height: 14),
          const Radius.circular(3),
        ),
        paint..color = bit.color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.bits != bits;
}
