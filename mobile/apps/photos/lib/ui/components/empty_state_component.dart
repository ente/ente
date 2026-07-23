import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

class EmptyStateComponent extends StatelessWidget {
  const EmptyStateComponent({
    required this.assetPath,
    required this.title,
    this.textWidth = 285,
    this.spacing = 20,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });

  final String assetPath;
  final String title;
  final double textWidth;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Center(
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
