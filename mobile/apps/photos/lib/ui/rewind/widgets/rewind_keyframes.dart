import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";

class RewindPose {
  const RewindPose(
    this.at, {
    this.dx = 0,
    this.dy = 0,
    double scale = 1,
    double? sx,
    double? sy,
    this.turn = 0,
    this.opacity = 1,
  }) : sx = sx ?? scale,
       sy = sy ?? scale;

  final double at;
  final double dx;
  final double dy;
  final double sx;
  final double sy;
  final double turn;
  final double opacity;

  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..rotateZ(turn * pi / 180)
    ..scaleByDouble(sx, sy, 1, 1);

  static RewindPose along(List<RewindPose> poses, double t) {
    var i = 0;
    while (i < poses.length - 2 && t > poses[i + 1].at) {
      i++;
    }
    final a = poses[i];
    final b = poses[i + 1];
    final q = b.at == a.at ? 1.0 : (t - a.at) / (b.at - a.at);
    double mix(double from, double to) => lerpDouble(from, to, q)!;
    return RewindPose(
      t,
      dx: mix(a.dx, b.dx),
      dy: mix(a.dy, b.dy),
      sx: mix(a.sx, b.sx),
      sy: mix(a.sy, b.sy),
      turn: mix(a.turn, b.turn),
      opacity: mix(a.opacity, b.opacity),
    );
  }
}

class RewindKeyframes extends StatefulWidget {
  const RewindKeyframes({
    required this.poses,
    required this.durationMs,
    required this.active,
    required this.child,
    this.delayMs = 0,
    this.curve = Curves.linear,
    this.origin = Alignment.center,
    this.replay,
    this.hiddenBeforeStart = false,
    super.key,
  });

  final List<RewindPose> poses;
  final int durationMs;
  final int delayMs;
  final bool active;
  final Curve curve;
  final Alignment origin;
  final Object? replay;
  final bool hiddenBeforeStart;
  final Widget child;

  @override
  State<RewindKeyframes> createState() => _RewindKeyframesState();
}

class _RewindKeyframesState extends State<RewindKeyframes>
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
  void didUpdateWidget(RewindKeyframes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) return;
    if (widget.replay != oldWidget.replay) {
      _controller.forward(from: 0);
    } else if (_controller.isDismissed) {
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
    if (MediaQuery.disableAnimationsOf(context)) {
      return _posed(widget.active ? widget.poses.last : widget.poses.first);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed =
            _controller.value * _controller.duration!.inMilliseconds -
            widget.delayMs;
        if (elapsed < 0 && widget.hiddenBeforeStart) {
          return Opacity(opacity: 0, child: widget.child);
        }
        final t = (elapsed / widget.durationMs).clamp(0.0, 1.0);
        return _posed(
          RewindPose.along(widget.poses, widget.curve.transform(t)),
        );
      },
    );
  }

  Widget _posed(RewindPose pose) {
    final child = Transform(
      transform: pose.matrix,
      alignment: widget.origin,
      child: widget.child,
    );
    if (pose.opacity >= 1) return child;
    return Opacity(opacity: pose.opacity.clamp(0.0, 1.0), child: child);
  }
}
