import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/ui/components/empty_state_illustration.dart";

class EmptyStateComponent extends StatelessWidget {
  const EmptyStateComponent({
    required this.assetPath,
    required this.title,
    this.animated = false,
    this.illustrationSize = const Size(204, 170),
    this.textWidth = 285,
    this.spacing = 20,
    this.padding = const EdgeInsets.all(24),
    this.alignment = Alignment.center,
    super.key,
  });

  final String assetPath;
  final String title;
  final bool animated;
  final Size illustrationSize;
  final double textWidth;
  final double spacing;
  final EdgeInsetsGeometry padding;

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
            if (animated)
              EmptyStateIllustration(
                key: ValueKey(assetPath),
                assetPath: assetPath,
                size: illustrationSize,
              )
            else
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
