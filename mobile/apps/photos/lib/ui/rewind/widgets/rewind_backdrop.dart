import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

sealed class RewindPattern {
  const RewindPattern(this.color);

  final Color color;

  Duration get period;

  void paint(Canvas canvas, Rect visible, double t);
}

class RewindZigzag extends RewindPattern {
  const RewindZigzag(super.color);

  @override
  Duration get period => const Duration(milliseconds: 2600);

  @override
  void paint(Canvas canvas, Rect visible, double t) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeJoin = StrokeJoin.miter;
    final firstColumn = ((visible.left + 40) / 28).floor() - 2;
    final lastColumn = ((visible.right + 40) / 28).ceil() + 2;
    final drift = -62 * t;
    final firstRow = ((visible.top + 44 - drift) / 62).floor() - 1;
    final lastRow = ((visible.bottom + 44 - drift) / 62).ceil() + 1;
    for (var row = firstRow; row <= lastRow; row++) {
      final top = -44 + 62.0 * row + drift;
      final path = Path();
      for (var column = firstColumn; column <= lastColumn; column++) {
        final point = Offset(
          -40 + 28.0 * column,
          top + (column.isEven ? 24 : 0),
        );
        column == firstColumn
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}

class RewindStripes extends RewindPattern {
  const RewindStripes(super.color);

  static const _pitch = 66.0;
  static const _segment = Offset(90, 1004);

  @override
  Duration get period => const Duration(milliseconds: 2400);

  @override
  void paint(Canvas canvas, Rect visible, double t) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    final stripe = Path()
      ..moveTo(0, 0)
      ..cubicTo(60, 315.4, 10, 568.6, _segment.dx, _segment.dy);
    final firstSegment = ((visible.top + 80) / _segment.dy).floor() - 1;
    final lastSegment = ((visible.bottom + 80) / _segment.dy).ceil();
    final phase = (-184 + _pitch * t) % _pitch;
    for (var k = firstSegment; k <= lastSegment; k++) {
      final shift = _segment * k.toDouble();
      final first = ((visible.left - shift.dx - _segment.dx - phase) / _pitch)
          .floor();
      final last = ((visible.right - shift.dx - phase) / _pitch).ceil();
      for (var n = first; n <= last; n++) {
        canvas.drawPath(
          stripe.shift(Offset(phase + _pitch * n, -80) + shift),
          paint,
        );
      }
    }
  }
}

class RewindRays extends RewindPattern {
  const RewindRays(
    super.color, {
    this.center = const Offset(195, 300),
    this.wedge = 9,
    this.step = 18,
  });

  final Offset center;
  final double wedge;
  final double step;

  @override
  Duration get period => const Duration(seconds: 48);

  @override
  void paint(Canvas canvas, Rect visible, double t) {
    final paint = Paint()..color = color;
    final reach = [
      visible.topLeft,
      visible.topRight,
      visible.bottomLeft,
      visible.bottomRight,
    ].map((corner) => (corner - center).distance).reduce(max);
    Offset at(double degrees) {
      final radians = degrees * pi / 180;
      return center + Offset(sin(radians), -cos(radians)) * (reach + 50);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(2 * pi * t);
    canvas.translate(-center.dx, -center.dy);
    for (var angle = 0.0; angle < 360; angle += step) {
      final a = at(angle);
      final b = at(angle + wedge);
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..close(),
        paint,
      );
    }
    canvas.restore();
  }
}

class RewindBackdrop extends StatelessWidget {
  const RewindBackdrop({
    required this.color,
    this.pattern,
    this.grain = 0.2,
    this.doodle,
    super.key,
  });

  final Color color;
  final RewindPattern? pattern;
  final double grain;
  final Color? doodle;

  @override
  Widget build(BuildContext context) {
    final pattern = this.pattern;
    final doodle = this.doodle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = RewindStage.scaleFor(constraints.biggest);
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: color),
            if (pattern != null) _AnimatedPattern(pattern: pattern),
            if (doodle != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(
                      RewindAssets.file(RewindAssets.coverDoodle),
                    ),
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    repeat: ImageRepeat.repeatY,
                    colorFilter: ColorFilter.mode(doodle, BlendMode.srcIn),
                  ),
                ),
              ),
            if (grain > 0)
              DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(RewindAssets.file(RewindAssets.grain)),
                    repeat: ImageRepeat.repeat,
                    scale: 2 / scale,
                    opacity: grain,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AnimatedPattern extends StatefulWidget {
  const _AnimatedPattern({required this.pattern});

  final RewindPattern pattern;

  @override
  State<_AnimatedPattern> createState() => _AnimatedPatternState();
}

class _AnimatedPatternState extends State<_AnimatedPattern>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.pattern.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _PatternPainter(widget.pattern, _controller)),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.pattern, this.progress) : super(repaint: progress);

  final RewindPattern pattern;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = RewindStage.scaleFor(size);
    final origin = RewindStage.originFor(size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final visible = Rect.fromLTWH(
      -origin.dx / scale,
      -origin.dy / scale,
      size.width / scale,
      size.height / scale,
    );
    pattern.paint(canvas, visible, progress.value);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern;
}

class RewindDoodleTile extends StatelessWidget {
  const RewindDoodleTile({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RewindColors.green,
        image: DecorationImage(
          image: FileImage(RewindAssets.file(RewindAssets.tileDoodle)),
          fit: BoxFit.cover,
          colorFilter: const ColorFilter.mode(
            RewindColors.doodleGreen,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
