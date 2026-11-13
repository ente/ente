import "package:flutter/foundation.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";
import "package:sqlite_async/sqlite3_common.dart";
import "package:sqlite_async/sqlite_async.dart";

class DatabaseDowngradeError extends Error {
  DatabaseDowngradeError(this.message);

  final String message;

  @override
  String toString() => message;
}

mixin SqlDbBase {
  static final Map<int, String> _params = <int, String>{};

  Future<SqliteDatabase>? _dbFuture;

  static String getParams(int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, "count", "must be greater than 0");
    }
    return _params.putIfAbsent(count, () => List.filled(count, "?").join(", "));
  }

  Future<SqliteDatabase> getOrOpenDatabase(
    Future<SqliteDatabase> Function() openDatabase,
  ) async {
    final future = _dbFuture ??= openDatabase();
    try {
      return await future;
    } catch (e) {
      if (e is! DatabaseDowngradeError && identical(_dbFuture, future)) {
        _dbFuture = null;
      }
      rethrow;
    }
  }

  @protected
  void resetDatabaseFuture() {
    _dbFuture = null;
  }

  Future<SqliteDatabase> openMigratedDatabase(
    String dbName,
    List<String> migrationScripts, {
    int maxReaders = 1,
    void Function(String path)? logPath,
  }) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, dbName);
    logPath?.call(path);
    final database = SqliteDatabase(path: path, maxReaders: maxReaders);
    try {
      await migrate(database, migrationScripts);
      return database;
    } catch (_) {
      try {
        await database.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> migrate(
    SqliteDatabase database,
    List<String> migrationScripts,
  ) async {
    final toVersion = migrationScripts.length;
    final probe = await database.writeLock(
      (tx) => tx.get('PRAGMA user_version'),
    );
    final probedVersion = probe['user_version'] as int;

    if (probedVersion > toVersion) {
      throw DatabaseDowngradeError(
        "currentVersion($probedVersion) cannot be greater than toVersion($toVersion)",
      );
    }
    if (probedVersion == toVersion) {
      return;
    }

    final didMigrate = await database.writeTransaction((tx) async {
      final result = await tx.get('PRAGMA user_version');
      final currentVersion = result['user_version'] as int;

      if (currentVersion > toVersion) {
        throw DatabaseDowngradeError(
          "currentVersion($currentVersion) cannot be greater than toVersion($toVersion)",
        );
      }
      if (currentVersion == toVersion) {
        return false;
      }

      debugPrint(
        "$runtimeType migrating database from $currentVersion to $toVersion",
      );
      for (int i = currentVersion + 1; i <= toVersion; i++) {
        try {
          final script = migrationScripts[i - 1];
          await tx.computeWithDatabase(_scriptExecutor(script));
        } catch (e) {
          debugPrint(
            "$runtimeType Error running migration script index ${i - 1} $e",
          );
          rethrow;
        }
      }
      await tx.execute('PRAGMA user_version = $toVersion');
      return true;
    });

    if (didMigrate) {
      await database.refreshSchema();
    }
  }
}

Future<void> Function(CommonDatabase) _scriptExecutor(String script) {
  return (database) async {
    database.execute(script);
  };
}
