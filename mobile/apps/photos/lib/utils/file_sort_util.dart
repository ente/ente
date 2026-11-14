import "package:collection/collection.dart";
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
  files.sort(_filenameComparator(order));
}

EnteFile? firstFileByName(List<EnteFile> files, FileSortOrder order) {
  assert(order.isFilename);
  if (files.length < 2) return files.firstOrNull;
  final compare = _filenameComparator(order);
  var first = files.first;
  for (var index = 1; index < files.length; index++) {
    final candidate = files[index];
    if (compare(candidate, first) < 0) first = candidate;
  }
  return first;
}

Comparator<EnteFile> _filenameComparator(FileSortOrder order) {
  return (first, second) {
    final result = compareAsciiLowerCaseNatural(
      first.displayName,
      second.displayName,
    );
    if (result != 0) return order.ascending ? result : -result;
    return _compareFileIDs(first, second);
  };
}
