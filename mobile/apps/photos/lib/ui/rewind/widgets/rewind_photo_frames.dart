import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";

class RewindPolaroid extends StatelessWidget {
  const RewindPolaroid({required this.photo, this.width = 112, super.key});

  final Widget photo;
  final double width;

  @override
  Widget build(BuildContext context) {
    final unit = width / 112;
    return Container(
      width: width,
      padding: EdgeInsets.fromLTRB(8 * unit, 8 * unit, 8 * unit, 30 * unit),
      decoration: BoxDecoration(
        color: RewindColors.photoPaper,
        borderRadius: BorderRadius.circular(3 * unit),
        boxShadow: [
          BoxShadow(
            color: const Color(0x2E000000),
            offset: Offset(0, 4 * unit),
            blurRadius: 3 * unit,
          ),
        ],
      ),
      child: AspectRatio(aspectRatio: 1, child: ClipRect(child: photo)),
    );
  }
}

class RewindStamp extends StatelessWidget {
  const RewindStamp({
    required this.photo,
    required this.label,
    this.portrait = false,
    this.width = 139.6,
    this.lift = 4,
    super.key,
  });

  final Widget photo;
  final String label;
  final bool portrait;
  final double width;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final unit = width / 139.6;
    return CustomPaint(
      painter: _StampPainter(unit: unit, lift: lift * unit),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14 * unit,
          (portrait ? 7.6 : 10) * unit,
          14 * unit,
          10 * unit,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 111.4 * unit,
              height: (portrait ? 132 : 46) * unit,
              child: ClipRect(child: photo),
            ),
            SizedBox(height: 8.75 * unit),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RewindTextStyles.body(
                11.35 * unit,
                weight: FontWeight.w400,
                color: RewindColors.ink.withValues(alpha: 0.82),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter({required this.unit, required this.lift});

  final double unit;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = _perforated(size);
    canvas.drawPath(
      edge.shift(Offset(0, lift)),
      Paint()..color = const Color(0x42000000),
    );
    canvas.drawPath(edge, Paint()..color = RewindColors.stampPaper);
  }

  Path _perforated(Size size) {
    final pitch = 13.6 * unit;
    final radius = 3 * unit;
    final holes = Path();
    void punchAlong(Offset from, Offset to) {
      final length = (to - from).distance;
      final count = max(1, (length / pitch).round());
      for (var i = 0; i <= count; i++) {
        holes.addOval(
          Rect.fromCircle(
            center: Offset.lerp(from, to, i / count)!,
            radius: radius,
          ),
        );
      }
    }

    punchAlong(Offset.zero, Offset(size.width, 0));
    punchAlong(Offset(0, size.height), Offset(size.width, size.height));
    punchAlong(Offset.zero, Offset(0, size.height));
    punchAlong(Offset(size.width, 0), Offset(size.width, size.height));
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      holes,
    );
  }

  @override
  bool shouldRepaint(_StampPainter oldDelegate) =>
      oldDelegate.unit != unit || oldDelegate.lift != lift;
}

class RewindFilmStrip extends StatelessWidget {
  const RewindFilmStrip({
    required this.photos,
    required this.date,
    this.firstFrame = 1,
    super.key,
  });

  static const height = 222.0;
  static const pitch = 232.0;

  final List<Widget> photos;
  final String date;
  final int firstFrame;

