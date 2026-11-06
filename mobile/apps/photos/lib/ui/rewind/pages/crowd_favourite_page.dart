import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _likeGreen = Color(0xFF08C225);
const _button = Offset(290.8, 564.8);

class CrowdFavouritePage extends RewindPage {
  const CrowdFavouritePage(this.photo, this.file);

  static const _countFromMs = 1500.0;
  static const _countMs = 1400.0;

  final rust.LikedPhoto photo;
  final EnteFile file;

  @override
  String get key => "crowd_favourite";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final likes = photo.likeCount;
    final unit = likes == 1 ? "LIKE" : "LIKES";
    const line = "You took thousands. This one had fans.";
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewindBackdrop(
            color: const Color(0xFF2F65D7),
            pattern: RewindStripes(
              const Color(0xFF3670EB).withValues(alpha: 0.36),
            ),
          ),
          Semantics(
            label:
                "Crowd favourite: ${rewindCounted(likes, "like", "likes")}. "
                "$line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 340,
                      child: RewindElapsed(
                        active: isActive,
                        stillMs: 6000,
                        builder: (context, ms) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _photo(ms),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _HeartStreamPainter(ms),
                              ),
                            ),
                            _likeButton(ms),
                          ],
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 26,
                    top: 625,
                    maxWidth: 338,
                    height: 23,
                    position: position,
                    active: isActive,
                    delayMs: 1350,
                    child: Text(
                      "CROWD FAVOURITE",
                      style: RewindTextStyles.display(
                        20,
                        height: 1.15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 24,
                    top: 649,
                    maxWidth: 340,
                    height: 62,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: _countFromMs.toInt(),
                    origin: Alignment.centerLeft,
                    child: RewindElapsed(
                      active: isActive,
                      stillMs: _countFromMs + _countMs,
                      builder: (context, ms) {
                        final shown =
                            (likes *
                                    rewindProgress(
                                      ms,
                                      delayMs: _countFromMs,
                                      durationMs: _countMs,
                                      curve: Curves.easeOutCubic,
                                    ))
                                .round();
                        return RewindOutlinedText(
                          "${rewindCount(shown)} $unit",
                          style: RewindTextStyles.display(54, height: 1.15),
                          outline: 1.6,
                          shadow: const Offset(2, 3),
                        );
                      },
                    ),
                  ),
                  RewindRevealLayer(
                    left: 26,
                    top: 719,
                    width: 318,
                    height: 23,
                    position: position,
                    active: isActive,
                    delayMs: 1800,
                    child: Text(line, style: RewindTextStyles.body(18)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(double ms) {
    final e = rewindProgress(
      ms,
      delayMs: 0,
      durationMs: RewindMotion.soft.duration.inMilliseconds.toDouble(),
      curve: RewindMotion.soft,
    );
    final scale = lerpDouble(0.86, 1, e)!;
    return Positioned(
      left: -19.6,
      top: 99.1,
      width: 366.7,
      height: 476.9,
      child: Opacity(
        opacity: e.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.topLeft,
          transform: Matrix4.identity()
            ..translateByDouble(0, 90 * (1 - e), 0, 1)
            ..rotateZ(lerpDouble(8, 3, e)! * pi / 180)
            ..scaleByDouble(scale, scale, 1, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(35.9),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D000000),
                  offset: Offset(0, 17.9),
                  blurRadius: 38.5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(35.9),
              child: RewindPhoto(file, placeholder: const Color(0x1F151515)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _likeButton(double ms) {
    final t = const Cubic(
      0.2,
      0.9,
      0.3,
      1.3,
    ).transform(((ms - 450) / 520).clamp(0.0, 1.0));
    final scale = t < 0.6 ? 1.18 * t / 0.6 : 1.18 - 0.18 * (t - 0.6) / 0.4;
    return Positioned.fromRect(
      rect: Rect.fromCenter(center: _button, width: 74.4, height: 74.4),
      child: Transform.scale(
        scale: max(0, scale),
        child: Transform.rotate(
          angle: 3.86 * pi / 180,
          child: const CustomPaint(painter: _LikeButtonPainter()),
        ),
      ),
    );
  }
}

Path _heart(double width) {
  final s = width / 100;
  return Path()
    ..moveTo(50 * s, 92 * s)
    ..cubicTo(22 * s, 74 * s, 0, 54 * s, 0, 30 * s)
    ..cubicTo(0, 13 * s, 13 * s, 0, 28 * s, 0)
    ..cubicTo(38 * s, 0, 46 * s, 6 * s, 50 * s, 14 * s)
    ..cubicTo(54 * s, 6 * s, 62 * s, 0, 72 * s, 0)
    ..cubicTo(87 * s, 0, 100 * s, 13 * s, 100 * s, 30 * s)
    ..cubicTo(100 * s, 54 * s, 78 * s, 74 * s, 50 * s, 92 * s)
    ..close();
}

void _paintHeart(Canvas canvas, Offset center, double width, double opacity) {
  if (opacity <= 0) return;
  final heart = _heart(width).shift(Offset(-width / 2, -width * 0.46));
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.saveLayer(
    Rect.fromCircle(center: Offset.zero, radius: width),
    Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
  );
  canvas.drawPath(
    heart.shift(Offset(0, width * 0.11)),
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.05),
  );
  canvas.drawPath(
    heart,
    Paint()
      ..color = RewindColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.11
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(heart, Paint()..color = _likeGreen);
  canvas.restore();
  canvas.restore();
}

class _LikeButtonPainter extends CustomPainter {
  const _LikeButtonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(
      center + const Offset(0, 6.4),
      radius,
      Paint()
        ..color = const Color(0x38000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.85),
    );
    canvas.drawCircle(center, radius, Paint()..color = RewindColors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF3169DE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _paintHeart(canvas, center + const Offset(0, 1.5), 50, 1);
  }

  @override
  bool shouldRepaint(_LikeButtonPainter oldDelegate) => false;
}

typedef _HeartStop = ({
  Offset center,
  double width,
  double turn,
  double opacity,
});

final List<_HeartStop> _stream = () {
  const marks = [
    (283.0, 485.5, 48.8, -3.3, 1.0),
    (288.2, 471.4, 43.4, 15.1, 1.0),
    (275.8, 457.9, 49.2, -7.8, 0.9),
    (289.5, 430.8, 39.3, -11.5, 0.9),
    (274.3, 415.1, 38.0, 4.0, 0.8),
    (260.3, 390.4, 41.5, -13.4, 0.8),
    (276.3, 343.4, 39.5, 14.8, 0.7),
    (244.3, 317.4, 41.6, 13.0, 0.7),
    (223.6, 279.5, 38.7, 0.1, 0.6),
    (195.1, 266.5, 34.4, -7.6, 0.6),
    (191.4, 229.8, 27.4, -1.3, 0.5),
    (202.6, 188.0, 28.3, -10.8, 0.4),
    (232.6, 160.8, 26.5, -2.2, 0.4),
    (233.5, 112.5, 23.5, -2.1, 0.3),
    (287.8, 82.9, 23.3, -9.4, 0.3),
  ];
  final stops = <_HeartStop>[
    for (final (x, y, width, turn, opacity) in marks)
      (
        center:
            Offset(x, y) +
            Offset.fromDirection(turn * pi / 180, width / 2) +
            Offset.fromDirection((turn + 90) * pi / 180, width / 2),
        width: width,
        turn: turn,
        opacity: opacity,
      ),
  ];
  final last = stops.last;
  stops[0] = (
    center: stops[0].center,
    width: stops[0].width,
    turn: stops[0].turn,
    opacity: 0,
  );
  stops.add((
    center: last.center - const Offset(0, 34),
    width: last.width * 0.85,
    turn: last.turn,
    opacity: 0,
  ));
  return stops;
}();

class _HeartStreamPainter extends CustomPainter {
  _HeartStreamPainter(this.ms);

  static const _startMs = 800.0;
  static const _everyMs = 270.0;
  static const _lifeMs = 4100.0;

  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final running = ms - _startMs;
    if (running < 0) return;
    final newest = (running / _everyMs).floor();
    final oldest = max(0, ((running - _lifeMs) / _everyMs).ceil());
    for (var heart = oldest; heart <= newest; heart++) {
      final age = (running - heart * _everyMs) / _lifeMs;
      final span = age * (_stream.length - 1);
      final i = min(span.floor(), _stream.length - 2);
      final q = span - i;
      final a = _stream[i];
      final b = _stream[i + 1];
      final center = Offset.lerp(a.center, b.center, q)!;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(lerpDouble(a.turn, b.turn, q)! * pi / 180);
      _paintHeart(
        canvas,
        Offset.zero,
        lerpDouble(a.width, b.width, q)!,
        lerpDouble(a.opacity, b.opacity, q)!,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HeartStreamPainter oldDelegate) => oldDelegate.ms != ms;
}
