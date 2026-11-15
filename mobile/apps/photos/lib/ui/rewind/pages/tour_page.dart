import "dart:math";

import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _months = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const _macrons = {
  "ā": "a",
  "ē": "e",
  "ī": "i",
  "ō": "o",
  "ū": "u",
  "Ā": "A",
  "Ē": "E",
  "Ī": "I",
  "Ō": "O",
  "Ū": "U",
};

String _city(rust.TourStop stop) =>
    stop.city.split("").map((letter) => _macrons[letter] ?? letter).join();

String _date(rust.TourStop stop) =>
    "${_months[stop.month - 1].substring(0, 3).toUpperCase()} "
    "${stop.day.toString().padLeft(2, "0")}";

String _place(rust.TourStop stop) => stop.countryCode.isEmpty
    ? _city(stop).toUpperCase()
    : "${_city(stop).toUpperCase()}, ${stop.countryCode}";

class TourPage extends RewindPage {
  const TourPage(this.tour);

  static const pageKey = "tour";

  static const _print = Rect.fromLTWH(102, 166, 186, 356);
  static const _singleColumnStops = 7;
  static const _rowsStartMs = 750;
  static const _rowStepMs = 95;

  final rust.Tour tour;

  @override
  String get key => pageKey;

  @override
  RewindChrome get chrome => RewindChrome.dark;

