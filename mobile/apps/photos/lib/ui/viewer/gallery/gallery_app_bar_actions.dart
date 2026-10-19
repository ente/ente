import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/ui/viewer/gallery/hooks/album_actions_sheet.dart";

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

Widget galleryAppBarActionsSheetAction<T>({
  required Widget icon,
  required String tooltip,
  required FutureOr<List<EntePopupMenuOption<T>>> Function() optionsBuilder,
  required FutureOr<void> Function(T) onSelected,
}) {
  return Builder(
    builder: (context) => IconButtonComponent(
      tooltip: tooltip,
      icon: icon,
      variant: IconButtonComponentVariant.unfilled,
      size: kMinInteractiveDimension,
      iconSize: IconSizes.medium,
      shouldSurfaceExecutionStates: false,
      onTap: () async {
        final options = await optionsBuilder();
        if (!context.mounted || options.isEmpty) {
          return;
        }

        final selected = await showAlbumActionsSheet<T>(context, options);
        if (!context.mounted || selected == null) {
          return;
        }
        await onSelected(selected);
      },
    ),
  );
}
