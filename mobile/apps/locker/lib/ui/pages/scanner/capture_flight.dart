import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:locker/services/scanner/scan_geometry.dart';
import 'package:locker/services/scanner/scanner_models.dart';

abstract final class CaptureFlightTuning {
  static const arcHeight = 0.08;
  static const tilt = -3 * math.pi / 180;
  static const lift = 0.02;
  static const developContrast = 1.16;
  static const developBrightness = 12.0;
  static const developSaturation = 0.88;
  static const thumbnailInset = 0.05;
}

class CaptureFlightSpec {
  CaptureFlightSpec({
    required this.image,
    required this.sourceCorners,
    required this.imageToLayer,
    required this.target,
    required this.targetRadius,
    required this.targetBorder,
  }) : clipEnd = _rectCorners(target),
       zoomedCorners = _insetQuad(
         sourceCorners,
         CaptureFlightTuning.thumbnailInset,
       ),
       imageEnd = _rectCorners(
         _coverRect(target.deflate(targetBorder), _aspectOf(sourceCorners)),
       );

  final ui.Image image;
  final List<Offset> sourceCorners;
  final List<Offset> zoomedCorners;
  final Float64List imageToLayer;
  final Rect target;
  final double targetRadius;
  final double targetBorder;
  final List<Offset> clipEnd;
  final List<Offset> imageEnd;

  static List<Offset> _insetQuad(List<Offset> corners, double inset) {
    Offset at(double u, double v) {
      final top = Offset.lerp(corners[0], corners[1], u)!;
      final bottom = Offset.lerp(corners[3], corners[2], u)!;
      return Offset.lerp(top, bottom, v)!;
    }

    return [
      at(inset, inset),
      at(1 - inset, inset),
      at(1 - inset, 1 - inset),
      at(inset, 1 - inset),
    ];
  }

  static List<Offset> _rectCorners(Rect rect) => [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  static double _aspectOf(List<Offset> corners) {
    final width =
        ((corners[1] - corners[0]).distance +
            (corners[2] - corners[3]).distance) /
        2;
    final height =
        ((corners[3] - corners[0]).distance +
            (corners[2] - corners[1]).distance) /
        2;
    if (width <= 0 || height <= 0) return 1;
    return width / height;
  }

  static Rect _coverRect(Rect box, double aspect) {
    if (aspect < 1) {
      return Rect.fromLTWH(box.left, box.top, box.width, box.width / aspect);
    }
    final width = box.height * aspect;
    return Rect.fromLTWH(box.center.dx - width / 2, box.top, width, box.height);
  }
}

Float64List coverImageTransform(Size image, Rect destination) {
  final rotate =
      (image.width > image.height) != (destination.width > destination.height);
  final shown = rotate ? Size(image.height, image.width) : image;
  final scale = math.max(
    destination.width / shown.width,
    destination.height / shown.height,
  );
  final matrix = Matrix4.translationValues(
    destination.left + (destination.width - shown.width * scale) / 2,
    destination.top + (destination.height - shown.height * scale) / 2,
    0,
  )..multiply(Matrix4.diagonal3Values(scale, scale, 1));
  if (rotate) {
    matrix
      ..multiply(Matrix4.translationValues(shown.width, 0, 0))
      ..multiply(Matrix4.rotationZ(math.pi / 2));
  }
  return matrix.storage;
}

List<Offset> lerpCorners(List<Offset> a, List<Offset> b, double t) => [
  for (var i = 0; i < a.length; i++) Offset.lerp(a[i], b[i], t)!,
];

Offset centroid(List<Offset> corners) {
  var sum = Offset.zero;
  for (final c in corners) {
    sum += c;
  }
  return sum / corners.length.toDouble();
}

List<Offset> poseCorners(
  List<Offset> corners, {
  required Offset about,
  required Offset offset,
  required double angle,
  required double scale,
}) {
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  return [
    for (final c in corners)
      () {
        final d = (c - about) * scale;
        return about +
            offset +
            Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA);
      }(),
  ];
}

