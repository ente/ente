import "dart:math";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_colours.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";
import "package:photos/ui/rewind/widgets/rewind_wordmark.dart";
import "package:photos/utils/share_util.dart";

const _summaryInk = Color(0xFF131313);
const _summaryGreen = Color(0xFF0EBF29);

enum _Cutout {
  outing(Offset(101, 211), Size(152.172, 119.006), -4),
  circle(Offset(277.8, 194.4), Size(126.81, 126.81), 3),
  tall(Offset(281.8, 334.4), Size(146.319, 169.73), 3),
  heart(Offset(152.9, 309.3), Size(121, 113), 7),
  flower(Offset(73.4, 387.1), Size(105.35, 105.35), -9),
  star(Offset(204.4, 413.3), Size(123.883, 116.08), 9);

  const _Cutout(this.center, this.size, this.turn);

  final Offset center;
  final Size size;
  final double turn;

  RewindCutoutShape? get shape => switch (this) {
    circle => RewindCutoutShape.circle,
    heart => RewindCutoutShape.heart,
    flower => RewindCutoutShape.flower,
    star => RewindCutoutShape.star,
    outing || tall => null,
  };
}

class ScrapbookPage extends RewindPage {
  const ScrapbookPage({
    required this.report,
    required this.photos,
    required this.people,
    required this.cityNames,
  });

  final rust.RewindReport report;
  final List<EnteFile> photos;
  final List<RewindFace> people;
  final List<String> cityNames;

  @override
  String get key => "scrapbook";

  @override
  RewindChrome get chrome =>
      const RewindChrome(foreground: RewindColors.cream, muteButton: false);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return _Scrapbook(page: this, isActive: isActive);
  }
}

class _Scrapbook extends StatefulWidget {
  const _Scrapbook({required this.page, required this.isActive});

  final ScrapbookPage page;
  final bool isActive;

  @override
  State<_Scrapbook> createState() => _ScrapbookState();
}

class _ScrapbookState extends State<_Scrapbook> {
  static final _logger = Logger("ScrapbookPage");

