import 'package:locker/services/files/sync/models/file.dart';

class TrashFile extends EnteFile {
  // Time first moved to Trash.
  late int createdAt;

  // Most recent move to Trash for active entries.
  late int updateAt;

  // Time when deletion frees the user's storage.
  late int deleteBy;
}
