import "dart:math";

import "package:flutter/widgets.dart";

class RewindStage extends StatelessWidget {
  const RewindStage({required this.children, super.key});

  static const size = Size(390, 844);

  static double scaleFor(Size screen) =>
      min(screen.width / size.width, screen.height / size.height);

  static Offset originFor(Size screen) {
    final scale = scaleFor(screen);
    return Offset(
      (screen.width - size.width * scale) / 2,
      (screen.height - size.height * scale) / 2,
    );
  }

  final List<Widget> children;

  static Alignment alignmentOf(Offset point) =>
      Alignment(point.dx / size.width * 2 - 1, point.dy / size.height * 2 - 1);

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: FittedBox(
        child: SizedBox.fromSize(
          size: size,
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      ),
    );
  }
}

class RewindLeave extends StatelessWidget {
  const RewindLeave({
    required this.position,
    required this.centerY,
    required this.child,
    super.key,
  });

  final double position;
  final double centerY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final depth = (centerY / RewindStage.size.height).clamp(0.0, 1.0);
    final q = (position.clamp(0.0, 1.0) * 1.9 - depth * 0.7).clamp(0.0, 1.0);
    final eased = q * q * (3 - 2 * q);
    return Opacity(
      opacity: 1 - eased,
      child: Transform.translate(offset: Offset(0, -56 * eased), child: child),
    );
  }
}
