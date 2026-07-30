import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";

/// Shared trailing-action surface for the gallery / people / cluster app bars.
class GalleryAppBarIconButtonSurface extends StatelessWidget {
  const GalleryAppBarIconButtonSurface({required this.icon, super.key});

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return SizedBox.square(
      dimension: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.fillLight,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: IconTheme.merge(
            data: IconThemeData(color: colors.textBase, size: IconSizes.small),
            child: icon,
          ),
        ),
      ),
    );
  }
}

Widget galleryAppBarPopupMenuAction<T>({
  required Widget icon,
  required String tooltip,
  required FutureOr<List<EntePopupMenuOption<T>>> Function() optionsBuilder,
  required FutureOr<void> Function(T) onSelected,
}) {
  return EntePopupMenuButton<T>(
    optionsBuilder: optionsBuilder,
    onSelected: onSelected,
    elevation: 0,
    child: Tooltip(
      message: tooltip,
      child: GalleryAppBarIconButtonSurface(icon: icon),
    ),
  );
}

Widget galleryAppBarMenuIcon(List<List<dynamic>> icon, Color color) {
  return HugeIcon(icon: icon, size: IconSizes.small, color: color);
}
