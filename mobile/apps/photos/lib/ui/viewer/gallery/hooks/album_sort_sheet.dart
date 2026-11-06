import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/events/magic_sort_change_event.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/ui/components/collection_share_badge.dart";

String albumSortOrderLabel(FileSortOrder order, StringsLocalizations strings) =>
    switch (order) {
      FileSortOrder.newestFirst => strings.sortNewestFirst,
      FileSortOrder.oldestFirst => strings.sortOldestFirst,
      FileSortOrder.filenameAscending => strings.sortAToZ,
      FileSortOrder.filenameDescending => strings.sortZToA,
    };

Future<FileSortOrder?> showAlbumSortSheet(
  BuildContext context, {
  required FileSortOrder sortOrder,
}) {
  return _showSortSheet(
    context,
    selected: sortOrder,
    options: [
      for (final order in FileSortOrder.values)
        (order, albumSortOrderLabel(order, context.strings)),
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
