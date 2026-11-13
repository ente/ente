import "package:logging/logging.dart";
import "package:path/path.dart" show join;
import "package:path_provider/path_provider.dart";
import "package:photos/db/common/base.dart";
import "package:photos/db/ml/schema.dart";
import "package:sqlite_async/sqlite_async.dart";

class OfflineFilesDB with SqlDbBase {
  static final Logger _logger = Logger("OfflineFilesDB");

  static const _databaseName = "ente.offline_files.db";
  static const _maxSqlBindParamsPerQuery = 500;

  OfflineFilesDB._privateConstructor();

  static final OfflineFilesDB instance = OfflineFilesDB._privateConstructor();

  static const List<String> _migrationScripts = [createOfflineFileKeyMapTable];

  Future<SqliteDatabase>? _sqliteAsyncDBFuture;

  Future<SqliteDatabase> get asyncDB async {
    _sqliteAsyncDBFuture ??= _initSqliteAsyncDatabase();
    return _sqliteAsyncDBFuture!;
  }

  Future<SqliteDatabase> _initSqliteAsyncDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String databaseDirectory = join(
      documentsDirectory.path,
      _databaseName,
    );
    _logger.info("Opening offline files DB at $databaseDirectory");
    final asyncDBConnection = SqliteDatabase(
      path: databaseDirectory,
      maxReaders: 2,
    );
    await migrate(asyncDBConnection, _migrationScripts);
    return asyncDBConnection;
  }

  Future<int> getOrCreateLocalIntId(String localId) async {
    final db = await asyncDB;
    final existing = await db.getAll(
      'SELECT $offlineFileKeyIntIdColumn FROM $offlineFileKeyMapTable WHERE $offlineFileKeyLocalIdColumn = ?',
      [localId],
    );
    if (existing.isNotEmpty) {
      return existing.first[offlineFileKeyIntIdColumn] as int;
    }
    await db.execute(
      'INSERT INTO $offlineFileKeyMapTable ($offlineFileKeyLocalIdColumn) VALUES (?)',
      [localId],
    );
    final inserted = await db.getAll(
      'SELECT $offlineFileKeyIntIdColumn FROM $offlineFileKeyMapTable WHERE $offlineFileKeyLocalIdColumn = ?',
      [localId],
    );
    return inserted.first[offlineFileKeyIntIdColumn] as int;
  }

  Future<String?> getLocalIdForIntId(int localIntId) async {
    final db = await asyncDB;
    final result = await db.getAll(
      'SELECT $offlineFileKeyLocalIdColumn FROM $offlineFileKeyMapTable WHERE $offlineFileKeyIntIdColumn = ?',
      [localIntId],
    );
    if (result.isEmpty) return null;
    return result.first[offlineFileKeyLocalIdColumn] as String?;
  }

  Future<Map<int, String>> getLocalIdsForIntIds(
    Iterable<int> localIntIds,
  ) async {
    final ids = localIntIds.toSet().toList();
    if (ids.isEmpty) return {};
    final db = await asyncDB;
    final mapping = <int, String>{};
    for (final chunk in _chunkSqlBindParams(ids)) {
      final inParam = List.filled(chunk.length, '?').join(',');
      final result = await db.getAll(
        'SELECT $offlineFileKeyIntIdColumn, $offlineFileKeyLocalIdColumn FROM $offlineFileKeyMapTable WHERE $offlineFileKeyIntIdColumn IN ($inParam)',
        chunk,
      );
      for (final row in result) {
        mapping[row[offlineFileKeyIntIdColumn] as int] =
            row[offlineFileKeyLocalIdColumn] as String;
      }
    }
    return mapping;
  }

  Future<Map<String, int>> getLocalIntIdsForLocalIds(
    Iterable<String> localIds,
  ) async {
    final ids = localIds.toSet().toList();
    if (ids.isEmpty) return {};
    final db = await asyncDB;
    final mapping = <String, int>{};
    for (final chunk in _chunkSqlBindParams(ids)) {
      final inParam = List.filled(chunk.length, '?').join(',');
      final result = await db.getAll(
        'SELECT $offlineFileKeyLocalIdColumn, $offlineFileKeyIntIdColumn FROM $offlineFileKeyMapTable WHERE $offlineFileKeyLocalIdColumn IN ($inParam)',
        chunk,
      );
      for (final row in result) {
        mapping[row[offlineFileKeyLocalIdColumn] as String] =
            row[offlineFileKeyIntIdColumn] as int;
      }
    }
    return mapping;
  }

  Future<Map<String, int>> ensureLocalIntIds(Iterable<String> localIds) async {
    final ids = localIds.toSet().toList();
    if (ids.isEmpty) return {};
    final existing = await getLocalIntIdsForLocalIds(ids);
    final missing = ids.where((id) => !existing.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final db = await asyncDB;
      final inputs = missing.map((id) => [id]).toList();
      await db.executeBatch(
        'INSERT OR IGNORE INTO $offlineFileKeyMapTable ($offlineFileKeyLocalIdColumn) VALUES (?)',
        inputs,
      );
      final inserted = await getLocalIntIdsForLocalIds(missing);
      existing.addAll(inserted);
    }
    return existing;
  }

  Iterable<List<T>> _chunkSqlBindParams<T>(List<T> values) sync* {
    for (var i = 0; i < values.length; i += _maxSqlBindParamsPerQuery) {
      final end = i + _maxSqlBindParamsPerQuery;
      yield values.sublist(i, end > values.length ? values.length : end);
    }
  }
}
