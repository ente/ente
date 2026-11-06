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
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _Pose = ({Offset center, double turn, double scale, double opacity});

const _Pose _gone = (
  center: Offset(-170, 380),
  turn: -30,
  scale: 0.892,
  opacity: 1,
);
const _Pose _left = (
  center: Offset(92.1, 363.5),
  turn: -19.8,
  scale: 0.892,
  opacity: 1,
);
const _Pose _front = (
  center: Offset(194.6, 340.2),
  turn: 0,
  scale: 1,
  opacity: 1,
);
const _Pose _right = (
  center: Offset(297.9, 363.5),
  turn: 19.8,
  scale: 0.892,
  opacity: 1,
);
const _Pose _coming = (
  center: Offset(560, 380),
  turn: 30,
  scale: 0.892,
  opacity: 1,
);
const _slots = [_gone, _left, _front, _right, _coming];

const _Pose _frontFrom = (
  center: Offset(194.6, 400),
  turn: 0,
  scale: 0.9,
  opacity: 0,
);
const _Pose _backFrom = (
  center: Offset(194.6, 350),
  turn: 0,
  scale: 0.892,
  opacity: 0,
);

_Pose _lerp(_Pose a, _Pose b, double t) => (
  center: Offset.lerp(a.center, b.center, t)!,
  turn: lerpDouble(a.turn, b.turn, t)!,
  scale: lerpDouble(a.scale, b.scale, t)!,
  opacity: lerpDouble(a.opacity, b.opacity, t)!,
);

class FavouritesPage extends RewindPage {
  const FavouritesPage(this.favourites, this.photos);

  static const _firstTurnMs = 1100.0;
  static const _beatMs = 1800.0;
  static const _turnMs = 760.0;

  final rust.Favourites favourites;
  final List<EnteFile> photos;

  @override
  String get key => "favourites";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final count = favourites.photoCount;
    final title = rewindCounted(count, "FAVOURITE", "FAVOURITES");
    const line = "Not that you were counting. We were.";
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewindBackdrop(
            color: const Color(0xFFFB4196),
            pattern: RewindStripes(
              const Color(0xFFFF4D9F).withValues(alpha: 0.42),
            ),
          ),
          Semantics(
            label: "${title.toLowerCase()}. $line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 340,
                      child: RewindElapsed(
                        active: isActive,
                        stillMs: _firstTurnMs,
                        builder: (context, ms) =>
                            Stack(clipBehavior: Clip.none, children: _deck(ms)),
                      ),
                    ),
                  ),
                  if (count >= 100)
                    RewindRevealLayer(
                      left: 277,
                      top: 466,
                      height: 104,
                      position: position,
                      active: isActive,
                      preset: RewindPreset.pop,
                      delayMs: 1150,
                      child: Image.file(
                        RewindAssets.file(RewindAssets.hundredSticker),
                        width: 110,
                        height: 104,
                      ),
                    ),
                  RewindRevealLayer(
                    left: 38.9,
                    top: 110.9,
                    height: 70,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.twinkle,
                    delayMs: 1250,
                    child: RewindIdleLoop(
                      idle: RewindIdle.twinkle,
                      active: isActive,
                      delayMs: 1950,
                      child: const CustomPaint(
                        size: Size.square(70),
                        painter: _SparklePainter(),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 664,
                    width: 331,
                    maxWidth: 331,
                    height: 40,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: 1300,
                    child: RewindOutlinedText(
                      title,
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
                    top: 718,
                    width: 316,
                    height: 22,
                    position: position,
                    active: isActive,
                    delayMs: 1600,
                    child: Text(line, style: RewindTextStyles.body(17)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _deck(double ms) {
    if (photos.length < 3) {
      return [
        if (photos.length == 2)
          _card(photos[1], 1, _entering(_backFrom, _right, ms, 320)),
        if (photos.isNotEmpty)
          _card(photos[0], 0, _entering(_frontFrom, _front, ms, 0)),
      ];
    }
    if (ms <= _firstTurnMs) {
      return [
        _card(photos.last, 0, _entering(_backFrom, _left, ms, 260)),
        _card(photos[1], 2, _entering(_backFrom, _right, ms, 320)),
        _card(photos[0], 1, _entering(_frontFrom, _front, ms, 0)),
      ];
    }
    final since = ms - _firstTurnMs;
    final turn = (since / _beatMs).floor();
    final progress = min(1.0, (since - turn * _beatMs) / _turnMs);
    Widget card(int relative) {
      final sequence = turn + relative;
      return _card(
        photos[(sequence - 1) % photos.length],
        sequence,
        _lerp(_slots[relative + 1], _slots[relative], progress),
      );
    }

    return [card(0), card(3), card(1), card(2)];
  }

  _Pose _entering(_Pose from, _Pose to, double ms, int delayMs) => _lerp(
    from,
    to,
    rewindProgress(
      ms,
      delayMs: delayMs.toDouble(),
      durationMs: RewindMotion.soft.duration.inMilliseconds.toDouble(),
      curve: RewindMotion.soft,
    ),
  );

  Widget _card(EnteFile file, int sequence, _Pose pose) {
    return Positioned.fromRect(
      key: ValueKey(sequence),
      rect: Rect.fromCenter(
        center: pose.center,
        width: _FavouriteCard.size.width,
        height: _FavouriteCard.size.height,
      ),
      child: Opacity(
        opacity: pose.opacity.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(pose.turn * pi / 180)
            ..scaleByDouble(pose.scale, pose.scale, 1, 1),
          child: _FavouriteCard(file),
        ),
      ),
    );
  }
}

class _FavouriteCard extends StatelessWidget {
  const _FavouriteCard(this.file);

  static const size = Size(302.042, 380.35);

  final EnteFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.95),
      decoration: BoxDecoration(
        color: RewindColors.cream,
        borderRadius: BorderRadius.circular(26.85),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19.02),
        child: RewindPhoto(file, placeholder: const Color(0x1F151515)),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 70);
    final star = Path()
      ..moveTo(46.38, 2.5)
      ..cubicTo(42.22, 22.23, 49.03, 36.86, 66.81, 46.38)
      ..cubicTo(47.07, 42.22, 32.45, 49.03, 22.93, 66.8)
      ..cubicTo(27.09, 47.07, 20.28, 32.45, 2.5, 22.93)
      ..cubicTo(22.23, 27.09, 36.86, 20.28, 46.38, 2.5)
      ..close();
    canvas.drawPath(star, Paint()..color = RewindColors.yellow);
    canvas.drawPath(
      star,
      Paint()
        ..color = RewindColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => false;
}
