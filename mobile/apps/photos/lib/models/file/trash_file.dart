import 'package:photos/models/file/file.dart';

class TrashFile extends EnteFile {
  TrashFile();

  TrashFile.fromEnteFile(
    super.file, {
    required this.createdAt,
    required this.updateAt,
    required this.deleteBy,
    required this.isSystemOnly,
    required this.systemTrashID,
  }) : super.from();

  // time when file was put in the trash for first time
  late int createdAt;

  // for non-deleted trash items, updateAt is usually equal to the latest time
  // when the file was moved to trash
  late int updateAt;

  // time after which will will be deleted from trash & user's storage usage
  // will go down
  late int deleteBy;

  // This file is not present on Ente's trash because it was never uploaded, systemTrashID will not not null.
  bool isSystemOnly = false;

  // The local file ID of this file if there is a corresponding entry in the system trash on this device, this may be != localID
  int? systemTrashID;
}
