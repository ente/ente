import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_splat.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class CoverPage extends RewindPage {
  const CoverPage();

  static const _lockup = Rect.fromLTWH(14, 87, 354, 316);
  static const _camera = Rect.fromLTWH(251.7, 100.3, 63, 67);
  static const _ducky = Rect.fromLTWH(68.4, 381, 262.7, 269);
  static const _tagline = Rect.fromLTWH(23.75, 669, 344.5, 24);
  static const _button = Offset(252, 755);

  @override
  String get key => "cover";

  @override
  RewindChrome get chrome => const RewindChrome(foreground: RewindColors.cream);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    Widget layer(Rect rect, Widget child) => Positioned.fromRect(
      rect: rect,
      child: RewindLeave(
        position: position,
        centerY: rect.center.dy,
        child: child,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: RewindPageScope.navigatorOf(context)?.next,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: RewindColors.green,
            doodle: RewindColors.doodleGreen,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.58, 1],
                colors: [Color(0x0008C225), RewindColors.green],
              ),
            ),
          ),
          RewindSplat(active: isActive, finalColor: RewindColors.green),
          RewindStage(
            children: [
              layer(
                _lockup,
                _FlyingLockup(
                  active: isActive,
                  from: RewindStage.size.center(Offset.zero) - _lockup.center,
                ),
              ),
              layer(
                _camera,
                RewindEntrance(
                  preset: RewindPreset.pop,
                  active: isActive,
                  delayMs: 1250,
                  child: Image.file(
                    RewindAssets.file(RewindAssets.cameraSticker),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              layer(
                _ducky,
                RewindEntrance(
                  preset: RewindPreset.hop,
                  active: isActive,
                  delayMs: 683,
                  child: const RewindDucky(RewindAssets.introDucky),
                ),
              ),
              layer(
                _tagline,
                RewindEntrance(
                  preset: RewindPreset.pop,
                  active: isActive,
                  delayMs: 1500,
                  child: RewindFitWidth(
                    width: _tagline.width,
                    alignment: Alignment.center,
                    child: Text(
                      "YOUR YEAR. FULL VOLUME.",
                      style: RewindTextStyles.display(
                        23.96,
                        color: RewindColors.white,
                        height: 0.84,
                      ),
                    ),
                  ),
                ),
              ),
              layer(
                Rect.fromCenter(center: _button, width: 320, height: 120),
                Center(
                  child: RewindEntrance(
                    preset: RewindPreset.pop,
                    active: isActive,
                    delayMs: 1750,
                    child: RewindIdleLoop(
                      idle: RewindIdle.pulse,
                      active: isActive,
                      delayMs: 2700,
                      child: Transform.rotate(
                        angle: -3.7 * pi / 180,
                        child: RewindCandyButton(
                          label: "Tap to start",
                          onTap: () =>
                              RewindPageScope.navigatorOf(context)?.next(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlyingLockup extends StatefulWidget {
  const _FlyingLockup({required this.active, required this.from});

  final bool active;
  final Offset from;

  @override
  State<_FlyingLockup> createState() => _FlyingLockupState();
}

class _FlyingLockupState extends State<_FlyingLockup>
    with TickerProviderStateMixin {
  static const _delayMs = 120;
  static const _flightMs = 1020;
  static const _shineDelayMs = 1550;

  late final _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _delayMs + _flightMs),
  );
  late final _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );
  late final _shineWait = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _shineDelayMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_FlyingLockup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _flight.isDismissed) _start();
  }

  void _start() {
    _flight.forward();
    _shineWait.forward().whenCompleteOrCancel(() {
      if (mounted) _shine.repeat();
    });
  }

  @override
  void dispose() {
    _flight.dispose();
    _shine.dispose();
    _shineWait.dispose();
    super.dispose();
  }

  Matrix4 _pose(double t) {
    final from = widget.from;
    const frames = [
      (at: 0.0, move: 1.0, sx: 0.4, sy: 0.4, turn: 8.0),
      (at: 0.45, move: -0.18, sx: 1.26, sy: 1 / 1.26, turn: -3.2),
      (at: 0.66, move: 0.054, sx: 0.94, sy: 1.07, turn: 1.2),
      (at: 0.84, move: 0.0, sx: 1.03, sy: 0.97, turn: 0.0),
      (at: 1.0, move: 0.0, sx: 1.0, sy: 1.0, turn: 0.0),
    ];
    var i = 0;
    while (i < frames.length - 2 && t > frames[i + 1].at) {
      i++;
    }
    final a = frames[i];
    final b = frames[i + 1];
    final q = RewindMotion.sway.transform(
      ((t - a.at) / (b.at - a.at)).clamp(0.0, 1.0),
    );
    final move = lerpDouble(a.move, b.move, q)!;
    return Matrix4.identity()
      ..translateByDouble(from.dx * move, from.dy * move, 0, 1)
      ..rotateZ(lerpDouble(a.turn, b.turn, q)! * pi / 180)
      ..scaleByDouble(
        lerpDouble(a.sx, b.sx, q)!,
        lerpDouble(a.sy, b.sy, q)!,
        1,
        1,
      );
  }

  @override
  Widget build(BuildContext context) {
    final lockup = Image.file(
      RewindAssets.file(RewindAssets.coverLockup),
      fit: BoxFit.contain,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return Opacity(opacity: widget.active ? 1 : 0, child: lockup);
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_flight, _shine]),
      child: lockup,
      builder: (context, child) {
        final elapsed = _flight.value * (_delayMs + _flightMs) - _delayMs;
        if (elapsed < 0) return Opacity(opacity: 0, child: child);
        final t = (elapsed / _flightMs).clamp(0.0, 1.0);
        return Opacity(
          opacity: (elapsed / 70).clamp(0.0, 1.0),
          child: Transform(
            transform: _pose(t),
            alignment: Alignment.center,
            child: _shine.isAnimating ? _shined(child!) : child,
          ),
        );
      },
    );
  }

  Widget _shined(Widget child) {
    final sweep = _shine.value / 0.23;
    if (sweep >= 1) return child;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        final direction = Offset(sin(115 * pi / 180), -cos(115 * pi / 180));
        final center = Offset(
          lerpDouble(-1.1, 2.1, sweep)! * bounds.width,
          bounds.height / 2,
        );
        final half = direction * bounds.width * 0.25;
        Alignment at(Offset point) => Alignment(
          point.dx / bounds.width * 2 - 1,
          point.dy / bounds.height * 2 - 1,
        );
        return LinearGradient(
          begin: at(center - half),
          end: at(center + half),
          colors: const [
            Color(0x00FFFFFF),
            Color(0xBFFFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(Offset.zero & bounds.size);
      },
      child: child,
    );
  }
}
