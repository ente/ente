import "dart:math";
import "dart:ui" show ImageFilter;

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:intl/intl.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_rituals.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _defaultIcons = ["💪", "🎨", "🪴", "👟"];

typedef _Spot = ({Offset center, double size, double turn, int delayMs});

const List<_Spot> _stickerSpots = [
  (center: Offset(86.9, 104.9), size: 86, turn: 21.9, delayMs: 700),
  (center: Offset(291.2, 105.7), size: 108, turn: -47.5, delayMs: 820),
  (center: Offset(89.2, 423.9), size: 129, turn: 7, delayMs: 940),
  (center: Offset(280.1, 431.3), size: 119, turn: -14, delayMs: 1060),
];

typedef _Tile = ({
  Offset center,
  Size size,
  double turn,
  bool curl,
  int delayMs,
});

const _Tile _leftTile = (
  center: Offset(74.5, 700.9),
  size: Size(94.7, 104),
  turn: -17.43,
  curl: true,
  delayMs: 1700,
);
const _Tile _middleTile = (
  center: Offset(195.7, 647.2),
  size: Size(172.6, 124.4),
  turn: 0,
  curl: false,
  delayMs: 1550,
);
const _Tile _rightTile = (
  center: Offset(311.7, 707.3),
  size: Size(95, 104),
  turn: 22.7,
  curl: true,
  delayMs: 1850,
);

class RitualStreakPage extends RewindPage {
  const RitualStreakPage(this.rituals);

  static const pageKey = "ritual_streak";

  static const _yellow = Color(0xFFFFE11E);