  @override
  Duration? get reelHold =>
      Duration(milliseconds: 2350 + _rowStepMs * tour.stops.length);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final stops = tour.stops;
    final first = stops.first;
    final last = stops.last;
    final cities = rewindCounted(tour.cityCount, "city", "cities");
    final printed = tour.cityCount > stops.length
        ? "The ${stops.length} biggest dates"
        : "Every date";
    final body =
        "From ${_city(first)} in ${_months[first.month - 1]} to ${_city(last)} "
        "in ${_months[last.month - 1]}. $printed made the tee.";
    final stampMs = _rowsStartMs + _rowStepMs * stops.length + 250;
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFFFFCA39),
            pattern: RewindRays(
              Color(0xFFFFD24E),
              center: Offset(195, 330),
              wedge: 9,
              step: 18,
            ),
          ),
          Semantics(
            label:
                "The camera roll went on tour. "
                "${cities.toUpperCase()}, sold out. $body",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  RewindLayer(
                    rect: const Rect.fromLTWH(0, 100, 390, 460),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.drop,
                      active: isActive,
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(painter: _TeePainter()),
                          ),
                          Positioned.fromRect(
                            rect: _print.shift(const Offset(0, -100)),
                            child: _Print(tour: tour, active: isActive),
                          ),
                        ],
                      ),
                    ),
                  ),
                  RewindLayer(
                    rect: const Rect.fromLTWH(254, 524, 126, 40),
                    position: position,
                    child: RewindEntrance(
                      preset: RewindPreset.slap,
                      active: isActive,
                      delayMs: stampMs,
                      child: Transform.rotate(
                        angle: -9 * pi / 180,
                        child: const _Stamp("SOLD OUT"),
                      ),
                    ),
                  ),
                  ...rewindCaption(
                    label: "THE CAMERA ROLL WENT ON TOUR",
                    title: "${cities.toUpperCase()}, SOLD OUT",
                    body: body,
                    position: position,
                    active: isActive,
                    delayMs: stampMs + 250,
                    top: 600,
                    ink: RewindColors.ink,
                    titleSize: 44,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Print extends StatelessWidget {
  const _Print({required this.tour, required this.active});

  final rust.Tour tour;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final stops = tour.stops;
    final single = stops.length <= TourPage._singleColumnStops;
    final half = (stops.length / 2).ceil();
    Widget entering(int index, Widget child) => RewindEntrance(
      preset: RewindPreset.line,
      active: active,
      delayMs: TourPage._rowsStartMs + TourPage._rowStepMs * index,
      child: child,
    );
    return Column(
      children: [
        Text(
          "CAMERA ROLL",
          style: RewindTextStyles.display(
            16,
            color: RewindColors.yellow,
            letterSpacing: 2.4,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        RewindFitWidth(
          width: TourPage._print.width,
          alignment: Alignment.center,
          child: Text(
            "WORLD TOUR",
            style: RewindTextStyles.display(
              39,
              color: RewindColors.hotPink,
              height: 0.92,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _Spark(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                "${RewindEdition.year}",
                style: RewindTextStyles.display(16, height: 1),
              ),
            ),
            const _Spark(),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Align(
            alignment: const Alignment(0, -0.25),
            child: single
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, stop) in stops.indexed)
                        entering(i, _Row(stop)),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (column, part) in [
                        stops.sublist(0, half),
                        stops.sublist(half),
                      ].indexed) ...[
                        if (column == 1) const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (i, stop) in part.indexed)
                                entering(column * half + i, _Cell(stop)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        Text(
          [
            rewindCounted(tour.cityCount, "CITY", "CITIES"),
            rewindCounted(tour.countryCount, "COUNTRY", "COUNTRIES"),
          ].join("  ·  "),
          style: RewindTextStyles.numeral(8.8),
        ),
        const SizedBox(height: 5),
        Text(
          "ALL SHOWS END-TO-END ENCRYPTED",
          style: RewindTextStyles.numeral(
            6.6,
            color: RewindColors.hotPink,
          ).copyWith(letterSpacing: 0.9),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.stop);

  final rust.TourStop stop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 27,
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              _date(stop),
              style: RewindTextStyles.numeral(10, color: RewindColors.yellow),
            ),
          ),
          RewindFitWidth(
            width: TourPage._print.width - 50,
            child: Text(
              _place(stop),
              style: RewindTextStyles.display(17, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.stop);

  final rust.TourStop stop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 31,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _date(stop),
            style: RewindTextStyles.numeral(7.6, color: RewindColors.yellow),
          ),
          const SizedBox(height: 1),
          RewindFitWidth(
            width: (TourPage._print.width - 10) / 2,
            child: Text(
              _place(stop),
              style: RewindTextStyles.display(13, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.file(
      RewindAssets.file(RewindAssets.whiteSparkle),
      width: 11,
      height: 11,
      colorFilter: const ColorFilter.mode(RewindColors.yellow, BlendMode.srcIn),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 5),
        decoration: BoxDecoration(
          color: RewindColors.hotPink,
          border: Border.all(color: RewindColors.ink, width: 3),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: RewindColors.ink, offset: Offset(3, 4)),
          ],
        ),
        child: Text(text, style: RewindTextStyles.display(21, height: 1.1)),
      ),
    );
  }
}

class _TeePainter extends CustomPainter {
  const _TeePainter();

  static const _cloth = Color(0xFF1B1B20);

  @override
  void paint(Canvas canvas, Size size) {
    final tee = Path()
      ..moveTo(158, 22)
      ..quadraticBezierTo(195, 52, 232, 22)
      ..lineTo(290, 36)
      ..quadraticBezierTo(322, 44, 372, 104)
      ..lineTo(336, 160)
      ..lineTo(304, 134)
      ..lineTo(304, 424)
      ..quadraticBezierTo(304, 438, 290, 438)
      ..lineTo(100, 438)
      ..quadraticBezierTo(86, 438, 86, 424)
      ..lineTo(86, 134)
      ..lineTo(54, 160)
      ..lineTo(18, 104)
      ..quadraticBezierTo(68, 44, 100, 36)
      ..close();
    Paint edge(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round;
    final shadow = tee.shift(const Offset(5, 6));
    canvas.drawPath(shadow, edge(RewindColors.ink, 11));
    canvas.drawPath(shadow, Paint()..color = RewindColors.ink);
    canvas.drawPath(tee, edge(RewindColors.cream, 11));
    canvas.drawPath(tee, Paint()..color = _cloth);
    canvas.save();
    canvas.clipPath(tee);
    canvas.drawPath(
      Path()
        ..moveTo(150, 18)
        ..quadraticBezierTo(195, 62, 240, 18),
      edge(const Color(0xFF393942), 9),
    );
    for (final seam in const [
      (Offset(304, 134), Offset(290, 40)),
      (Offset(86, 134), Offset(100, 40)),
    ]) {
      canvas.drawLine(seam.$1, seam.$2, edge(const Color(0xFF2A2A31), 1.6));
    }
    canvas.restore();
    final label = RRect.fromRectAndRadius(
      const Rect.fromLTWH(180, 44, 30, 13),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(label, Paint()..color = RewindColors.cream);
    final brand = TextPainter(
      text: TextSpan(
        text: "ente",
        style: RewindTextStyles.body(9, color: RewindColors.ink, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    brand.paint(
      canvas,
      label.center - Offset(brand.width / 2, brand.height / 2 + 0.5),
    );
    brand.dispose();
  }

  @override
  bool shouldRepaint(_TeePainter oldDelegate) => false;
}
