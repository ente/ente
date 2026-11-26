import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";

class RewindCountUp extends StatefulWidget {
  const RewindCountUp({
    required this.value,
    required this.active,
    required this.builder,
    this.delayMs = 0,
    this.durationMs = 1400,
    super.key,
  });

  final int value;
  final bool active;
  final int delayMs;
  final int durationMs;
  final Widget Function(BuildContext context, String text) builder;

  @override
  State<RewindCountUp> createState() => _RewindCountUpState();
}

class _RewindCountUpState extends State<RewindCountUp>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delayMs + widget.durationMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(RewindCountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _controller.stop();
    } else if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = RewindCopy.of(context);
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.builder(context, copy.number(widget.value));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed =
            _controller.value * _controller.duration!.inMilliseconds -
            widget.delayMs;
        final q = (elapsed / widget.durationMs).clamp(0.0, 1.0);
        final shown = (widget.value * (1 - pow(1 - q, 3))).round();
        return widget.builder(context, copy.number(shown));
      },
    );
  }
}
