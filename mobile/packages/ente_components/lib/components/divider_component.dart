import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=5772-34405&m=dev
/// Section: Divider
/// Specs: 1px horizontal line using stroke/faint.
class DividerComponent extends StatelessWidget {
  const DividerComponent({
    super.key,
    this.color,
    this.padding = EdgeInsets.zero,
    this.thickness = 1,
  });

  final Color? color;
  final EdgeInsetsGeometry padding;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        height: thickness,
        color: color ?? colors.strokeFaint,
      ),
    );
  }
}
