import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photos/db/common/base.dart';
import 'package:sqlite_async/sqlite_async.dart';

class FileUpdationDB with SqlDbBase {
  static const _databaseName = "ente.files_migration.db";
  static final Logger _logger = Logger((FileUpdationDB).toString());

  static const tableName = 're_upload_tracker';
  static const columnLocalID = 'local_id';
  static const columnReason = 'reason';
  static const androidMissingGPS = 'androidMissingGPS';

  static const modificationTimeUpdated = 'modificationTimeUpdated';

  static List<String> _createTable() {
    return [
      '''
      CREATE TABLE $tableName (
      $columnLocalID TEXT NOT NULL,
      UNIQUE($columnLocalID)
      ); 
      ''',
    ];
  }

  static List<String> addReasonColumn() {
    return [
      '''
        ALTER TABLE $tableName ADD COLUMN $columnReason TEXT;
      ''',
      '''
        UPDATE $tableName SET $columnReason = '$modificationTimeUpdated';
      ''',
    ];
  }

  static final initializationScript = [..._createTable()];
  static final migrationScripts = [...addReasonColumn()];
  FileUpdationDB._privateConstructor();

  static final FileUpdationDB instance = FileUpdationDB._privateConstructor();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(_databaseName, [
      ...initializationScript,
      ...migrationScripts,
    ], logPath: (path) => debugPrint("DB path " + path)),
  );

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.execute('DELETE FROM $tableName');
  }

  Future<void> insertMultiple(List<String> fileLocalIDs, String reason) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    await _insertBatch(db, [
      for (final localID in fileLocalIDs) [localID, reason],
    ]);
    final endTime = DateTime.now();
    final duration = Duration(
      microseconds:
          endTime.microsecondsSinceEpoch - startTime.microsecondsSinceEpoch,
    );
    _logger.info(
      "Batch insert of ${fileLocalIDs.length} updated files due to $reason "
      "took ${duration.inMilliseconds} ms.",
    );
  }

  Future<void> deleteByLocalIDs(List<String> localIDs, String reason) async {
    if (localIDs.isEmpty) {
      return;
    }
    final db = await instance.database;
    await db.executeBatch(
      '''
      DELETE FROM $tableName
      WHERE $columnLocalID = ? AND $columnReason = ?;
    ''',
      [
        for (final localID in localIDs) [localID, reason],
      ],
    );
  }

  Future<bool> isExisting(String localID, String reason) async {
    final db = await instance.database;
    final rows = await db.getAll(
      '''
      SELECT 1 FROM $tableName
      WHERE $columnLocalID = ? AND $columnReason = ?
      LIMIT 1
      ''',
      [localID, reason],
    );
    return rows.isNotEmpty;
  }

  Future<List<String>> getLocalIDsForPotentialReUpload(
    int limit,
    String reason,
  ) async {
    final db = await instance.database;
    final rows = await db.getAll(
      '''
      SELECT $columnLocalID FROM $tableName
      WHERE $columnReason = ?
      LIMIT ?
      ''',
      [reason, limit],
    );
    final result = <String>[];
    for (final row in rows) {
      result.add(row[columnLocalID] as String);
    }
    return result;
  }

  Future<void> deleteByReasons(List<String> reasons) async {
    if (reasons.isEmpty) {
      return;
    }
    final db = await instance.database;
    await db.executeBatch(
      '''
      DELETE FROM $tableName
      WHERE $columnReason = ?;
    ''',
      [
        for (final reason in reasons) [reason],
      ],
    );
  }

  Future<void> _insertBatch(
    SqliteDatabase db,
    List<List<Object?>> parameterSets,
  ) async {
    if (parameterSets.isEmpty) return;
    await db.executeBatch('''
      INSERT OR REPLACE INTO $tableName ($columnLocalID, $columnReason)
      VALUES (?, ?)
      ''', parameterSets);
  }
}