List<double> developMatrix(double t) {
  final c = ui.lerpDouble(1, CaptureFlightTuning.developContrast, t)!;
  final b = ui.lerpDouble(0, CaptureFlightTuning.developBrightness, t)!;
  final s = ui.lerpDouble(1, CaptureFlightTuning.developSaturation, t)!;
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  final sr = (1 - s) * lr;
  final sg = (1 - s) * lg;
  final sb = (1 - s) * lb;
  final offset = 128 * (1 - c) + b;
  return [
    c * (sr + s), c * sg, c * sb, 0, offset, //
    c * sr, c * (sg + s), c * sb, 0, offset, //
    c * sr, c * sg, c * (sb + s), 0, offset, //
    0, 0, 0, 1, 0, //
  ];
}

Path roundedPolygonPath(List<Offset> corners, double radius) {
  final path = Path();
  if (radius <= 0.01) return path..addPolygon(corners, true);
  final n = corners.length;
  for (var i = 0; i < n; i++) {
    final previous = corners[(i - 1 + n) % n];
    final corner = corners[i];
    final next = corners[(i + 1) % n];
    final toPrevious = previous - corner;
    final toNext = next - corner;
    final r = math.min(
      radius,
      math.min(toPrevious.distance, toNext.distance) / 2,
    );
    final entry = corner + toPrevious / toPrevious.distance * r;
    final exit = corner + toNext / toNext.distance * r;
    if (i == 0) {
      path.moveTo(entry.dx, entry.dy);
    } else {
      path.lineTo(entry.dx, entry.dy);
    }
    path.quadraticBezierTo(corner.dx, corner.dy, exit.dx, exit.dy);
  }
  return path..close();
}

class CaptureFlightCard extends StatefulWidget {
  const CaptureFlightCard({
    super.key,
    required this.spec,
    required this.borderColor,
    required this.onLanded,
  });

  static const duration = Duration(milliseconds: 620);

  final CaptureFlightSpec spec;
  final Color borderColor;
  final VoidCallback onLanded;

  @override
  State<CaptureFlightCard> createState() => _CaptureFlightCardState();
}

class _CaptureFlightCardState extends State<CaptureFlightCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CaptureFlightCard.duration,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onLanded();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FlightPainter(
          spec: widget.spec,
          progress: _progress,
          borderColor: widget.borderColor,
        ),
      ),
    );
  }
}

