import "dart:math";

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_colours.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

typedef _Painting = ({
  String image,
  String title,
  String original,
  String artist,
});

_Painting _paintingFor(rust.RewindColour colour) => switch (colour) {
  rust.RewindColour.cherryBomb => (
    image: "red",
    title: "Ducky’s Red Studio",
    original: "The Red Studio",
    artist: "Henri Matisse",
  ),
  rust.RewindColour.tangerinePop => (
    image: "orange",
    title: "The Squawk",
    original: "The Scream",
    artist: "Edvard Munch",
  ),
  rust.RewindColour.lemonDrop => (
    image: "yellow",
    title: "The Ducky Kiss",
    original: "The Kiss",
    artist: "Gustav Klimt",
  ),
  rust.RewindColour.pistachio => (
    image: "green",
    title: "The Son of Duck",
    original: "The Son of Man",
    artist: "René Magritte",
  ),
  rust.RewindColour.berryBlue => (
    image: "blue",
    title: "Ducky with a Pearl Earring",
    original: "Girl with a Pearl Earring",
    artist: "Johannes Vermeer",
  ),
  rust.RewindColour.lavenderFizz => (
    image: "lavender",
    title: "Ducky in the Lilies",
    original: "Water Lilies",
    artist: "Claude Monet",
  ),
  rust.RewindColour.bubblegum => (
    image: "pink",
    title: "Ducky on the Swing",
    original: "The Swing",
    artist: "Jean-Honoré Fragonard",
  ),
  rust.RewindColour.hotCocoa => (
    image: "brown",
    title: "Mona Ducky",
    original: "Mona Lisa",
    artist: "Leonardo da Vinci",
  ),
  rust.RewindColour.marshmallow => (
    image: "white",
    title: "Ducky in White",
    original: "Miranda",
    artist: "Thomas Francis Dicksee",
  ),
  rust.RewindColour.midnightCola => (
    image: "black",
    title: "Madame Ducky",
    original: "Madame X",
    artist: "John Singer Sargent",
  ),
};

class ArtTwinPage extends RewindPage {
  const ArtTwinPage(this.colour);

  static const pageKey = "art_twin";

  static const _frame = Rect.fromLTWH(42, 238, 306, 366);
  static const _plaque = Rect.fromLTWH(38, 653, 314, 74);

  final rust.RewindColour colour;

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold => const Duration(milliseconds: 4400);

