import 'package:photos/models/file/trash_file.dart';

const kIgnoreReasonTrash = "trash";

class IgnoredFile {
  final String? localID;
  final String? title;
  final String? deviceFolder;
  String reason;

  IgnoredFile(this.localID, this.title, this.deviceFolder, this.reason);

  static IgnoredFile? fromTrashItem(TrashFile? trashFile) {
    if (trashFile == null) return null;
    if (trashFile.localID == null ||
        trashFile.localID!.isEmpty ||
        trashFile.title == null ||
        trashFile.title!.isEmpty ||
        trashFile.deviceFolder == null ||
        trashFile.deviceFolder!.isEmpty) {
      return null;
    }

    return IgnoredFile(
      trashFile.localID,
      trashFile.title,
      trashFile.deviceFolder,
      kIgnoreReasonTrash,
    );
  }
}
