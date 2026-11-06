import "dart:math";

import "package:flutter/material.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _weekdays = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

String _clockHour(int hour) {
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return "$twelve ${hour < 12 ? "AM" : "PM"}";
}

class WeeklyHabitPage extends RewindPage {
  const WeeklyHabitPage(this.habit);

  static const _clock = Rect.fromLTWH(72.2, 157.9, 237.583, 237.583);

  final rust.WeeklyHabit habit;

  @override
  String get key => "weekly_habit";

  @override
  RewindChrome get chrome => RewindChrome.dark;

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final day = (habit.weekday - 1).clamp(0, 6);
    final hour = _clockHour(habit.hour);
    final title = "${_weekdays[day]}s, $hour";
    final line =
        "${habit.percent}% of your photos were taken on ${_weekdays[day]}s.";
    final dayLeft = 37.0 + 46 * day;
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewindBackdrop(
            color: const Color(0xFFFFCA39),
            pattern: RewindStripes(
              const Color(0xFFFFD24E).withValues(alpha: 0.4),
            ),
          ),
          Semantics(
            label: "Your weekly ritual: $title. $line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  _layer(
                    rect: _clock.inflate(40),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.pop,
                      active: isActive,
                      child: RewindElapsed(
                        active: isActive,
                        stillMs: 3000,
                        builder: (context, ms) => Transform.rotate(
                          angle: _wobble(ms) * pi / 180,
                          child: Stack(
                            children: [
                              Positioned.fromRect(
                                rect: _clock.shift(const Offset(-32.2, -117.9)),
                                child: CustomPaint(
                                  painter: _ClockPainter(
                                    hour: habit.hour,
                                    spin: rewindProgress(
                                      ms,
                                      delayMs: 400,
                                      durationMs: 1400,
                                      curve: const Cubic(0.35, 0, 0.2, 1),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 254 - 32.2,
                                top: 177 - 117.9,
                                child: FractionalTranslation(
                                  translation: const Offset(-0.5, -0.5),
                                  child: _HourTag(hour),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _layer(
                    rect: Rect.fromLTWH(dayLeft - 43, 377, 110, 128),
                    position: position,
                    child: _Fire(active: isActive, delayMs: 3150),
                  ),
                  for (var i = 0; i < 7; i++)
                    _layer(
                      rect: Rect.fromLTWH(37.0 + 46 * i, 455, 40, 72),
                      position: position,
                      child: RewindEntrance(
                        preset: RewindPreset.bubble,
                        active: isActive,
                        delayMs: 1900 + 140 * (i + 1),
                        origin: Alignment.bottomCenter,
                        child: _DayTile(
                          letter: _weekdays[i][0],
                          percent: i == day ? habit.percent : null,
                        ),
                      ),
                    ),
                  _layer(
                    rect: const Rect.fromLTWH(37, 91, 179, 354),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.drop,
                      active: isActive,
                      delayMs: 3550,
                      child: Image.file(
                        RewindAssets.file(RewindAssets.cameraOnPole),
                      ),
                    ),
                  ),
                  _layer(
                    rect: const Rect.fromLTWH(0, 60, 210, 245),
                    position: position,
                    child: _Fire(active: isActive, delayMs: 2950),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 597,
                    maxWidth: 316,
                    height: 18,
                    position: position,
                    active: isActive,
                    delayMs: 4000,
                    child: Text(
                      "YOUR WEEKLY RITUAL",
                      style: RewindTextStyles.display(
                        17,
                        color: RewindColors.ink,
                        height: 1.05,
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 627,
                    width: 316,
                    maxWidth: 316,
                    height: 40,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: 4200,
                    child: RewindOutlinedText(
                      title.toUpperCase(),
                      style: RewindTextStyles.display(
                        48.039,
                        color: RewindColors.white,
                        height: 0.84,
                        letterSpacing: -1.4412,
                      ),
                      shadow: const Offset(1.766, 2.119),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 690,
                    width: 316,
                    height: 44,
                    position: position,
                    active: isActive,
                    delayMs: 4500,
                    child: Text(
                      line,
                      style: RewindTextStyles.body(17, color: RewindColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layer({
    required Rect rect,
    required double position,
    required Widget child,
  }) {
    return Positioned.fromRect(
      rect: rect,
      child: RewindLeave(
        position: position,
        centerY: rect.center.dy,
        child: child,
      ),
    );
  }

  double _wobble(double ms) {
    const turns = [0.0, -5.0, 5.0, -4.0, 4.0, -2.0, 0.0];
    final t = rewindProgress(ms, delayMs: 1820, durationMs: 650);
    final span = t * (turns.length - 1);
    final i = min(span.floor(), turns.length - 2);
    return turns[i] + (turns[i + 1] - turns[i]) * (span - i);
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({required this.hour, required this.spin});

  final int hour;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final ink = Paint()..color = RewindColors.ink;
    canvas.drawCircle(center + const Offset(7.92, 9.5), radius, ink);
    canvas.drawCircle(center, radius, Paint()..color = RewindColors.cream);
    canvas.drawCircle(
      center,
      radius - 1.98,
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.96,
    );
    for (var tick = 0; tick < 12; tick++) {
      canvas.drawCircle(
        center + Offset.fromDirection((tick * 30 - 90) * pi / 180, 95.03),
        4.75,
        ink,
      );
    }
    final hours = hour % 12 == 0 ? 12 : hour % 12;
    void hand(double length, double width, double degrees) {
      canvas.drawLine(
        center,
        center + Offset.fromDirection((degrees - 90) * pi / 180, length),
        Paint()
          ..color = RewindColors.ink
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(66.2, 7.92, 360.0 * hours * spin);
    hand(43.83, 6.34, 30.0 * hours * spin);
    canvas.drawCircle(center, 7.92, Paint()..color = RewindColors.hotPink);
    canvas.drawCircle(
      center,
      6.34,
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.17,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter oldDelegate) =>
      oldDelegate.hour != hour || oldDelegate.spin != spin;
}

class _HourTag extends StatelessWidget {
  const _HourTag(this.hour);

  final String hour;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -6 * pi / 180,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 7, 18, 6),
        decoration: BoxDecoration(
          color: RewindColors.hotPink,
          border: Border.all(color: RewindColors.ink, width: 3.49),
          borderRadius: BorderRadius.circular(6.34),
          boxShadow: const [
            BoxShadow(color: RewindColors.ink, offset: Offset(3.17, 4.75)),
          ],
        ),
        child: Text(hour, style: RewindTextStyles.display(28.51, height: 1.15)),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.letter, this.percent});

  final String letter;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final percent = this.percent;
    final highlighted = percent != null;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 40,
        height: highlighted ? 72 : 56,
        decoration: BoxDecoration(
          color: highlighted ? RewindColors.hotPink : RewindColors.cream,
          border: Border.all(color: RewindColors.ink, width: 2.5),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: RewindColors.ink, offset: Offset(3, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              letter,
              style: RewindTextStyles.display(
                20,
                color: highlighted ? RewindColors.cream : RewindColors.ink,
                height: 1.15,
              ),
            ),
            if (highlighted) ...[
              const SizedBox(height: 9),
              FittedBox(
                child: Text(
                  "$percent%",
                  style: RewindTextStyles.numeral(
                    12,
                    color: RewindColors.cream,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fire extends StatelessWidget {
  const _Fire({required this.active, required this.delayMs});

  final bool active;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return RewindEntrance(
      preset: RewindPreset.pop,
      active: active,
      delayMs: delayMs,
      child: RewindIdleLoop(
        idle: RewindIdle.flicker,
        active: active,
        delayMs: delayMs + 700,
        child: Image.file(RewindAssets.file(RewindAssets.fireSticker)),
      ),
    );
  }
}
