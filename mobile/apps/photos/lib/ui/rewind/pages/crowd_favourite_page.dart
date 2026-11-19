import "dart:math";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
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

const _likeGreen = Color(0xFF08C225);
const _photoRect = Rect.fromLTWH(30, 100, 330, 428);
const _photoTurn = 3.0;
const _frame = 6.0;
const _corner = 35.9;

typedef _Heart = ({Offset center, double size, double turn, bool front});

const List<_Heart> _hearts = [
  (center: Offset(334, 508), size: 80, turn: 12, front: true),
  (center: Offset(50, 118), size: 60, turn: -16, front: true),
  (center: Offset(350, 116), size: 44, turn: 18, front: true),
  (center: Offset(44, 504), size: 42, turn: -14, front: true),
  (center: Offset(282, 562), size: 36, turn: -10, front: true),
  (center: Offset(18, 250), size: 32, turn: 14, front: false),
  (center: Offset(118, 76), size: 30, turn: 6, front: false),
  (center: Offset(282, 72), size: 26, turn: -12, front: false),
  (center: Offset(20, 392), size: 24, turn: -10, front: false),
  (center: Offset(326, 602), size: 24, turn: 10, front: true),
  (center: Offset(372, 474), size: 22, turn: -14, front: false),
  (center: Offset(94, 556), size: 22, turn: 12, front: true),
  (center: Offset(200, 60), size: 18, turn: 4, front: false),
  (center: Offset(232, 556), size: 16, turn: -8, front: true),
];

class CrowdFavouritePage extends RewindPage {
  const CrowdFavouritePage(this.file);

  final EnteFile file;

  @override
  String get key => "crowd_favourite";

  @override
  Duration? get reelHold =>
      const Duration(milliseconds: 2700 + RewindMotion.reelReadingMs);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    const line = "Your most liked photo.";
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
            label: "Crowd favourite. $line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: _photoRect.center.dy,
                      child: RewindElapsed(
                        active: isActive && !RewindPageScope.coveredOf(context),
                        stillMs: 6000,
                        builder: (context, ms) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _HeartsPainter(ms, front: false),
                              ),
                            ),
                            _photo(ms),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _HeartsPainter(ms, front: true),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 644,
                    width: 334,
                    maxWidth: 334,
                    height: 37,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: 1500,
                    child: RewindOutlinedText(
                      "CROWD FAVOURITE",
                      style: RewindTextStyles.display(32, height: 1.15),
                      outline: 1.6,
                      shadow: const Offset(2, 3),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 704,
                    width: 334,
                    height: 23,
                    position: position,
                    active: isActive,
                    delayMs: 1800,
                    child: RewindVoice(
                      you: line,
                      me: "My most liked photo.",
                      builder: (text) => Text(
                        text,
                        textAlign: TextAlign.center,
                        style: RewindTextStyles.body(18),
                      ),
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

  Widget _photo(double ms) {
    final e = rewindProgress(
      ms,
      delayMs: 0,
      durationMs: RewindMotion.soft.duration.inMilliseconds.toDouble(),
      curve: RewindMotion.soft,
    );
    final scale = lerpDouble(0.86, 1, e)!;
    return Positioned.fromRect(
      rect: _photoRect,
      child: Opacity(
        opacity: e.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, 90 * (1 - e), 0, 1)
            ..rotateZ(lerpDouble(8, _photoTurn, e)! * pi / 180)
            ..scaleByDouble(scale, scale, 1, 1),
          child: Container(
            padding: const EdgeInsets.all(_frame),
            decoration: BoxDecoration(
              color: RewindColors.white,
              borderRadius: BorderRadius.circular(_corner),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D000000),
                  offset: Offset(0, 17.9),
                  blurRadius: 38.5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_corner - _frame),
              child: RewindPhoto(file, placeholder: const Color(0x1F151515)),
            ),
          ),
        ),
      ),
    );
  }
}

Path _heart(double size) {
  final s = size / 100;
  return Path()
    ..moveTo(50 * s, 87.49 * s)
    ..cubicTo(49.49 * s, 87.49 * s, 48.99 * s, 87.36 * s, 48.53 * s, 87.12 * s)
    ..cubicTo(47.86 * s, 86.75 * s, 47.33 * s, 86.45 * s, 46.8 * s, 86.14 * s)
    ..cubicTo(40.46 * s, 82.37 * s, 34.53 * s, 77.95 * s, 29.12 * s, 72.93 * s)
    ..cubicTo(19.53 * s, 63.99 * s, 9.37 * s, 50.71 * s, 9.37 * s, 34.36 * s)
    ..cubicTo(9.37 * s, 22.16 * s, 19.64 * s, 12.49 * s, 32.03 * s, 12.49 * s)
    ..cubicTo(35.48 * s, 12.47 * s, 38.88 * s, 13.23 * s, 41.99 * s, 14.71 * s)
    ..cubicTo(45.1 * s, 16.19 * s, 47.84 * s, 18.35 * s, 50 * s, 21.04 * s)
    ..cubicTo(52.16 * s, 18.35 * s, 54.9 * s, 16.19 * s, 58.01 * s, 14.71 * s)
    ..cubicTo(61.12 * s, 13.23 * s, 64.53 * s, 12.47 * s, 67.97 * s, 12.49 * s)
    ..cubicTo(80.36 * s, 12.49 * s, 90.62 * s, 22.16 * s, 90.62 * s, 34.36 * s)
    ..cubicTo(90.62 * s, 50.72 * s, 80.47 * s, 63.99 * s, 70.88 * s, 72.93 * s)
    ..cubicTo(65.47 * s, 77.94 * s, 59.54 * s, 82.37 * s, 53.2 * s, 86.14 * s)
    ..cubicTo(52.67 * s, 86.45 * s, 52.14 * s, 86.75 * s, 51.47 * s, 87.12 * s)
    ..cubicTo(51.01 * s, 87.36 * s, 50.51 * s, 87.49 * s, 50 * s, 87.49 * s)
    ..close();
}

class _HeartsPainter extends CustomPainter {
  _HeartsPainter(this.ms, {required this.front});

  static const _firstMs = 650.0;
  static const _everyMs = 55.0;
  static const _floatPx = 3.0;
  static const _floatMs = 2600.0;

  final double ms;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, heart) in _hearts.indexed) {
      if (heart.front != front) continue;
      final pop = RewindMotion.pop.transform(
        ((ms - _firstMs - _everyMs * i) /
                RewindMotion.pop.duration.inMilliseconds)
            .clamp(0.0, 1.0),
      );
      if (pop <= 0) continue;
      final drift = _floatPx * sin(2 * pi * ms / _floatMs + i * 1.3);
      canvas.save();
      canvas.translate(heart.center.dx, heart.center.dy + drift);
      canvas.rotate(heart.turn * pi / 180);
      canvas.scale(pop);
      _paintHeart(canvas, heart.size);
      canvas.restore();
    }
  }

  void _paintHeart(Canvas canvas, double size) {
    final heart = _heart(size).shift(Offset(-size / 2, -size / 2));
    final rim = size * 0.0937;
    canvas.drawPath(
      heart.shift(Offset(0, size * 0.0878)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.0732),
    );
    canvas.drawPath(
      heart,
      Paint()
        ..color = RewindColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(heart, Paint()..color = _likeGreen);
  }

  @override
  bool shouldRepaint(_HeartsPainter oldDelegate) =>
      oldDelegate.ms != ms || oldDelegate.front != front;
}
