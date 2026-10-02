import "package:collection/collection.dart";
import "package:photos/models/file/file.dart";

// Match album-name ordering, including numeric runs (photo2 before photo10).
// Unnamed files stay last in either direction; identities break name ties.
int compareFileNames(EnteFile first, EnteFile second, {bool ascending = true}) {
  final firstName = first.displayName;
  final secondName = second.displayName;
  if (firstName.isEmpty != secondName.isEmpty) {
    return firstName.isEmpty ? 1 : -1;
  }
  final comparison = compareNatural(
    firstName.toLowerCase(),
    secondName.toLowerCase(),
  );
  if (comparison != 0) return ascending ? comparison : -comparison;

  final uploadedIDComparison = (first.uploadedFileID ?? -1).compareTo(
    second.uploadedFileID ?? -1,
  );
  if (uploadedIDComparison != 0) return uploadedIDComparison;
  final localIDComparison = (first.localID ?? "").compareTo(
    second.localID ?? "",
  );
  if (localIDComparison != 0) return localIDComparison;
  return (first.generatedID ?? -1).compareTo(second.generatedID ?? -1);
}
