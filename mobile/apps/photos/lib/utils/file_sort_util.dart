import "dart:ui";

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/src/rust/api/file_sort_api.dart" as rust;

Future<void> sortFilesByName(
  List<EnteFile> files,
  FileSortOrder order, {
  String? localeTag,
}) async {
  assert(order.isFilename);
  if (files.length < 2) return;
  final original = List<EnteFile>.of(files, growable: false);
  final indices = await rust.sortedFilenameIndices(
    names: original.map((file) => file.displayName).toList(growable: false),
    fileIds: Int64List.fromList(
      original
          .map((file) => file.uploadedFileID ?? file.generatedID ?? 0)
          .toList(growable: false),
    ),
    locale: localeTag ?? PlatformDispatcher.instance.locale.toLanguageTag(),
    ascending: order.ascending,
  );
  for (var index = 0; index < indices.length; index++) {
    files[index] = original[indices[index]];
  }
}
