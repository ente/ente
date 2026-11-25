import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/pages/finale/finale_actions.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_svg.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";
import "package:photos/ui/rewind/widgets/rewind_year_duckies.dart";

const _actionsDelayMs = 700;
const _headlineWidth = 435.06;
const _headlineCenterX = 197.54;

const _confetti = [
  (RewindAssets.limeConfetti, Offset(156, 94.02), 450),
  (RewindAssets.yellowConfetti, Offset(42, 189.98), 520),
  (RewindAssets.yellowConfetti, Offset(279.98, 165), 590),
  (RewindAssets.blueConfetti, Offset(53.02, 379), 660),
  (RewindAssets.greenConfetti, Offset(199.98, 388.99), 730),
];

class FinaleCard extends StatefulWidget {
  const FinaleCard({required this.active, required this.launched, super.key});

  final bool active;
  final bool launched;

  @override
  State<FinaleCard> createState() => _FinaleCardState();
}

class _FinaleCardState extends State<FinaleCard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _ms = ValueNotifier(0.0);
  var _banked = Duration.zero;
  var _since = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FinaleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ms.dispose();
    super.dispose();
  }

  void _sync() {
    final run = widget.launched && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _banked = _since;
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    _since = _banked + elapsed;
    _ms.value = _since.inMicroseconds / 1000;
  }

  @override
  Widget build(BuildContext context) {
    final copy = RewindCopy.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Semantics(
            label: copy.finaleLabel,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const RewindBackdrop(
                    color: RewindColors.green,
                    pattern: RewindStripes(Color(0xFF0EBF29)),
                  ),
                  RewindStage(
                    children: [
                      const Positioned(
                        left: -109.63,
                        top: -98.75,
                        child: RewindSvg(RewindAssets.finaleRays),
                      ),
                      _fire(),
                      _headline(
                        copy.finaleTop,
                        size: 81.731,
                        color: RewindColors.cream,
                        letterSpacing: -4.0865,
                        centerY: 241.5,
                        boxHeight: 100.592,
                        delayMs: 0,
                      ),
                      _headline(
                        copy.finaleBottom,
                        size: 118.196,
                        color: const Color(0xFFFFCE00),
                        centerY: 314.02,
                        boxHeight: 145.858,
                        delayMs: 150,
                      ),
                      for (final (asset, at, delayMs) in _confetti)
                        Positioned(
                          left: at.dx,
                          top: at.dy,
                          child: RewindEntrance(
                            preset: RewindPreset.twinkle,
                            active: widget.launched,
                            delayMs: delayMs,
                            child: RewindIdleLoop(
                              idle: RewindIdle.twinkle,
                              active: widget.launched,
                              delayMs: delayMs + 900,
                              child: RewindSvg(asset),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const RewindYearDuckies(),
                ],
              ),
            ),
          ),
        ),
        RewindStage(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: _ms,
                builder: (context, ms, actions) => IgnorePointer(
                  ignoring: !widget.active || (!still && ms < _actionsDelayMs),
                  child: actions,
                ),
                child: FinaleActions(
                  active: widget.launched,
                  delayMs: _actionsDelayMs,
                  elapsedMs: _ms,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fire() {
    return Positioned.fromRect(
      rect: const Rect.fromLTWH(130.35, 94.5, 133.16, 155.98),
      child: Transform.rotate(
        angle: 5.68 * pi / 180,
        child: const RewindDucky(RewindAssets.fire, stateMachine: "Fire"),
      ),
    );
  }

  Widget _headline(
    String text, {
    required double size,
    required Color color,
    required double centerY,
    required double boxHeight,
    required int delayMs,
    double letterSpacing = 0,
  }) {
    return Positioned(
      left: _headlineCenterX - _headlineWidth / 2,
      top: centerY - boxHeight / 2,
      width: _headlineWidth,
      height: boxHeight,
      child: RewindEntrance(
        preset: RewindPreset.rise,
        active: widget.launched,
        delayMs: delayMs,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: RewindOutlinedText(
              text,
              style: RewindTextStyles.display(
                size,
                color: color,
                height: 1.05,
                letterSpacing: letterSpacing,
              ),
              outline: 5,
              shadow: const Offset(0, 6.287),
              ink: RewindColors.outline,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
