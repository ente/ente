import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class RewindWaveReveal extends StatefulWidget {
  const RewindWaveReveal({
    required this.active,
    required this.child,
    this.onRevealed,
    super.key,
  });

  final bool active;
  final VoidCallback? onRevealed;
  final Widget child;

  @override
  State<RewindWaveReveal> createState() => _RewindWaveRevealState();
}

class _RewindWaveRevealState extends State<RewindWaveReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: RewindMotion.waveDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(RewindWaveReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _controller.isDismissed) _start();
  }

  void _start() {
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) widget.onRevealed?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = Curves.easeInOutCubic.transform(_controller.value);
        if (progress >= 1) return child!;
        return ClipPath(clipper: RewindWaveClipper(progress), child: child);
      },
    );
  }
}

class RewindWaveClipper extends CustomClipper<Path> {
  RewindWaveClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final scale = size.width / RewindStage.size.width;
    final amplitude = 16 * sin(pi * progress) * scale;
    final height = size.height;
    final base =
        height +
        amplitude +
        4 * scale -
        progress * (height + 2 * amplitude + 8 * scale);
    final path = Path()..moveTo(-10 * scale, height + 60 * scale);
    for (var x = -10.0; x <= RewindStage.size.width + 10; x += 10) {
      path.lineTo(
        x * scale,
        base +
            amplitude * sin(x / RewindStage.size.width * 3 * pi + 5 * progress),
      );
    }
    return path
      ..lineTo((RewindStage.size.width + 10) * scale, height + 60 * scale)
      ..close();
  }

  @override
  bool shouldReclip(RewindWaveClipper oldClipper) =>
      oldClipper.progress != progress;
}
