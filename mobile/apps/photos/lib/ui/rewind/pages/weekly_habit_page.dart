import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
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
  const WeeklyHabitPage(this.habit, this.hourPhotos, this.ringPhotos);

  static const maxHourPhotos = 3;
  static const maxRingPhotos = 3 * (_Dial._maxSlots - 1);
  static const _tilesTop = 476.0;

  final rust.WeeklyHabit habit;
  final List<EnteFile> hourPhotos;
  final List<EnteFile> ringPhotos;

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
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: _Dial.center.dy,
                      child: _Dial(
                        hourPhotos: hourPhotos,
                        ringPhotos: ringPhotos,
                        hour: habit.hour,
                        label: hour,
                        active: isActive,
                        paused: ModalRoute.of(context)?.isCurrent == false,
                      ),
                    ),
                  ),
                  _layer(
                    rect: Rect.fromLTWH(dayLeft - 26, _tilesTop - 60, 92, 107),
                    position: position,
                    child: _Fire(active: isActive, delayMs: 3000),
                  ),
                  for (var i = 0; i < 7; i++)
                    _layer(
                      rect: Rect.fromLTWH(37.0 + 46 * i, _tilesTop, 40, 72),
                      position: position,
                      child: RewindEntrance(
                        preset: RewindPreset.bubble,
                        active: isActive,
                        delayMs: 2100 + 110 * (i + 1),
                        origin: Alignment.bottomCenter,
                        child: _DayTile(
                          letter: _weekdays[i][0],
                          percent: i == day ? habit.percent : null,
                        ),
                      ),
                    ),
                  RewindRevealLayer(
                    left: 28,
                    top: 597,
                    maxWidth: 316,
                    height: 18,
                    position: position,
                    active: isActive,
                    delayMs: 3300,
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
                    delayMs: 3500,
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
                    delayMs: 3800,
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
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.hourPhotos,
    required this.ringPhotos,
    required this.hour,
    required this.label,
    required this.active,
    required this.paused,
  });

  static const center = Offset(195, 258);
  static const _clockScale = 0.84;
  static const _clockRadius = 118.8 * _clockScale;
  static const _ringRadius = 147.0;
  static const _heroRadius = 138.0;
  static const _photoSize = Size.square(66);
  static const _heroSize = Size(96, 116);
  static const _sweepFromMs = 420.0;
  static const _sweepMs = 1260.0;
  static const _heroMs = _sweepFromMs + _sweepMs;
  static const _ringMs = 1820.0;
  static const _tickFromMs = 3500.0;
  static const _tickEveryMs = 760.0;
  static const _tickMs = 220.0;
  static const _flipMs = 460.0;
  static const _maxSlots = 12;
  static const _tilts = [
    -4.0,
    5.0,
    -6.0,
    3.0,
    -3.0,
    6.0,
    -5.0,
    4.0,
    -2.0,
    5.0,
    -6.0,
    3.0,
  ];

  final List<EnteFile> hourPhotos;
  final List<EnteFile> ringPhotos;
  final int hour;
  final String label;
  final bool active;
  final bool paused;

  double get _heroTurn => (hour % 12) * pi / 6;

  int get _slots =>
      hourPhotos.isEmpty ? 0 : min(_maxSlots, 1 + ringPhotos.length);

  double _slotTurn(int slot) => _heroTurn + slot * 2 * pi / _slots;

  @override
  Widget build(BuildContext context) {
    final count = _slots;
    final faces = [
      [
        for (final (i, file) in hourPhotos.indexed)
          _DialPhoto(key: ValueKey(-1 - i), file: file, caption: label),
      ],
      for (var slot = 1; slot < count; slot++)
        [
          for (var i = slot - 1; i < ringPhotos.length; i += count - 1)
            _DialPhoto(key: ValueKey(i), file: ringPhotos[i]),
        ],
    ];
    return RewindElapsed(
      active: active && !paused,
      stillMs: _tickFromMs,
      builder: (context, ms) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (var slot = count - 1; slot >= 1; slot--)
            _ringPhoto(_face(faces[slot], slot, ms), slot, ms),
          _clock(ms),
          if (count > 0) _hero(_face(faces[0], 0, ms), ms),
        ],
      ),
    );
  }

  Widget _clock(double ms) {
    const box = 118.8 * 2;
    return Positioned.fromRect(
      rect: Rect.fromCenter(center: center, width: box + 80, height: box + 80),
      child: RewindEntrance(
        preset: RewindPreset.pop,
        active: active,
        child: Transform.rotate(
          angle: _wobble(ms) * pi / 180,
          child: Transform.scale(
            scale: _clockScale,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: CustomPaint(
                painter: _ClockPainter(
                  hour: hour,
                  spin: rewindProgress(
                    ms,
                    delayMs: 400,
                    durationMs: 1400,
                    curve: const Cubic(0.35, 0, 0.2, 1),
                  ),
                  second: _slots < 2 ? null : _secondTurn(ms),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _dealMs(int slot) => _sweepFromMs + _sweepMs * slot / _slots;

  double _secondTurn(double ms) {
    if (ms < _tickFromMs) {
      final sweep = rewindProgress(
        ms,
        delayMs: _sweepFromMs,
        durationMs: _sweepMs,
      );
      return _heroTurn + 2 * pi * sweep;
    }
    final beat = (ms - _tickFromMs) / _tickEveryMs;
    final step = beat.floor();
    final into = (beat - step) * _tickEveryMs;
    final settle = RewindMotion.pop.transform((into / _tickMs).clamp(0.0, 1.0));
    final from = _slotTurn(_tickSlot(step - 1));
    var to = _slotTurn(_tickSlot(step));
    if (to < from) to += 2 * pi;
    return lerpDouble(from, to, settle)!;
  }

  int _tickSlot(int step) => step < 0 ? 0 : (step + 1) % _slots;

  int _step(double ms) => ((ms - _tickFromMs) / _tickEveryMs).floor();

  Widget _face(List<Widget> faces, int slot, double ms) {
    final step = _step(ms);
    final first = (slot - 1) % _slots;
    if (faces.length == 1 || _slots < 2 || ms < _tickFromMs || step < first) {
      return faces.first;
    }
    final ticks = (step - first) ~/ _slots + 1;
    final settled = faces[ticks % faces.length];
    final into = ms - _tickFromMs - step * _tickEveryMs;
    if ((step - first) % _slots != 0 || into >= _flipMs) return settled;
    final t = Curves.easeInOut.transform(into / _flipMs);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..rotateY(t < 0.5 ? pi * t : pi * (t - 1)),
      child: t < 0.5 ? faces[(ticks - 1) % faces.length] : settled,
    );
  }

  Widget _ringPhoto(Widget frame, int slot, double ms) {
    final dealMs = _dealMs(slot);
    final e = _spring(ms, dealMs);
    final turn = _slotTurn(slot);
    final radius =
        lerpDouble(_clockRadius - 40, _ringRadius, e)! + _jolt(ms, slot);
    final tick = _tick(ms, slot);
    final scale = lerpDouble(0.3, 1, e)! * (1 + 0.12 * tick);
    final tilt = lerpDouble(-30, _tilts[slot % _tilts.length], e)! + 6 * tick;
    return _placed(
      frame,
      center + Offset(sin(turn), -cos(turn)) * radius,
      _photoSize,
      scale: scale,
      tilt: tilt,
      opacity: ((ms - dealMs) / 90).clamp(0.0, 1.0),
    );
  }

  Widget _hero(Widget frame, double ms) {
    final e = _spring(ms, _heroMs);
    final turn = _heroTurn;
    final radius = lerpDouble(_heroRadius + 16, _heroRadius, e)!;
    final tick = _tick(ms, 0);
    return _placed(
      frame,
      center + Offset(sin(turn), -cos(turn)) * radius,
      _heroSize,
      scale: lerpDouble(0.2, 1, e)! * (1 + 0.08 * tick),
      tilt: lerpDouble(-24, -4, e)! + 4 * tick,
      opacity: ((ms - _heroMs) / 90).clamp(0.0, 1.0),
    );
  }

  Widget _placed(
    Widget frame,
    Offset at,
    Size size, {
    required double scale,
    required double tilt,
    required double opacity,
  }) {
    return Positioned.fromRect(
      rect: Rect.fromCenter(center: at, width: size.width, height: size.height),
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: tilt * pi / 180,
          child: Transform.scale(scale: scale, child: frame),
        ),
      ),
    );
  }

  double _spring(double ms, double fromMs) => RewindMotion.pop.transform(
    ((ms - fromMs) / RewindMotion.pop.duration.inMilliseconds).clamp(0.0, 1.0),
  );

  double _jolt(double ms, int slot) {
    final q = (ms - _ringMs - 14 * slot) / 700;
    if (q <= 0 || q >= 1) return 0;
    return 10 * sin(q * 5 * pi) * pow(1 - q, 2);
  }

  double _tick(double ms, int slot) {
    if (_slots < 2 || ms < _tickFromMs) return 0;
    final beat = (ms - _tickFromMs) / _tickEveryMs;
    if (_tickSlot(beat.floor()) != slot) return 0;
    final into = (beat - beat.floor()) * _tickEveryMs;
    return sin((into / 420).clamp(0.0, 1.0) * pi);
  }

  double _wobble(double ms) {
    const turns = [0.0, -5.0, 5.0, -4.0, 4.0, -2.0, 0.0];
    final t = rewindProgress(ms, delayMs: _ringMs, durationMs: 650);
    final span = t * (turns.length - 1);
    final i = min(span.floor(), turns.length - 2);
    return turns[i] + (turns[i + 1] - turns[i]) * (span - i);
  }
}

class _DialPhoto extends StatelessWidget {
  const _DialPhoto({required this.file, this.caption, super.key});

  final EnteFile file;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final caption = this.caption;
    final hero = caption != null;
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: RewindPhoto(file, placeholder: const Color(0x1F151515)),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hero ? RewindColors.hotPink : RewindColors.photoPaper,
        border: Border.all(color: RewindColors.ink, width: hero ? 3 : 2.5),
        borderRadius: BorderRadius.circular(hero ? 9 : 8),
        boxShadow: [
          BoxShadow(
            color: RewindColors.ink,
            offset: hero ? const Offset(4, 5) : const Offset(2.5, 3.5),
          ),
        ],
      ),
      child: hero
          ? Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
              child: Column(
                children: [
                  AspectRatio(aspectRatio: 1, child: photo),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        child: Text(
                          caption,
                          style: RewindTextStyles.display(20, height: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Padding(padding: const EdgeInsets.all(3.5), child: photo),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({required this.hour, required this.spin, this.second});

  final int hour;
  final double spin;
  final double? second;

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
    final second = this.second;
    if (second != null) {
      final tip = Offset(sin(second), -cos(second));
      canvas.drawLine(
        center - tip * 18,
        center + tip * 88,
        Paint()
          ..color = RewindColors.hotPink
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round,
      );
    }
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
      oldDelegate.hour != hour ||
      oldDelegate.spin != spin ||
      oldDelegate.second != second;
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
