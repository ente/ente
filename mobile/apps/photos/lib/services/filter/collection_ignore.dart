import 'package:photos/models/file/file.dart';
import "package:photos/services/filter/filter.dart";

class CollectionsAndSavedFileFilter extends Filter {
  final Set<int> collectionIDs;
  final bool ignoreSavedFiles;
  final int ownerID;

  Set<int>? _ignoredUploadIDs;
  Set<String> ownedFileHashes = {};

  CollectionsAndSavedFileFilter(
    this.collectionIDs,
    this.ownerID,
    List<EnteFile> files,
    this.ignoreSavedFiles,
  ) : super() {
    init(files);
  }

  void init(List<EnteFile> files) {
    _ignoredUploadIDs = {};
    for (var file in files) {
      if (file.collectionID != null && file.isUploaded) {
        if (collectionIDs.contains(file.collectionID!)) {
          _ignoredUploadIDs!.add(file.uploadedFileID!);
        } else if (ignoreSavedFiles &&
            file.ownerID == ownerID &&
            (file.hash ?? '').isNotEmpty) {
          ownedFileHashes.add(file.hash!);
        }
      }
    }
  }

  @override
  bool filter(EnteFile file) {
    if (!file.isUploaded) {
      if (file.collectionID != null &&
          collectionIDs.contains(file.collectionID!)) {
        return false;
      }
      return true;
    }
    if (_ignoredUploadIDs!.contains(file.uploadedFileID!)) {
      return false;
    }
    if (ignoreSavedFiles &&
        file.ownerID != ownerID &&
        (file.hash ?? '').isNotEmpty) {
      return !ownedFileHashes.contains(file.hash!);
    }
    return true;
  }
}
