import 'package:photos/models/file/file.dart';

class TrashFile extends EnteFile {
  // Keep the asset ID after localID is cleared when the asset is in device trash.
  String? trashedLocalID;

  // time when file was put in the trash for first time
  late int createdAt;

  // for non-deleted trash items, updateAt is usually equal to the latest time
  // when the file was moved to trash
  late int updateAt;

  // time after which will will be deleted from trash & user's storage usage
  // will go down
  late int deleteBy;
}
