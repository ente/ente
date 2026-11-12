import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";

enum RewindTick {
  back(Size(13, 17), 4, [
    Offset(10.39, 14.96),
    Offset(10.11, 8.64),
    Offset(4.68, 3.69),
    Offset(2, 2),
  ]),
  forward(Size(11, 18), 4, [
    Offset(2, 16),
    Offset(7.2, 12.4),
    Offset(8.5, 5.17),
    Offset(8.5, 2),
  ]),
  bold(Size(16, 23), 6, [
    Offset(3, 20),
    Offset(9.8, 18),
    Offset(12.17, 7.83),
    Offset(12.5, 3),
  ]);

  const RewindTick(this.size, this.width, this.curve);

  final Size size;
  final double width;
  final List<Offset> curve;
}

class RewindTickMark extends StatelessWidget {
  const RewindTickMark(this.tick, {super.key});

  final RewindTick tick;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: tick.size, painter: _TickPainter(tick));
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.tick);

  final RewindTick tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / tick.size.width, size.height / tick.size.height);
    final [start, a, b, end] = tick.curve;
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(a.dx, a.dy, b.dx, b.dy, end.dx, end.dy),
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = tick.width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => oldDelegate.tick != tick;
}

class RewindLabelSticker extends StatelessWidget {
  const RewindLabelSticker(
    this.text, {
    this.size = 12.26,
    this.fill = RewindColors.yellow,
    super.key,
  });

  final String text;
  final double size;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final unit = size / 12.26;
    return Container(
      padding: EdgeInsets.all(1.8 * unit),
      decoration: BoxDecoration(
        color: RewindColors.cream,
        border: Border.all(color: RewindColors.ink, width: 0.9 * unit),
        borderRadius: BorderRadius.circular(4.33 * unit),
        boxShadow: [
          BoxShadow(
            color: RewindColors.ink,
            offset: Offset(1.44 * unit, 1.8 * unit),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 4.33 * unit,
          vertical: 1.08 * unit,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(2.89 * unit),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: RewindTextStyles.display(
            size,
            color: RewindColors.ink,
            height: 1.05,
          ),
        ),
      ),
    );
  }
}
