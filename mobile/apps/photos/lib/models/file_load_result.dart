import "package:photos/models/file/file.dart";

class FileLoadResult {
  late final List<EnteFile> files;
  late final bool hasMore;

  FileLoadResult(List<EnteFile> files, this.hasMore) {
    if (files.runtimeType == <EnteFile>[].runtimeType) {
      // Runtime type is already List<EnteFile>, no need to create a copy.
      this.files = files;
    } else {
      // If the runtime type of the list is not List<EnteFile>, then create a copy, to avoid covariance problems.
      this.files = List<EnteFile>.of(files);
    }
  }
}
