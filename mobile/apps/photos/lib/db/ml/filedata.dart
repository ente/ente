import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/schema.dart";
import "package:photos/services/filedata/model/file_data.dart";

extension FileDataTable on MLDataDB {
  Future<void> putFDStatus(List<FDStatus> fdStatusList) async {
    if (fdStatusList.isEmpty) return;
    final db = await MLDataDB.instance.asyncDB;
    final inputs = <List<Object?>>[];
    for (var status in fdStatusList) {
      inputs.add([
        status.fileID,
        status.userID,
        status.type,
        status.size,
        status.objectID,
        status.objectNonce,
        status.updatedAt,
      ]);
    }
    await db.executeBatch(
      'INSERT OR REPLACE INTO $fileDataTable ($fileIDColumn, user_id, type, size, obj_id, obj_nonce, updated_at ) values(?, ?, ?, ?, ?, ?, ?)',
      inputs,
    );
  }

  Future<Map<int, PreviewInfo>> getFileIDsVidPreview() async {
    final db = await MLDataDB.instance.asyncDB;
    final res = await db.execute(
      "SELECT $fileIDColumn, $objectIdColumn, size FROM $fileDataTable WHERE type='vid_preview'",
    );
    return res.asMap().map(
      (i, e) => MapEntry(
        e[fileIDColumn] as int,
        PreviewInfo(
          objectId: e[objectIdColumn] as String,
          objectSize: e['size'] as int,
        ),
      ),
    );
  }

  Future<Set<int>> getFileIDsWithFDData({DataType? type}) async {
    final db = await MLDataDB.instance.asyncDB;
    final String query = type == null
        ? 'SELECT $fileIDColumn FROM $fileDataTable'
        : 'SELECT $fileIDColumn FROM $fileDataTable WHERE type = ?';
    final List<Object?> args = type == null ? const [] : [type.toJson()];
    final res = args.isEmpty
        ? await db.execute(query)
        : await db.execute(query, args);
    return res.map((e) => e[fileIDColumn] as int).toSet();
  }
}
