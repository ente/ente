import "dart:math";
import "dart:ui" show ImageFilter, lerpDouble;

import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";

enum RewindPreset {
  rise(1050, RewindMotion.expo),
  line(900, RewindMotion.expo, fadeMs: 420, blur: 5),
  pop(879, RewindMotion.pop, fadeMs: 420, blur: 8),
  slap(642, RewindMotion.slap, fadeMs: 240, blur: 12),
  duck(1050, RewindMotion.squash, fadeMs: 200),
  hop(1150, RewindMotion.hop, fadeMs: 70),
  fly(792, RewindMotion.soft, fadeMs: 250),
  flip(792, RewindMotion.soft, fadeMs: 420),
  tilt(833, RewindMotion.drop, fadeMs: 420),
  drop(833, RewindMotion.drop, fadeMs: 420),
  crowd(1300, RewindMotion.expo),
  cloud(1150, RewindMotion.expo),
  bubble(992, RewindMotion.bubble, fadeMs: 420),
  twinkle(879, RewindMotion.pop, fadeMs: 420),
  fadeIn(0, Curves.linear, fadeMs: 700);

  const RewindPreset(
    this.motionMs,
    this.curve, {
    this.fadeMs = 0,
    this.blur = 0,
  });

  final int motionMs;
  final Curve curve;
  final int fadeMs;
  final double blur;

  int get lengthMs => max(motionMs, fadeMs);

  Alignment get defaultOrigin => switch (this) {
    duck || hop => Alignment.bottomCenter,
    _ => Alignment.center,
  };

  Matrix4 transformAt(double e) {
    final rest = 1 - e;
    final matrix = Matrix4.identity();
    switch (this) {
      case line:
        matrix.translateByDouble(0, 18 * rest, 0, 1);
      case pop:
        matrix
          ..rotateZ(_radians(-14 * rest))
          ..scaleByDouble(0.25 + 0.75 * e, 0.25 + 0.75 * e, 1, 1);
      case slap:
        matrix
          ..rotateZ(_radians(3 * rest))
          ..scaleByDouble(1.6 - 0.6 * e, 1.6 - 0.6 * e, 1, 1);
      case duck:
        _applyKeyframes(matrix, e, _duckFrames);
      case hop:
        _applyKeyframes(matrix, e, _hopFrames);
      case fly:
        matrix
          ..translateByDouble(0, 340 * rest, 0, 1)
          ..rotateZ(_radians(-16 * rest))
          ..scaleByDouble(0.6 + 0.4 * e, 0.6 + 0.4 * e, 1, 1);
      case flip:
        matrix
          ..setEntry(3, 2, 0.001)
          ..rotateY(_radians(-100 * rest))
          ..scaleByDouble(0.82 + 0.18 * e, 0.82 + 0.18 * e, 1, 1);
      case tilt:
        matrix
          ..setEntry(3, 2, 0.001)
          ..translateByDouble(0, -160 * rest, 0, 1)
          ..rotateX(_radians(30 * rest))
          ..rotateZ(_radians(-10 * rest));
      case drop:
        matrix
          ..translateByDouble(0, -150 * rest, 0, 1)
          ..rotateZ(_radians(-14 * rest))
          ..scaleByDouble(1.08 - 0.08 * e, 1.08 - 0.08 * e, 1, 1);
      case crowd:
        matrix.translateByDouble(0, 360 * rest, 0, 1);
      case cloud:
        matrix.translateByDouble(0, 280 * rest, 0, 1);
      case bubble:
        matrix.scaleByDouble(e, e, 1, 1);
      case twinkle:
        matrix
          ..rotateZ(_radians(-150 * rest))
          ..scaleByDouble(e, e, 1, 1);
      case rise:
        matrix.setEntry(1, 0, tan(_radians(6 * rest)));
      case fadeIn:
        break;
    }
    return matrix;
  }
}

const _duckFrames = [
  (at: 0.0, dy: 170.0, sx: 0.92, sy: 1.12),
  (at: 0.5, dy: -16.0, sx: 0.97, sy: 1.04),
  (at: 0.72, dy: 0.0, sx: 1.06, sy: 0.93),
  (at: 0.88, dy: 0.0, sx: 0.99, sy: 1.01),
  (at: 1.0, dy: 0.0, sx: 1.0, sy: 1.0),
];

const _hopFrames = [
  (at: 0.0, dy: 520.0, sx: 0.95, sy: 1.06),
  (at: 0.52, dy: -34.0, sx: 1.0, sy: 1.0),
  (at: 0.74, dy: 8.0, sx: 1.05, sy: 0.95),
  (at: 0.88, dy: -2.0, sx: 1.0, sy: 1.0),
  (at: 1.0, dy: 0.0, sx: 1.0, sy: 1.0),
];

void _applyKeyframes(
  Matrix4 matrix,
  double e,
  List<({double at, double dy, double sx, double sy})> frames,
) {
  final t = e.clamp(0.0, 1.0);
  var i = 0;
  while (i < frames.length - 2 && t > frames[i + 1].at) {
    i++;
  }
  final a = frames[i];
  final b = frames[i + 1];
  final q = (t - a.at) / (b.at - a.at);
  matrix
    ..translateByDouble(0, lerpDouble(a.dy, b.dy, q)!, 0, 1)
    ..scaleByDouble(
      lerpDouble(a.sx, b.sx, q)!,
      lerpDouble(a.sy, b.sy, q)!,
      1,
      1,
    );
}

