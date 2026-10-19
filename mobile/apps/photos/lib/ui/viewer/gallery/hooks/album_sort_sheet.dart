import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
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
  return showBottomSheetComponent<FileSortOrder>(
    context: context,
    builder: (sheetContext) => SingleChildScrollView(
      child: BottomSheetComponent(
        title: sheetContext.strings.sortPhotos,
        closeTooltip: sheetContext.strings.close,
        content: MenuGroupComponent(
          items: [
            for (final value in FileSortOrder.values)
              Semantics(
                selected: value == sortOrder,
                child: MenuComponent(
                  title: albumSortOrderLabel(value, sheetContext.strings),
                  trailing: value == sortOrder
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
