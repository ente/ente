import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

class EmptyStateComponent extends StatelessWidget {
  const EmptyStateComponent({
    required this.assetPath,
    required this.title,
    this.textWidth = 285,
    this.spacing = 20,
    this.padding = const EdgeInsets.all(24),
    this.alignment = Alignment.center,
    super.key,
  });

  final String assetPath;
  final String title;
  final double textWidth;
  final double spacing;
  final EdgeInsetsGeometry padding;

  /// Allows fixed-format empty states to opt out of vertical centering.
  /// Source: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=17186-38829&m=dev
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(assetPath),
            SizedBox(height: spacing),
            SizedBox(
              width: textWidth,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyles.display2.copyWith(color: colors.textBase),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