double _radians(double degrees) => degrees * pi / 180;

class RewindEntrance extends StatefulWidget {
  const RewindEntrance({
    required this.preset,
    required this.active,
    required this.child,
    this.delayMs = 0,
    this.origin,
    super.key,
  });

  final RewindPreset preset;
  final bool active;
  final int delayMs;
  final Alignment? origin;
  final Widget child;

  @override
  State<RewindEntrance> createState() => _RewindEntranceState();
}

class _RewindEntranceState extends State<RewindEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delayMs + widget.preset.lengthMs),
  );
  final _childKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(RewindEntrance oldWidget) {
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
    if (MediaQuery.disableAnimationsOf(context)) {
      return Opacity(opacity: widget.active ? 1 : 0, child: widget.child);
    }
    return AnimatedBuilder(
      animation: _controller,
      child: KeyedSubtree(key: _childKey, child: widget.child),
      builder: (context, child) => _build(child!),
    );
  }

  Widget _build(Widget child) {
    final preset = widget.preset;
    final elapsed =
        _controller.value * _controller.duration!.inMilliseconds -
        widget.delayMs;
    if (elapsed < 0) return Opacity(opacity: 0, child: child);
    final motion = preset.motionMs == 0
        ? 1.0
        : preset.curve.transform((elapsed / preset.motionMs).clamp(0.0, 1.0));
    final fade = preset.fadeMs == 0
        ? 1.0
        : Curves.easeOut.transform((elapsed / preset.fadeMs).clamp(0.0, 1.0));
    var result = motion == 1
        ? child
        : Transform(
            transform: preset.transformAt(motion),
            alignment: widget.origin ?? preset.defaultOrigin,
            child: child,
          );
    if (preset == RewindPreset.rise && motion < 1) {
      result = ClipRect(
        clipper: const _AboveBottomEdge(),
        child: FractionalTranslation(
          translation: Offset(0, 0.74 * (1 - motion)),
          child: result,
        ),
      );
    }
    final blur = preset.blur * (1 - fade);
    if (blur > 0.05) {
      result = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: result,
      );
    }
    return fade < 1 ? Opacity(opacity: fade, child: result) : result;
  }
}

class _AboveBottomEdge extends CustomClipper<Rect> {
  const _AboveBottomEdge();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, -size.height, size.width * 2, size.height);

  @override
  bool shouldReclip(_AboveBottomEdge oldClipper) => false;
}

typedef _Pose = ({double sx, double sy, double turn, double skew});

const _rest = (sx: 1.0, sy: 1.0, turn: 0.0, skew: 0.0);

enum RewindIdle {
  pulse(1400, [_rest, (sx: 1.07, sy: 1.07, turn: 0.0, skew: 0.0), _rest]),
  twinkle(1500, [_rest, (sx: 0.55, sy: 0.55, turn: 25.0, skew: 0.0), _rest]),
  flicker(700, [
    _rest,
    (sx: 1.04, sy: 1.1, turn: 0.0, skew: -3.0),
    (sx: 0.98, sy: 0.94, turn: 0.0, skew: 3.0),
    _rest,
  ]);

  const RewindIdle(this.periodMs, this._poses);

  final int periodMs;
  final List<_Pose> _poses;

  Matrix4 transformAt(double t) {
    final span = t * (_poses.length - 1);
    final i = min(span.floor(), _poses.length - 2);
    final q = Curves.easeInOut.transform(span - i);
    final a = _poses[i];
    final b = _poses[i + 1];
    final sx = lerpDouble(a.sx, b.sx, q)!;
    final sy = lerpDouble(a.sy, b.sy, q)!;
    return Matrix4.identity()
      ..rotateZ(_radians(lerpDouble(a.turn, b.turn, q)!))
      ..setEntry(0, 1, tan(_radians(lerpDouble(a.skew, b.skew, q)!)))
      ..scaleByDouble(sx, sy, 1, 1);
  }
}

class RewindIdleLoop extends StatefulWidget {
  const RewindIdleLoop({
    required this.idle,
    required this.active,
    required this.child,
    this.delayMs = 0,
    super.key,
  });

  final RewindIdle idle;
  final bool active;
  final int delayMs;
  final Widget child;

  @override
  State<RewindIdleLoop> createState() => _RewindIdleLoopState();
}

class _RewindIdleLoopState extends State<RewindIdleLoop>
    with TickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.idle.periodMs),
  );
  late final _wait = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delayMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _begin();
  }

  @override
  void didUpdateWidget(RewindIdleLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _wait.isDismissed) _begin();
  }

  void _begin() {
    _wait.forward().whenCompleteOrCancel(() {
      if (mounted) _loop.repeat();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _wait.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _loop,
      child: widget.child,
      builder: (context, child) => Transform(
        transform: widget.idle.transformAt(_loop.value),
        alignment: widget.idle == RewindIdle.flicker
            ? Alignment.bottomCenter
            : Alignment.center,
        child: child,
      ),
    );
  }
}
