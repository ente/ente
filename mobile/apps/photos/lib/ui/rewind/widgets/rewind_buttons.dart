import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";

enum RewindGlyph { sound, muted, share, close }

class RewindRoundButton extends StatelessWidget {
  const RewindRoundButton({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.size = 40,
    this.ring = true,
    super.key,
  });

  final RewindGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: RewindPressable(
        onTap: onTap,
        child: CustomPaint(
          size: Size.square(size),
          painter: _RoundButtonPainter(glyph, ring: ring),
        ),
      ),
    );
  }
}

class _RoundButtonPainter extends CustomPainter {
  _RoundButtonPainter(this.glyph, {required this.ring});

  final RewindGlyph glyph;
  final bool ring;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final unit = size.width / 40;
    canvas.drawCircle(
      center + const Offset(3, 4) * unit,
      radius,
      Paint()..color = RewindColors.ink,
    );
    canvas.drawCircle(center, radius, Paint()..color = RewindColors.cream);
    if (ring) {
      canvas.drawCircle(
        center,
        radius - 1.25 * unit,
        Paint()
          ..color = RewindColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * unit,
      );
    }
    canvas.scale(unit);
    final line = Paint()
      ..color = RewindColors.ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case RewindGlyph.sound:
      case RewindGlyph.muted:
        final speaker = Path()
          ..moveTo(11, 16)
          ..lineTo(16, 16)
          ..lineTo(22, 11)
          ..lineTo(22, 29)
          ..lineTo(16, 24)
          ..lineTo(11, 24)
          ..close();
        canvas.drawPath(speaker, Paint()..color = RewindColors.ink);
        canvas.drawPath(speaker, line..strokeWidth = 1);
        line.strokeWidth = 2.2;
        if (glyph == RewindGlyph.sound) {
          canvas.drawPath(
            Path()
              ..moveTo(26, 15)
              ..cubicTo(29, 18, 29, 22, 26, 25),
            line,
          );
        } else {
          canvas.drawLine(
            const Offset(25.5, 16.5),
            const Offset(31.5, 23.5),
            line,
          );
          canvas.drawLine(
            const Offset(31.5, 16.5),
            const Offset(25.5, 23.5),
            line,
          );
        }
      case RewindGlyph.share:
        line.strokeWidth = 2.4;
        canvas.drawPath(
          Path()
            ..moveTo(20, 24)
            ..lineTo(20, 11)
            ..moveTo(25, 16)
            ..lineTo(20, 11)
            ..lineTo(15, 16)
            ..moveTo(14, 21)
            ..lineTo(12, 21)
            ..lineTo(12, 30)
            ..lineTo(28, 30)
            ..lineTo(28, 21)
            ..lineTo(26, 21),
          line,
        );
      case RewindGlyph.close:
        line.strokeWidth = 2.6 * 40 / 36;
        canvas.drawLine(const Offset(14, 14), const Offset(26, 26), line);
        canvas.drawLine(const Offset(26, 14), const Offset(14, 26), line);
    }
  }

  @override
  bool shouldRepaint(_RoundButtonPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.ring != ring;
}

class RewindCandyButton extends StatelessWidget {
  const RewindCandyButton({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: RewindPressable(
        onTap: onTap,
        child: CustomPaint(
          painter: const _CandyPainter(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 187, minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: RewindTextStyles.body(
                    25.68,
                    height: 1.1,
                    letterSpacing: -0.77,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CandyPainter extends CustomPainter {
  const _CandyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );
    canvas.drawRRect(
      body.shift(const Offset(8, 10)).inflate(4),
      Paint()..color = RewindColors.ink,
    );
    canvas.drawRRect(body.inflate(4), Paint()..color = RewindColors.ink);
    canvas.drawRRect(body, Paint()..color = RewindColors.candyPink);
    canvas.save();
    canvas.clipRRect(body);
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.7)
        ..cubicTo(w * 0.3, h * 0.92, w * 0.75, h * 0.86, w, h * 0.56)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = RewindColors.candyPinkShade,
    );
    canvas.drawPath(
      Path()
        ..moveTo(4, h * 0.32)
        ..quadraticBezierTo(6, 3, w * 0.25, 2.5)
        ..lineTo(w - 22, 2.5),
      Paint()
        ..color = RewindColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final gloss = Paint()..color = RewindColors.white.withValues(alpha: 0.33);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.83, h * 0.12), width: 34, height: 7),
      gloss,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.71, h * 0.16), width: 10, height: 6),
      gloss,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CandyPainter oldDelegate) => false;
}

class RewindPressable extends StatefulWidget {
  const RewindPressable({
    required this.onTap,
    required this.child,
    this.pressedScale = 0.94,
    super.key,
  });

  final VoidCallback onTap;
  final Widget child;
  final double pressedScale;

  @override
  State<RewindPressable> createState() => _RewindPressableState();
}

class _RewindPressableState extends State<RewindPressable> {
  var _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