  final _card = RewindShareCard(branded: false);
  final _button = GlobalKey();
  var _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    _sharing = true;
    try {
      await shareRewindCard(
        _card,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
        wordmark: Rect.zero,
        wordmarkColor: RewindColors.cream,
        origin: shareButtonRect(context, _button),
      );
    } catch (error, stackTrace) {
      _logger.warning("Failed to share the scrapbook", error, stackTrace);
    } finally {
      _sharing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final active = widget.isActive;
    final screen = MediaQuery.sizeOf(context);
    final inset =
        MediaQuery.paddingOf(context).bottom / RewindStage.scaleFor(screen);
    final lift = max(0.0, inset - 18);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: _card.boundary,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const RewindBackdrop(
                color: RewindColors.green,
                pattern: RewindStripes(_summaryGreen),
              ),
              RewindStage(
                children: [
                  Positioned(
                    left: 33.2,
                    top: 48.1,
                    child: RewindEntrance(
                      preset: RewindPreset.line,
                      active: active,
                      delayMs: 350,
                      child: const RewindWordmark(
                        color: RewindColors.cream,
                        width: 88.8,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    top: 69.7,
                    child: RewindEntrance(
                      preset: RewindPreset.pop,
                      active: active,
                      delayMs: 420,
                      child: Semantics(
                        label: "Rewind 2026",
                        child: Image.file(
                          RewindAssets.file(RewindAssets.compactHeader),
                          width: 239,
                          height: 45,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: const Rect.fromLTWH(29.73, 137.55, 329.706, 311.172),
                    child: RewindEntrance(
                      preset: RewindPreset.pop,
                      active: active,
                      delayMs: 150,
                      child: Transform.rotate(
                        angle: 0.13 * pi / 180,
                        child: const CustomPaint(painter: _GraphPaperPainter()),
                      ),
                    ),
                  ),
                  for (final (index, cutout) in _Cutout.values.indexed)
                    if (index < page.photos.length)
                      Positioned.fromRect(
                        rect: Rect.fromCenter(
                          center: cutout.center,
                          width: cutout.size.width,
                          height: cutout.size.height,
                        ),
                        child: RewindEntrance(
                          preset: RewindPreset.drop,
                          active: active,
                          delayMs: 300 + 70 * index,
                          child: Transform.rotate(
                            angle: cutout.turn * pi / 180,
                            child: _photoCutout(cutout, page.photos[index]),
                          ),
                        ),
                      ),
                  Positioned.fill(
                    child: RewindElapsed(
                      active: active,
                      stillMs: 2000,
                      builder: (context, ms) => Transform.translate(
                        offset: Offset(
                          0,
                          380 *
                              (1 -
                                  rewindProgress(
                                    ms,
                                    delayMs: 380,
                                    durationMs: 792,
                                    curve: RewindMotion.soft,
                                  )),
                        ),
                        child: _Summary(page: page),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        RewindStage(
          children: [
            Positioned(
              left: 30,
              top: 760 - lift,
              width: 330,
              height: 66,
              child: RewindElapsed(
                active: active,
                stillMs: 2000,
                builder: (context, ms) => Transform.translate(
                  offset: Offset(
                    0,
                    380 *
                        (1 -
                            rewindProgress(
                              ms,
                              delayMs: 380,
                              durationMs: 792,
                              curve: RewindMotion.soft,
                            )),
                  ),
                  child: _ShareButton(key: _button, onTap: _share),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _photoCutout(_Cutout cutout, EnteFile file) {
    final shape = cutout.shape;
    final photo = RewindPhoto(file, placeholder: const Color(0x1F151515));
    if (shape != null) return RewindCutout(shape: shape, photo: photo);
    return Container(
      padding: const EdgeInsets.all(2.926),
      decoration: BoxDecoration(
        color: RewindColors.cream,
        borderRadius: BorderRadius.circular(0.975),
        boxShadow: const [
          BoxShadow(
            color: Color(0x21000000),
            offset: Offset(0, 1.951),
            blurRadius: 1.951,
          ),
        ],
      ),
      child: photo,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.page});

  final ScrapbookPage page;

  @override
  Widget build(BuildContext context) {
    final report = page.report;
    final totals = report.totals;
    final colour = report.colour?.colour;
    final names = report.peopleRace == null
        ? const <String>[]
        : [
            for (final person in page.people)
              if (person.name?.trim().isNotEmpty ?? false) person.name!.trim(),
          ].take(3).toList();
    final places = report.places == null
        ? const <String>[]
        : page.cityNames.take(3).toList();
    final firstRow = totals != null || colour != null;
    final secondTop = firstRow ? 620.0 : 520.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          left: -45,
          top: 462,
          width: 480,
          height: 1000,
          child: CustomPaint(painter: _ScallopPainter()),
        ),
        if (totals != null) ...[
          const Positioned(
            left: 35,
            top: 520,
            child: _Label("Photos uploaded"),
          ),
          Positioned(
            left: 35,
            top: 545,
            child: _Uploads(files: totals.files, topPercent: totals.topPercent),
          ),
        ],
        if (colour != null) ...[
          const Positioned(
            left: 212,
            top: 520,
            child: _Label("Colour of the year"),
          ),
          Positioned(
            left: 212,
            top: 546,
            width: 153,
            height: 67,
            child: _Colour(name: colour.label, color: colour.color),
          ),
        ],
        if (names.isNotEmpty) ...[
          Positioned(
            left: 35,
            top: secondTop,
            child: const _Label("Top people"),
          ),
          Positioned(
            left: 35,
            top: secondTop + 24,
            width: 153,
            child: _Ranking(names),
          ),
        ],
        if (places.isNotEmpty) ...[
          Positioned(
            left: 212,
            top: secondTop,
            child: const _Label("Top places"),
          ),
          Positioned(
            left: 212,
            top: secondTop + 24,
            width: 153,
            child: _Ranking(places),
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: RewindTextStyles.body(14, color: _summaryInk, height: 1.26),
    );
  }
}

class _Uploads extends StatelessWidget {
  const _Uploads({required this.files, required this.topPercent});

  final int files;
  final int? topPercent;

  @override
  Widget build(BuildContext context) {
    final topPercent = this.topPercent;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: topPercent == null ? 153 : 130),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: RewindOutlinedText(
              rewindCount(files),
              style: RewindTextStyles.display(
                47,
                color: _summaryGreen,
                height: 50 / 47,
              ),
              outline: 2,
              shadow: const Offset(2, 3),
              ink: _summaryInk,
            ),
          ),
        ),
        if (topPercent != null)
          Positioned(right: -40.8, top: -29, child: _Seal(topPercent)),
      ],
    );
  }
}

class _Seal extends StatelessWidget {
  const _Seal(this.topPercent);

  final int topPercent;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 58.8,
      child: Transform.rotate(
        angle: -15 * pi / 180,
        child: Center(
          child: SizedBox.square(
            dimension: 48,
            child: CustomPaint(
              painter: const _SealPainter(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("TOP", style: RewindTextStyles.body(8, height: 10 / 8)),
                  Text(
                    "$topPercent%",
                    style: RewindTextStyles.body(16, height: 18 / 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final seal = Path()
      ..addPolygon([
        for (var i = 0; i < 160; i++)
          center +
              Offset.fromDirection(
                i / 160 * 2 * pi,
                radius * (0.9 + 0.1 * cos(8 * i / 160 * 2 * pi)),
              ),
      ], true);
    canvas.drawPath(seal, Paint()..color = _summaryGreen);
    canvas.save();
    canvas.clipPath(seal);
    canvas.drawPath(
      seal,
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SealPainter oldDelegate) => false;
}

class _Colour extends StatelessWidget {
  const _Colour({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: _summaryInk, width: 1.5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: _summaryInk, offset: Offset(2, 3)),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              name.replaceAll(" ", "\n"),
              style: RewindTextStyles.tag(
                22,
                color: _summaryInk,
              ).copyWith(height: 1.11),
            ),
          ),
        ),
      ],
    );
  }
}

class _Ranking extends StatelessWidget {
  const _Ranking(this.names);

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, name) in names.indexed)
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: RewindColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "${index + 1}",
                    style: RewindTextStyles.body(11, height: 1),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RewindTextStyles.body(
                      16,
                      color: _summaryInk,
                      weight: FontWeight.w400,
                      height: 1.375,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Share your Rewind",
      child: RewindPressable(
        onTap: onTap,
        pressedScale: 0.97,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RewindColors.candyPink,
            border: Border.all(color: RewindColors.ink, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
          child: ExcludeSemantics(
            child: Text(
              "Share your Rewind",
              style: RewindTextStyles.body(17, height: 22 / 17),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphPaperPainter extends CustomPainter {
  const _GraphPaperPainter();

  static const _cell = 18.5335;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(1.951),
    );
    canvas.drawRRect(paper, Paint()..color = RewindColors.cream);
    canvas.save();
    canvas.clipRRect(paper);
    final line = Paint()
      ..color = const Color(0x3B183F30)
      ..strokeWidth = 0.585;
    for (var x = _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPaperPainter oldDelegate) => false;
}

class _ScallopPainter extends CustomPainter {
  const _ScallopPainter();

  static const _back = [
    (-26.0, 490.0, 70.0),
    (23.0, 468.0, 64.0),
    (74.0, 482.0, 58.0),
    (123.0, 462.0, 76.0),
    (190.0, 472.0, 62.0),
    (240.0, 462.0, 70.0),
    (298.0, 468.0, 66.0),
  ];
  static const _front = [
    (-45.0, 492.0, 62.0),
    (0.0, 490.0, 72.0),
    (63.0, 496.0, 58.0),
    (102.0, 469.0, 80.0),
    (171.0, 492.0, 62.0),
    (215.0, 468.0, 78.0),
    (278.0, 489.0, 64.0),
    (327.0, 472.0, 74.0),
    (378.0, 499.0, 56.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(45, -462);
    void layer(List<(double, double, double)> bumps, double top, Color color) {
      final paint = Paint()..color = color;
      for (final (x, y, diameter) in bumps) {
        canvas.drawOval(Rect.fromLTWH(x, y, diameter, diameter), paint);
      }
      canvas.drawRect(Rect.fromLTRB(-45, top, 435, 462 + size.height), paint);
    }

    layer(_back, 523, const Color(0xFFF2E2C3));
    layer(_front, 521, RewindColors.cream);
  }

  @override
  bool shouldRepaint(_ScallopPainter oldDelegate) => false;
}
