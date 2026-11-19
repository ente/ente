import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_sort_order.dart";

int _compareFileIDs(EnteFile first, EnteFile second) {
  return (first.uploadedFileID ?? first.generatedID ?? 0).compareTo(
    second.uploadedFileID ?? second.generatedID ?? 0,
  );
}

void sortFilesByName(List<EnteFile> files, FileSortOrder order) {
  assert(order.isFilename);
  if (files.length < 2) return;
  // Keys are computed once per file; folding inside the comparator is ~10x
  // slower for accented names.
  final keyed = [
    for (final file in files)
      (file: file, name: file.displayName, key: nameSortKey(file.displayName)),
  ];
  keyed.sort((first, second) {
    final result = compareNames(
      first.name,
      second.name,
      aKey: first.key,
      bKey: second.key,
    );
    if (result != 0) return order.ascending ? result : -result;
    return _compareFileIDs(first.file, second.file);
  });
  for (var i = 0; i < files.length; i++) {
    files[i] = keyed[i].file;
  }
}
