import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

enum LoadingComponentSize {
  small(16, 2),
  medium(24, 2.5),
  large(40, 3);

  const LoadingComponentSize(this.diameter, this.stroke);

  final double diameter;
  final double stroke;
}

class LoadingComponent extends StatefulWidget {
  const LoadingComponent({
    super.key,
    this.size = LoadingComponentSize.medium,
    this.color,
    this.semanticsLabel,
  });

  final LoadingComponentSize size;
  final Color? color;
  final String? semanticsLabel;

  @override
  State<LoadingComponent> createState() => _LoadingComponentState();
}

class _LoadingComponentState extends State<LoadingComponent>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      role: SemanticsRole.loadingSpinner,
      child: SizedBox.square(
        dimension: widget.size.diameter,
        child: RotationTransition(
          turns: _turn,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LoadingPainter(
                color: widget.color ?? context.componentColors.primary,
                stroke: widget.size.stroke,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter({required this.color, required this.stroke});

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.16);
    canvas.drawOval(rect, paint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi / 2,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_LoadingPainter old) =>
      old.color != color || old.stroke != stroke;
}