class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.spec,
    required this.progress,
    required this.borderColor,
  }) : super(repaint: progress);

  final CaptureFlightSpec spec;
  final Animation<double> progress;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final swing = math.sin(math.pi * t);
    final travel = spec.target.center - centroid(spec.sourceCorners);
    final pose = (
      offset: Offset(
        0,
        -travel.distance * CaptureFlightTuning.arcHeight * swing,
      ),
      angle: CaptureFlightTuning.tilt * swing,
      scale:
          1 +
          CaptureFlightTuning.lift *
              math.sin(math.pi * (t / 0.35).clamp(0.0, 1.0)),
    );
    final rawClip = lerpCorners(spec.sourceCorners, spec.clipEnd, t);
    final about = centroid(rawClip);
    final clip = poseCorners(
      rawClip,
      about: about,
      offset: pose.offset,
      angle: pose.angle,
      scale: pose.scale,
    );
    final sourceQuad = lerpCorners(spec.sourceCorners, spec.zoomedCorners, t);
    final imageQuad = poseCorners(
      lerpCorners(spec.sourceCorners, spec.imageEnd, t),
      about: about,
      offset: pose.offset,
      angle: pose.angle,
      scale: pose.scale,
    );
    final path = roundedPolygonPath(clip, spec.targetRadius * t);
    final elevation = 18 * math.sin(math.pi * t) + 3 * t;
    if (elevation > 0) {
      canvas.drawShadow(path, Colors.black, elevation, false);
    }
    canvas
      ..save()
      ..clipPath(path);
    paintMappedSnapshot(canvas, spec, sourceQuad, imageQuad, develop: t);
    final borderAlpha = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    if (borderAlpha > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = borderColor.withValues(alpha: borderAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = spec.targetBorder * 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlightPainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.borderColor != borderColor;
}

void paintMappedSnapshot(
  Canvas canvas,
  CaptureFlightSpec spec,
  List<Offset> sourceQuad,
  List<Offset> imageQuad, {
  required double develop,
}) {
  canvas.save();
  final homography = homographyMatrix(sourceQuad, imageQuad);
  if (homography != null) {
    canvas.transform(homography);
  } else {
    final from = _bounds(sourceQuad);
    final to = _bounds(imageQuad);
    canvas
      ..translate(to.left, to.top)
      ..scale(to.width / from.width, to.height / from.height)
      ..translate(-from.left, -from.top);
  }
  final paint = Paint()..filterQuality = FilterQuality.medium;
  if (develop > 0) {
    paint.colorFilter = ColorFilter.matrix(developMatrix(develop));
  }
  canvas
    ..transform(spec.imageToLayer)
    ..drawImage(spec.image, Offset.zero, paint)
    ..restore();
}

Rect _bounds(List<Offset> points) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final p in points) {
    left = math.min(left, p.dx);
    top = math.min(top, p.dy);
    right = math.max(right, p.dx);
    bottom = math.max(bottom, p.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

class CaptureSnapshotThumbnail extends StatelessWidget {
  const CaptureSnapshotThumbnail({super.key, required this.spec});

  final CaptureFlightSpec spec;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _SnapshotThumbnailPainter(spec),
    );
  }
}

class _SnapshotThumbnailPainter extends CustomPainter {
  const _SnapshotThumbnailPainter(this.spec);

  final CaptureFlightSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = spec.target.topLeft.translate(
      spec.targetBorder,
      spec.targetBorder,
    );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(-origin.dx, -origin.dy);
    paintMappedSnapshot(
      canvas,
      spec,
      spec.zoomedCorners,
      spec.imageEnd,
      develop: 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SnapshotThumbnailPainter oldDelegate) =>
      oldDelegate.spec != spec;
}

class CaptureSnapOverlay extends StatefulWidget {
  const CaptureSnapOverlay({
    super.key,
    required this.quad,
    required this.snapId,
    required this.color,
  });

  static const duration = Duration(milliseconds: 320);

  final ScanQuad? quad;
  final int snapId;
  final Color color;

  @override
  State<CaptureSnapOverlay> createState() => _CaptureSnapOverlayState();
}

class _CaptureSnapOverlayState extends State<CaptureSnapOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CaptureSnapOverlay.duration,
  );

  @override
  void didUpdateWidget(CaptureSnapOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapId != oldWidget.snapId && widget.quad != null) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SnapPainter(
          quad: widget.quad,
          progress: _controller,
          color: widget.color,
        ),
      ),
    );
  }
}

class _SnapPainter extends CustomPainter {
  _SnapPainter({
    required this.quad,
    required this.progress,
    required this.color,
  }) : super(repaint: progress);

  final ScanQuad? quad;
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final source = quad;
    final t = progress.value;
    if (source == null || t <= 0 || t >= 1 || size.isEmpty) return;
    final flash = math.pow(1 - Curves.easeOut.transform(t), 2).toDouble();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: 0.55 * flash),
    );
    final fade = 1 - Curves.easeOutCubic.transform(t);
    final path = Path()
      ..addPolygon([
        for (final c in source.corners)
          Offset(c.dx * size.width, c.dy * size.height),
      ], true);
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.4 * fade)
          ..style = PaintingStyle.fill,
      )
      ..drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 + 4 * fade
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_SnapPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.color != color;
}
