import 'dart:async';

import 'package:photos/db/common/base.dart';
import 'package:photos/models/memories/memory.dart';
import 'package:sqlite_async/sqlite_async.dart';

class MemoriesDB with SqlDbBase {
  static const _databaseName = "ente.memories.db";

  static const table = 'memories';

  static const columnFileID = 'file_id';
  static const columnSeenTime = 'seen_time';

  static const _migrationScripts = [
    '''
      CREATE TABLE $table (
        $columnFileID INTEGER PRIMARY KEY NOT NULL,
        $columnSeenTime TEXT NOT NULL
      )
      ''',
  ];

  final String _dbName;

  MemoriesDB._privateConstructor({String dbName = _databaseName})
    : _dbName = dbName;
  static final MemoriesDB instance = MemoriesDB._privateConstructor();
  static final MemoriesDB localGalleryInstance = MemoriesDB._privateConstructor(
    dbName: "ente.memories.offline.db",
  );

  Future<SqliteDatabase> get database =>
      getOrOpenDatabase(() => openMigratedDatabase(_dbName, _migrationScripts));

  Future<void> clearTable() async {
    final db = await database;
    await db.execute('DELETE FROM $table');
  }

  Future<void> clearMemoriesSeenBeforeTime(int timestamp) async {
    final db = await database;
    await db.execute('DELETE FROM $table WHERE $columnSeenTime < ?', [
      timestamp,
    ]);
  }

  Future<void> markMemoryAsSeen(
    Memory memory,
    int timestamp, {
    int? seenTimeKey,
  }) async {
    final db = await database;
    await db.execute(
      '''
      INSERT OR REPLACE INTO $table ($columnFileID, $columnSeenTime)
      VALUES (?, ?)
      ''',
      [seenTimeKey ?? memory.file.generatedID, timestamp],
    );
  }

  Future<Map<int, int>> getSeenTimes() async {
    final db = await database;
    return _convertToSeenTimes(await db.getAll('SELECT * FROM $table'));
  }

  Map<int, int> _convertToSeenTimes(List<Map<String, dynamic>> rows) {
    final seenTimes = <int, int>{};
    for (final row in rows) {
      seenTimes[row[columnFileID]] = int.parse(row[columnSeenTime]);
    }
    return seenTimes;
  }
}
