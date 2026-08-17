import 'package:photos/models/file/file.dart';
import "package:photos/services/filter/filter.dart";

class DedupeUploadIDFilter extends Filter {
  final Set<int> trackedUploadIDs = {};

  @override
  bool filter(EnteFile file) {
    if (!file.isUploaded) {
      return true;
    }
    if (trackedUploadIDs.contains(file.uploadedFileID!)) {
      return false;
    }
    trackedUploadIDs.add(file.uploadedFileID!);
    return true;
  }
}
