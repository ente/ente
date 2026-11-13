import "package:photos/core/configuration.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/services/collections_service.dart";

extension FilePropsExtn on EnteFile {
  bool get isLivePhoto => fileType == FileType.livePhoto;

  bool get isMotionPhoto => (pubMagicMetadata?.mvi ?? 0) > 0;

  bool get isLiveOrMotionPhoto => isLivePhoto || isMotionPhoto;

  bool get isOwner =>
      (ownerID == null) || (ownerID == Configuration.instance.getUserID());

  bool get isVideo => fileType == FileType.video;

  bool get hasDims => height > 0 && width > 0;

  bool? isPanorama() {
    if (fileType != FileType.image) {
      return false;
    }
    if (pubMagicMetadata?.mediaType != null) {
      return (pubMagicMetadata!.mediaType! & 1) == 1;
    }
    return null;
  }

  bool canBePanorama() {
    if (hasDims) {
      if (height < 8000 && width < 8000) return false;
      if (height > width) {
        return height / width >= 2.0;
      }
      return width / height >= 2.0;
    }
    return false;
  }

  bool get canEditMetaInfo => isUploaded && isOwner;

  bool get isTrash => this is TrashFile;
  bool get isEnteTrash => this is EnteTrashFile;
  bool get isDeviceTrash => this is DeviceTrashFile;
  TrashFile? get asTrashFile => (this is TrashFile) ? this as TrashFile : null;
  EnteTrashFile? get asEnteTrashFile =>
      (this is EnteTrashFile) ? this as EnteTrashFile : null;
  DeviceTrashFile? get asDeviceTrashFile =>
      (this is DeviceTrashFile) ? this as DeviceTrashFile : null;

  bool get isCollect => uploaderName != null;

  String? get uploaderName => pubMagicMetadata?.uploaderName;

  String? get cameraMake => pubMagicMetadata?.cameraMake;

  String? get cameraModel => pubMagicMetadata?.cameraModel;

  String? get cameraLabel {
    final make = cameraMake?.trim();
    final model = cameraModel?.trim();
    if ((make == null || make.isEmpty) && (model == null || model.isEmpty)) {
      return null;
    }
    if (make != null && make.isNotEmpty && model != null && model.isNotEmpty) {
      return '$make $model';
    }
    return model ?? make;
  }

  bool get skipIndex => !isUploaded || fileType == FileType.other;

  bool canReUpload(int userID) =>
      localID != null &&
      localID!.isNotEmpty &&
      isOwner &&
      collectionID != null &&
      (CollectionsService.instance
              .getCollectionByID(collectionID!)
              ?.isOwner(userID) ??
          false);
}

Set<int> filesToUploadedFileIDs(Iterable<EnteFile> files) => files
    .where((file) => file.isUploaded)
    .map((file) => file.uploadedFileID!)
    .toSet();
