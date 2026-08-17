import 'package:photos/models/file/file.dart';

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
}
