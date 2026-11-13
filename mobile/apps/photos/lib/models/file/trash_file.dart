import "package:photo_manager/photo_manager.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";

sealed class TrashFile extends EnteFile {
  TrashFile();

  TrashFile.from(super.file, {required this.deleteBy}) : super.from();

  // Time when deletion frees the user's storage.
  late int deleteBy;
}

class EnteTrashFile extends TrashFile {
  EnteTrashFile();

  EnteTrashFile.from(
    super.file, {
    required super.deleteBy,
    required this.createdAt,
    required this.updateAt,
  }) : super.from();

  // Time first moved to Trash.
  late int createdAt;

  // Most recent move to Trash for active entries.
  late int updateAt;
}

class DeviceTrashFile extends TrashFile {
  DeviceTrashFile();

  DeviceTrashFile.from(super.file, {required super.deleteBy}) : super.from();

  AssetEntity toAssetEntity() {
    return AssetEntity(
      id: localID!,
      typeInt: switch (fileType) {
        FileType.image || FileType.livePhoto => AssetType.image.index,
        FileType.video => AssetType.video.index,
        FileType.other => AssetType.other.index,
      },
      width: 0,
      height: 0,
    );
  }
}
