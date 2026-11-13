import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/events/magic_sort_change_event.dart";
import "package:photos/ui/components/collection_share_badge.dart";

Future<bool?> showAlbumSortSheet(
  BuildContext context, {
  required bool ascending,
}) {
  return _showSortSheet(
    context,
    selected: ascending,
    options: [
      (false, context.strings.sortNewestFirst),
      (true, context.strings.sortOldestFirst),
    ],
  );
}

Future<MagicSortType?> showMagicSortSheet(
  BuildContext context, {
  required MagicSortType sortType,
}) {
  return _showSortSheet(
    context,
    selected: sortType,
    options: [
      (MagicSortType.mostRecent, context.strings.mostRecent),
      (MagicSortType.mostRelevant, context.strings.mostRelevant),
    ],
  );
}

Future<T?> _showSortSheet<T>(
  BuildContext context, {
  required T selected,
  required List<(T, String)> options,
}) {
  return showBottomSheetComponent<T>(
    context: context,
    builder: (sheetContext) => SingleChildScrollView(
      child: BottomSheetComponent(
        title: sheetContext.strings.sortPhotos,
        closeTooltip: sheetContext.strings.close,
        content: MenuGroupComponent(
          items: [
            for (final (value, label) in options)
              Semantics(
                selected: value == selected,
                child: MenuComponent(
                  title: label,
                  trailing: value == selected
                      ? const CollectionSelectedBadge()
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(value),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