  @override
  Widget build(BuildContext context) {
    final label = RewindTextStyles.film(10);
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 3),
      decoration: const BoxDecoration(
        color: RewindColors.photoPaper,
        boxShadow: [BoxShadow(color: Color(0x29000000), offset: Offset(0, 7))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < photos.length; i++)
            SizedBox(
              width: pitch,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    width: 214,
                    top: 11,
                    child: Text(
                      date,
                      textAlign: TextAlign.center,
                      style: label,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 31,
                    width: 214,
                    height: 160,
                    child: ClipRect(child: photos[i]),
                  ),
                  Positioned(
                    left: 14,
                    top: 199,
                    child: Text(
                      (firstFrame + i).toString().padLeft(3, "0"),
                      style: label,
                    ),
                  ),
                  const Positioned(left: 42, top: 202.5, child: _PlayMark()),
                  const Positioned(left: 196, top: 202.5, child: _PlayMark()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayMark extends StatelessWidget {
  const _PlayMark();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(7, 8), painter: _PlayMarkPainter());
  }
}

class _PlayMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = const Color(0xD9151515),
    );
  }

  @override
  bool shouldRepaint(_PlayMarkPainter oldDelegate) => false;
}

class RewindBoothStrip extends StatelessWidget {
  const RewindBoothStrip({required this.photos, super.key});

  static const size = Size(224, 451);

  final List<Widget> photos;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: _BoothStripPainter(),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          children: [
            for (var i = 0; i < min(photos.length, 4); i++)
              Positioned(
                left: 12.6,
                top: 6 + 110.0 * i,
                width: 198.8,
                height: 103,
                child: ClipRect(child: photos[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoothStripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final notches = Path();
    for (var y = 6.25; y < size.height; y += 12.5) {
      for (final x in [0.0, size.width]) {
        notches.addOval(
          Rect.fromCenter(center: Offset(x, y), width: 11.76, height: 8.4),
        );
      }
    }
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        notches,
      ),
      Paint()..color = RewindColors.photoPaper,
    );
  }

  @override
  bool shouldRepaint(_BoothStripPainter oldDelegate) => false;
}

enum RewindCutoutShape { circle, heart, flower, star }

class RewindCutout extends StatelessWidget {
  const RewindCutout({
    required this.shape,
    required this.photo,
    this.border = 2.9,
    super.key,
  });

  final RewindCutoutShape shape;
  final Widget photo;
  final double border;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CutoutBackingPainter(shape),
      child: Padding(
        padding: EdgeInsets.all(border),
        child: ClipPath(clipper: _CutoutClipper(shape), child: photo),
      ),
    );
  }
}

Path _cutoutPath(RewindCutoutShape shape, Size size) {
  if (shape == RewindCutoutShape.circle) {
    return Path()..addOval(Offset.zero & size);
  }
  const samples = 180;
  final points = <Offset>[];
  for (var i = 0; i < samples; i++) {
    final t = i / samples * 2 * pi;
    points.add(switch (shape) {
      RewindCutoutShape.heart => Offset(
        16 * pow(sin(t), 3).toDouble(),
        -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)),
      ),
      RewindCutoutShape.flower => Offset.fromDirection(
        t,
        0.8 + 0.2 * cos(8 * t),
      ),
      RewindCutoutShape.star => Offset.fromDirection(
        t - pi / 2,
        0.62 + 0.38 * pow((cos(5 * t) + 1) / 2, 1.6),
      ),
      RewindCutoutShape.circle => Offset.fromDirection(t),
    });
  }
  final bounds = (Path()..addPolygon(points, true)).getBounds();
  return Path()..addPolygon([
    for (final point in points)
      Offset(
        (point.dx - bounds.left) / bounds.width * size.width,
        (point.dy - bounds.top) / bounds.height * size.height,
      ),
  ], true);
}

class _CutoutClipper extends CustomClipper<Path> {
  _CutoutClipper(this.shape);

  final RewindCutoutShape shape;

  @override
  Path getClip(Size size) => _cutoutPath(shape, size);

  @override
  bool shouldReclip(_CutoutClipper oldClipper) => oldClipper.shape != shape;
}

class _CutoutBackingPainter extends CustomPainter {
  _CutoutBackingPainter(this.shape);

  final RewindCutoutShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _cutoutPath(shape, size);
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x21000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    canvas.drawPath(path, Paint()..color = RewindColors.cream);
  }

  @override
  bool shouldRepaint(_CutoutBackingPainter oldDelegate) =>
      oldDelegate.shape != shape;
}
