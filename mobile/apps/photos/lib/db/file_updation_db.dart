import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_migration/sqflite_migration.dart';

class FileUpdationDB {
  static const _databaseName = "ente.files_migration.db";
  static final Logger _logger = Logger((FileUpdationDB).toString());

  static const tableName = 're_upload_tracker';
  static const columnLocalID = 'local_id';
  static const columnReason = 'reason';
  static const androidMissingGPS = 'androidMissingGPS';

  static const modificationTimeUpdated = 'modificationTimeUpdated';

  // SQL code to create the database table
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
  final dbConfig = MigrationConfig(
    initializationScript: initializationScript,
    migrationScripts: migrationScripts,
  );

  FileUpdationDB._privateConstructor();

  static final FileUpdationDB instance = FileUpdationDB._privateConstructor();

  // only have a single app-wide reference to the database
  static Future<Database>? _dbFuture;

  Future<Database> get database async {
    // lazily instantiate the db the first time it is accessed
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  // this opens the database (and creates it if it doesn't exist)
  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    debugPrint("DB path " + path);
    return await openDatabaseWithMigration(path, dbConfig);
  }

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.delete(tableName);
  }

  Future<void> insertMultiple(List<String> fileLocalIDs, String reason) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    var batch = db.batch();
    int batchCounter = 0;
    for (String localID in fileLocalIDs) {
      if (batchCounter == 400) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCounter = 0;
      }
      batch.insert(
        tableName,
        _getRowForReUploadTable(localID, reason),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batchCounter++;
    }
    await batch.commit(noResult: true);
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
    final inParam = localIDs.map((id) => "'$id'").join(',');
    final db = await instance.database;
    await db.rawQuery('''
      DELETE FROM $tableName
      WHERE $columnLocalID IN ($inParam) AND $columnReason = '$reason';
    ''');
  }

  // check if entry existing for given localID and reason
  Future<bool> isExisting(String localID, String reason) async {
    final db = await instance.database;
    final String whereClause =
        '$columnLocalID = "$localID" AND $columnReason = "$reason"';
    final rows = await db.query(tableName, where: whereClause);
    return rows.isNotEmpty;
  }

  Future<List<String>> getLocalIDsForPotentialReUpload(
    int limit,
    String reason,
  ) async {
    final db = await instance.database;
    final String whereClause = '$columnReason = "$reason"';
    final rows = await db.query(tableName, limit: limit, where: whereClause);
    final result = <String>[];
    for (final row in rows) {
      result.add(row[columnLocalID] as String);
    }
    return result;
  }

  // delete entries for given list of reasons
  Future<void> deleteByReasons(List<String> reasons) async {
    if (reasons.isEmpty) {
      return;
    }
    final inParam = reasons.map((reason) => "'$reason'").join(',');
    final db = await instance.database;
    await db.rawQuery('''
      DELETE FROM $tableName
      WHERE $columnReason IN ($inParam);
    ''');
  }

  Map<String, dynamic> _getRowForReUploadTable(String localID, String reason) {
    final row = <String, dynamic>{};
    row[columnLocalID] = localID;
    row[columnReason] = reason;
    return row;
  }
}
