import 'dart:io';

import 'package:logging/logging.dart';
import 'package:photos/db/common/base.dart';
import 'package:photos/models/ignored_file.dart';
import 'package:sqlite_async/sqlite_async.dart';

// Prevent files deleted from Ente from being reuploaded without user action.
class IgnoredFilesDB with SqlDbBase {
  static const _databaseName = "ente.ignored_files.db";
  static final Logger _logger = Logger("IgnoredFilesDB");
  static const tableName = 'ignored_files';

  static const columnLocalID = 'local_id';
  static const columnTitle = 'title';
  static const columnDeviceFolder = 'device_folder';
  static const columnReason = 'reason';

  static const _migrationScripts = [
    '''
        CREATE TABLE $tableName (
          $columnLocalID TEXT NOT NULL,
          $columnTitle TEXT NOT NULL,
          $columnDeviceFolder TEXT NOT NULL,
          $columnReason TEXT DEFAULT $kIgnoreReasonTrash,
          UNIQUE($columnLocalID, $columnTitle, $columnDeviceFolder)
        );
      CREATE INDEX IF NOT EXISTS local_id_index ON $tableName($columnLocalID);
      CREATE INDEX IF NOT EXISTS device_folder_index ON $tableName($columnDeviceFolder);
      ''',
  ];

  IgnoredFilesDB._privateConstructor();

  static final IgnoredFilesDB instance = IgnoredFilesDB._privateConstructor();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(_databaseName, _migrationScripts),
  );

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.execute('DELETE FROM $tableName');
  }

  Future<void> insertMultiple(List<IgnoredFile> ignoredFiles) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    await _insertBatch(db, [
      for (final file in ignoredFiles)
        [file.localID, file.title, file.deviceFolder, file.reason],
    ]);
    final endTime = DateTime.now();
    final duration = Duration(
      microseconds:
          endTime.microsecondsSinceEpoch - startTime.microsecondsSinceEpoch,
    );
    _logger.info(
      "Batch insert of ${ignoredFiles.length} "
      "took ${duration.inMilliseconds} ms.",
    );
  }

  Future<List<IgnoredFile>> getAll() async {
    final db = await instance.database;
    final rows = await db.getAll('SELECT * FROM $tableName');
    final result = <IgnoredFile>[];
    for (final row in rows) {
      result.add(_getIgnoredFileFromRow(row));
    }
    return result;
  }

  Future<void> removeIgnoredEntries(List<IgnoredFile> ignoredFiles) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    await _deleteBatch(db, [
      for (final file in ignoredFiles)
        Platform.isAndroid ? [file.deviceFolder, file.title] : [file.localID],
    ]);
    final endTime = DateTime.now();
    final duration = Duration(
      microseconds:
          endTime.microsecondsSinceEpoch - startTime.microsecondsSinceEpoch,
    );
    _logger.info(
      "Batch delete for ${ignoredFiles.length} "
      "took ${duration.inMilliseconds} ms.",
    );
  }

  IgnoredFile _getIgnoredFileFromRow(Map<String, dynamic> row) {
    return IgnoredFile(
      row[columnLocalID],
      row[columnTitle],
      row[columnDeviceFolder],
      row[columnReason],
    );
  }

  Future<void> _insertBatch(
    SqliteDatabase db,
    List<List<Object?>> parameterSets,
  ) async {
    if (parameterSets.isEmpty) return;
    await db.executeBatch('''
      INSERT OR REPLACE INTO $tableName (
        $columnLocalID, $columnTitle, $columnDeviceFolder, $columnReason
      ) VALUES (?, ?, ?, ?)
      ''', parameterSets);
  }

  Future<void> _deleteBatch(
    SqliteDatabase db,
    List<List<Object?>> parameterSets,
  ) async {
    if (parameterSets.isEmpty) return;
    final sql = Platform.isAndroid
        ? 'DELETE FROM $tableName WHERE $columnDeviceFolder = ? AND $columnTitle = ?'
        : 'DELETE FROM $tableName WHERE $columnLocalID = ?';
    await db.executeBatch(sql, parameterSets);
  }
}