  @override
  RewindChrome get chrome => RewindChrome(
    foreground: colour.text,
    wordmark: colour.text == RewindColors.ink
        ? RewindColors.ink
        : RewindColors.white,
  );

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final painting = _paintingFor(colour);
    final ink = colour.text;
    final cloth = SvgPicture.file(RewindAssets.file(RewindAssets.artCloth));
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewindBackdrop(
            color: colour.color,
            pattern: RewindStripes(colour.stripe),
          ),
          Semantics(
            label:
                "Your art twin: ${painting.title}, inspired by "
                "${painting.original} by ${painting.artist}.",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  RewindRevealLayer(
                    left: 24,
                    top: 133,
                    width: 342,
                    height: 48,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.rise,
                    child: SizedBox(
                      height: 48,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RewindVoice(
                          you: "YOUR ART TWIN",
                          me: "MY ART TWIN",
                          builder: (text) => Text(
                            text,
                            style: RewindTextStyles.display(
                              40,
                              color: ink,
                              height: 48 / 40,
                            ).copyWith(shadows: _titleShadows(ink)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 24,
                    top: 189,
                    width: 342,
                    height: 22,
                    position: position,
                    active: isActive,
                    delayMs: 200,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RewindVoice(
                          you: "Your photos found their art twin.",
                          me: "My photos found their art twin.",
                          builder: (text) => Text(
                            text,
                            style: RewindTextStyles.body(
                              17,
                              color: ink,
                              height: 1.26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: _frame,
                    child: RewindLeave(
                      position: position,
                      centerY: _frame.center.dy,
                      child: RewindEntrance(
                        preset: RewindPreset.drop,
                        active: isActive,
                        delayMs: 250,
                        child: RewindElapsed(
                          active: isActive,
                          stillMs: _ArtFrame.revealedMs,
                          builder: (context, ms) => _ArtFrame(
                            image: RewindAssets.artTwin(painting.image),
                            cloth: cloth,
                            ms: RewindShareable.capturing(context)
                                ? _ArtFrame.revealedMs
                                : ms,
                          ),
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: _plaque.left,
                    top: _plaque.top,
                    width: _plaque.width,
                    height: _plaque.height,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.pop,
                    delayMs: 2150,
                    child: _Plaque(painting),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Shadow>? _titleShadows(Color ink) => ink == RewindColors.ink
      ? null
      : const [Shadow(color: RewindColors.outline, offset: Offset(0, 3))];
}

class _ArtFrame extends StatelessWidget {
  const _ArtFrame({required this.image, required this.cloth, required this.ms});

  static const revealedMs = 4000.0;
  static const _liftMs = 1350.0;
  static const _liftDurationMs = 900.0;
  static const _canvas = Rect.fromLTWH(33, 33, 240, 300);
  static const _clothRect = Rect.fromLTWH(-13.5, -17, 333, 400);
  static const _sparkles = [
    (center: Offset(52, 333), radius: 15.0, color: RewindColors.cream),
    (center: Offset(256, 32), radius: 20.0, color: RewindColors.hotPink),
  ];

  final String image;
  final Widget cloth;
  final double ms;

  @override
  Widget build(BuildContext context) {
    final lift = rewindProgress(
      ms,
      delayMs: _liftMs,
      durationMs: _liftDurationMs,
      curve: Curves.easeInCubic,
    );
    final fade = rewindProgress(
      ms,
      delayMs: _liftMs + _liftDurationMs * 0.55,
      durationMs: _liftDurationMs * 0.45,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(child: CustomPaint(painter: _FramePainter())),
        Positioned.fromRect(
          rect: _canvas,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.file(
              RewindAssets.file(image),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        ),
        for (final (i, sparkle) in _sparkles.indexed)
          Positioned.fromRect(
            rect: Rect.fromCircle(
              center: sparkle.center,
              radius: sparkle.radius,
            ),
            child: Transform.scale(
              scale: _twinkle(i),
              child: CustomPaint(painter: _SparklePainter(sparkle.color)),
            ),
          ),
        if (fade < 1)
          Positioned.fromRect(
            rect: _clothRect,
            child: Opacity(
              opacity: 1 - fade,
              child: Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()
                  ..translateByDouble(0, -540 * lift, 0, 1)
                  ..rotateZ(-7 * pi / 180 * lift),
                child: cloth,
              ),
            ),
          ),
      ],
    );
  }

  double _twinkle(int i) {
    final since = ms - _liftMs - _liftDurationMs * 0.6 - 150 * i;
    if (since <= 0) return 0;
    final popMs = RewindMotion.pop.duration.inMilliseconds;
    final grow = RewindMotion.pop.transform(min(1.0, since / popMs));
    final breathe = 1 - 0.18 * (0.5 - 0.5 * cos(2 * pi * since / 1500));
    return grow * (since > popMs ? breathe : 1);
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter();

  static const _ink = RewindColors.outline;
  static const _gold = Color(0xFFFFCA39);
  static const _deepGold = Color(0xFFF2A516);
  static const _pearlStep = 11.9;

  @override
  void paint(Canvas canvas, Size size) {
    _panel(canvas, const Rect.fromLTWH(0, 0, 306, 366), 18, _gold, 3);
    _panel(canvas, const Rect.fromLTWH(17, 17, 272, 332), 9, _deepGold, 2);
    _panel(
      canvas,
      const Rect.fromLTWH(26, 26, 254, 314),
      6,
      RewindColors.cream,
      2.5,
    );
    for (var x = 34.0; x <= 261; x += _pearlStep) {
      _pearl(canvas, Offset(x, 10));
      _pearl(canvas, Offset(x, 356));
    }
    for (var y = 34.0; y <= 332; y += _pearlStep) {
      _pearl(canvas, Offset(10, y));
      _pearl(canvas, Offset(296, y));
    }
    for (final corner in const [
      Offset(10, 10),
      Offset(296, 10),
      Offset(10, 356),
      Offset(296, 356),
    ]) {
      _rosette(canvas, corner);
    }
  }

  void _panel(
    Canvas canvas,
    Rect rect,
    double radius,
    Color fill,
    double edge,
  ) {
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rounded, Paint()..color = fill);
    canvas.drawRRect(
      rounded.deflate(edge / 2),
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge,
    );
  }

  void _pearl(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 3, Paint()..color = RewindColors.cream);
    canvas.drawCircle(
      center,
      3,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _rosette(Canvas canvas, Offset center) {
    final edge = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 13.75, Paint()..color = _gold);
    canvas.drawCircle(center, 13.75, edge..strokeWidth = 2.5);
    canvas.drawCircle(center, 5.5, Paint()..color = _deepGold);
    canvas.drawCircle(center, 5.5, edge..strokeWidth = 2);
    canvas.drawCircle(
      center + const Offset(-5, -6),
      2,
      Paint()..color = RewindColors.cream,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => false;
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final k = 0.22 * r;
    final star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(star, Paint()..color = color);
    canvas.drawPath(
      star,
      Paint()
        ..color = RewindColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => oldDelegate.color != color;
}

class _Plaque extends StatelessWidget {
  const _Plaque(this.painting);

  static const _muted = Color(0xB8151515);

  final _Painting painting;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 314,
      height: 74,
      child: CustomPaint(
        painter: const _PlatePainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8.5, 24, 0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _line(
                  painting.title,
                  RewindTextStyles.body(
                    18,
                    color: RewindColors.ink,
                    height: 1.26,
                  ),
                ),
                const SizedBox(height: 1),
                _line(
                  "Inspired by ${painting.original}",
                  RewindTextStyles.body(
                    12.5,
                    color: _muted,
                    height: 1.26,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                _line(
                  painting.artist,
                  RewindTextStyles.body(
                    12.5,
                    color: _muted,
                    height: 1.26,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String text, TextStyle style) =>
      Text(text, style: style, maxLines: 1);
}

class _PlatePainter extends CustomPainter {
  const _PlatePainter();

  static const _ink = RewindColors.outline;

  @override
  void paint(Canvas canvas, Size size) {
    final plate = Path()
      ..moveTo(38, 0)
      ..lineTo(276, 0)
      ..cubicTo(288, 0, 298, 8, 300, 19)
      ..cubicTo(308, 22, 314, 29, 314, 37)
      ..cubicTo(314, 45, 308, 52, 300, 55)
      ..cubicTo(298, 66, 288, 74, 276, 74)
      ..lineTo(38, 74)
      ..cubicTo(26, 74, 16, 66, 14, 55)
      ..cubicTo(6, 52, 0, 45, 0, 37)
      ..cubicTo(0, 29, 6, 22, 14, 19)
      ..cubicTo(16, 8, 26, 0, 38, 0)
      ..close();
    canvas.drawPath(plate, Paint()..color = RewindColors.cream);
    canvas.drawPath(
      plate,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (final screw in const [Offset(17, 37), Offset(297, 37)]) {
      canvas.drawCircle(screw, 4.25, Paint()..color = _FramePainter._gold);
      canvas.drawCircle(
        screw,
        4.25,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => false;
}
