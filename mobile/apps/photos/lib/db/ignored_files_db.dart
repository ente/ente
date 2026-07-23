import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/models/ignored_file.dart';
import 'package:sqflite/sqflite.dart';

// Keeps track of localIDs which should be not uploaded to ente without
// user's intervention.
// Common use case:
// when a user deletes a file just from ente on current or different device.
class IgnoredFilesDB {
  static const _databaseName = "ente.ignored_files.db";
  static const _databaseVersion = 1;
  static final Logger _logger = Logger("IgnoredFilesDB");
  static const tableName = 'ignored_files';

  static const columnLocalID = 'local_id';
  static const columnTitle = 'title';
  static const columnDeviceFolder = 'device_folder';
  static const columnReason = 'reason';

  Future _onCreate(Database db, int version) async {
    await db.execute('''
        CREATE TABLE $tableName (
          $columnLocalID TEXT NOT NULL,
          $columnTitle TEXT NOT NULL,
          $columnDeviceFolder TEXT NOT NULL,
          $columnReason TEXT DEFAULT $kIgnoreReasonTrash,
          UNIQUE($columnLocalID, $columnTitle, $columnDeviceFolder)
        );
      CREATE INDEX IF NOT EXISTS local_id_index ON $tableName($columnLocalID);
      CREATE INDEX IF NOT EXISTS device_folder_index ON $tableName($columnDeviceFolder);
      ''');
  }

  IgnoredFilesDB._privateConstructor();

  static final IgnoredFilesDB instance = IgnoredFilesDB._privateConstructor();

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
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.delete(tableName);
  }

  Future<void> insertMultiple(List<IgnoredFile> ignoredFiles) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    var batch = db.batch();
    int batchCounter = 0;
    for (IgnoredFile file in ignoredFiles) {
      if (batchCounter == 400) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCounter = 0;
      }
      batch.insert(
        tableName,
        _getRowForIgnoredFile(file),
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
      "Batch insert of ${ignoredFiles.length} "
      "took ${duration.inMilliseconds} ms.",
    );
  }

  Future<List<IgnoredFile>> getAll() async {
    final db = await instance.database;
    final rows = await db.query(tableName);
    final result = <IgnoredFile>[];
    for (final row in rows) {
      result.add(_getIgnoredFileFromRow(row));
    }
    return result;
  }

  Future<void> removeIgnoredEntries(List<IgnoredFile> ignoredFiles) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    var batch = db.batch();
    int batchCounter = 0;
    for (IgnoredFile file in ignoredFiles) {
      if (batchCounter == 400) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCounter = 0;
      }
      // on Android, we track device folder and title to track files to ignore.
      // See IgnoredFileService#_getIgnoreID method for more detail
      if (Platform.isAndroid) {
        batch.rawDelete(
          "DELETE from $tableName WHERE  $columnDeviceFolder = '${file.deviceFolder}' AND $columnTitle = '${file.title}' ",
        );
      } else {
        batch.rawDelete(
          "DELETE from $tableName WHERE $columnLocalID = '${file.localID}' ",
        );
      }
      batchCounter++;
    }
    await batch.commit(noResult: true);
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

  Map<String, dynamic> _getRowForIgnoredFile(IgnoredFile ignoredFile) {
    assert(ignoredFile.title != null);
    assert(ignoredFile.localID != null);
    final row = <String, dynamic>{};
    row[columnLocalID] = ignoredFile.localID;
    row[columnTitle] = ignoredFile.title;
    row[columnDeviceFolder] = ignoredFile.deviceFolder;
    row[columnReason] = ignoredFile.reason;
    return row;
  }
}