  final RewindRituals rituals;

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold => const Duration(milliseconds: 3000);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final streak = rewindCount(rituals.longestStreak);
    final month = DateFormat.MMMM(
      "en_US",
    ).format(DateTime(RewindEdition.year, rituals.busiestMonth));
    final icons = [
      ...rituals.icons,
      ..._defaultIcons.where((icon) => !rituals.icons.contains(icon)),
    ];
    final lightning = SvgPicture.file(
      RewindAssets.file(RewindAssets.lightningSticker),
    );
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewindBackdrop(
            color: const Color(0xFFF0713F),
            pattern: RewindStripes(
              const Color(0xFFF5754A).withValues(alpha: 0.78),
            ),
            grain: 0.045,
          ),
          Semantics(
            label:
                "Your longest ritual streak: $streak. "
                "${rewindCounted(rituals.checkIns, "check-in", "check-ins")} "
                "this year, most in $month. "
                "${rewindCounted(rituals.continued, "ritual", "rituals")} "
                "still going.",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 260,
                      child: RewindEntrance(
                        preset: RewindPreset.bubble,
                        active: isActive,
                        origin: RewindStage.alignmentOf(const Offset(195, 261)),
                        child: const CustomPaint(painter: _BlobPainter()),
                      ),
                    ),
                  ),
                  for (final (i, spot) in _stickerSpots.indexed)
                    Positioned.fromRect(
                      rect: Rect.fromCenter(
                        center: spot.center,
                        width: spot.size,
                        height: spot.size,
                      ),
                      child: RewindLeave(
                        position: position,
                        centerY: spot.center.dy,
                        child: RewindEntrance(
                          preset: RewindPreset.pop,
                          active: isActive,
                          delayMs: spot.delayMs,
                          child: Transform.rotate(
                            angle: spot.turn * pi / 180,
                            child: _EmojiSticker(icons[i], size: spot.size),
                          ),
                        ),
                      ),
                    ),
                  RewindRevealLayer(
                    left: 24,
                    top: 166,
                    width: 342,
                    height: 22,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.rise,
                    delayMs: 150,
                    child: Center(
                      child: RewindVoice(
                        you: "YOUR LONGEST STREAK",
                        me: "MY LONGEST STREAK",
                        builder: (text) => RewindOutlinedText(
                          text,
                          style: RewindTextStyles.display(
                            26.012,
                            color: _yellow,
                            height: 0.84,
                          ),
                          outline: 2.015,
                          shadow: const Offset(0.956, 1.148),
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 24,
                    top: 194,
                    width: 342,
                    height: 178,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: 350,
                    child: Center(
                      child: _Streak(
                        streak,
                        lightning: RewindEntrance(
                          preset: RewindPreset.pop,
                          active: isActive,
                          delayMs: 900,
                          child: lightning,
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 34,
                    top: 509,
                    width: 320,
                    height: 66,
                    position: position,
                    active: isActive,
                    delayMs: 1250,
                    child: Column(
                      children: [
                        RewindVoice(
                          you: "Apparently,\nconsistency is your thing.",
                          me: "Apparently,\nconsistency is my thing.",
                          builder: (text) => Text(
                            text,
                            textAlign: TextAlign.center,
                            style: RewindTextStyles.body(
                              20,
                              height: 26 / 20,
                              color: RewindColors.white,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 96,
                          height: 11,
                          child: CustomPaint(painter: _UnderlinePainter()),
                        ),
                      ],
                    ),
                  ),
                  _tile(
                    _leftTile,
                    rewindCount(rituals.checkIns),
                    rituals.checkIns == 1
                        ? "Check-in\nthis year"
                        : "Check-ins\nthis year",
                    position,
                    isActive,
                  ),
                  _tile(
                    _rightTile,
                    rewindCount(rituals.continued),
                    rituals.continued == 1
                        ? "Ritual\ncontinued"
                        : "Rituals\ncontinued",
                    position,
                    isActive,
                  ),
                  _tile(
                    _middleTile,
                    month,
                    "Most active\nmonth",
                    position,
                    isActive,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    _Tile tile,
    String value,
    String label,
    double position,
    bool isActive,
  ) {
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: tile.center,
        width: tile.size.width,
        height: tile.size.height,
      ),
      child: RewindLeave(
        position: position,
        centerY: tile.center.dy,
        child: RewindEntrance(
          preset: RewindPreset.drop,
          active: isActive,
          delayMs: tile.delayMs,
          child: Transform.rotate(
            angle: tile.turn * pi / 180,
            child: _PaperTile(value: value, label: label, curl: tile.curl),
          ),
        ),
      ),
    );
  }
}

class _Streak extends StatelessWidget {
  const _Streak(this.value, {required this.lightning});

  static const _lightningSize = Size(54, 76);

  final String value;
  final Widget lightning;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.only(right: 22),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            RewindOutlinedText(
              value,
              style: RewindTextStyles.numeral(
                194,
                color: RewindColors.white,
              ).copyWith(height: 0.92),
              outline: 4,
              ink: RewindColors.outline,
              shadow: const Offset(5, 7),
            ),
            Positioned(
              right: -22,
              top: 1,
              width: _lightningSize.width,
              height: _lightningSize.height,
              child: lightning,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiSticker extends StatelessWidget {
  const _EmojiSticker(this.emoji, {required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final glyph = Text(
      emoji,
      textAlign: TextAlign.center,
      style: TextStyle(inherit: false, fontSize: size * 0.865, height: 1),
    );
    final border = size * 0.055;
    Widget silhouette(Color color, ImageFilter filter) => ImageFiltered(
      imageFilter: filter,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: glyph,
      ),
    );
    final dilate = ImageFilter.dilate(radiusX: border, radiusY: border);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(0, size * 0.02),
            child: silhouette(
              const Color(0x33000000),
              ImageFilter.compose(
                outer: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                inner: dilate,
              ),
            ),
          ),
          silhouette(RewindColors.cream, dilate),
          glyph,
        ],
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({
    required this.value,
    required this.label,
    required this.curl,
  });

  final String value;
  final String label;
  final bool curl;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaperPainter(curl: curl),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: constraints.maxWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RewindOutlinedText(
                      value,
                      style: RewindTextStyles.numeral(
                        38.98,
                        color: RewindColors.white,
                      ).copyWith(height: 1.1),
                      outline: 1.392,
                      ink: RewindColors.outline,
                      shadow: const Offset(1.856, 1.856),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: RewindTextStyles.body(13.92, height: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({required this.curl});

  static const _fill = Color(0xFFE86436);
  static const _shine = Color(0xFFFFAF93);
  static const _shade = Color(0xFFC94B1E);
  static const _edge = Color(0xFF893011);
  static const _edgeWidth = 2.784;

  final bool curl;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(13),
    );
    canvas.drawRRect(paper, Paint()..color = _fill);
    canvas.save();
    canvas.clipRRect(paper);
    canvas.drawPath(
      Path()
        ..moveTo(4, 12)
        ..quadraticBezierTo(5, 4.5, 16, 4.2)
        ..lineTo(size.width - 14, 4.2)
        ..quadraticBezierTo(size.width - 4.5, 4.5, size.width - 4.2, 14)
        ..lineTo(size.width - 4.2, size.height * 0.55),
      Paint()
        ..color = _shine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round,
    );
    if (curl) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width, size.height * 0.62)
          ..quadraticBezierTo(
            size.width * 0.82,
            size.height * 0.9,
            size.width * 0.42,
            size.height,
          )
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = _shade,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - _edgeWidth * 2, size.width, _edgeWidth),
      Paint()..color = _edge,
    );
    canvas.restore();
    canvas.drawRRect(
      paper.deflate(_edgeWidth / 2),
      Paint()
        ..color = _edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = _edgeWidth,
    );
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) => oldDelegate.curl != curl;
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter();

  static const _colour = Color(0xFFE86436);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(40, 92);
    canvas.drawPath(
      Path()
        ..moveTo(2.0982, 135.046)
        ..cubicTo(12.8605, 19.6691, 61.2908, -6.30318, 139.562, 1.18884)
        ..cubicTo(207.071, 7.18115, 297.572, 40.6481, 308.334, 148.533)
        ..cubicTo(319.097, 256.418, 302.464, 342.327, 160.597, 337.831)
        ..cubicTo(18.7308, 333.336, -8.66409, 250.423, 2.0982, 135.046)
        ..close(),
      Paint()..color = _colour,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(21, 69);
    canvas.drawPath(
      Path()
        ..moveTo(6.00928, 128.189)
        ..cubicTo(19.8152, 26.6278, 69.1222, 3.73303, 156.888, 1.11245)
        ..cubicTo(307.766, -3.38914, 349.184, 128.189, 342.281, 228.749)
        ..cubicTo(335.378, 329.308, 305.794, 383.342, 151.464, 379.84)
        ..cubicTo(-2.86593, 376.338, -7.79659, 229.75, 6.00928, 128.189)
        ..close(),
      Paint()
        ..color = _colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) => false;
}

class _UnderlinePainter extends CustomPainter {
  const _UnderlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(1.5, 8.607)
        ..cubicTo(27.103, -0.324, 72.639, 0.497, 94.473, 3.856),
      Paint()
        ..color = RitualStreakPage._yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_UnderlinePainter oldDelegate) => false;
}
