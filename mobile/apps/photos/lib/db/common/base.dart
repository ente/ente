import "package:flutter/foundation.dart";
import "package:sqlite_async/sqlite_async.dart";

mixin SqlDbBase {
  static final Map<int, String> _params = <int, String>{};

  static String getParams(int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, "count", "must be greater than 0");
    }
    return _params.putIfAbsent(count, () => List.filled(count, "?").join(", "));
  }

  Future<void> migrate(
    SqliteDatabase database,
    List<String> migrationScripts,
  ) async {
    final result = await database.execute('PRAGMA user_version');
    final currentVersion = result[0]['user_version'] as int;
    final toVersion = migrationScripts.length;

    if (currentVersion < toVersion) {
      debugPrint(
        "$runtimeType migrating database from $currentVersion to $toVersion",
      );
      await database.writeTransaction((tx) async {
        for (int i = currentVersion + 1; i <= toVersion; i++) {
          try {
            await tx.execute(migrationScripts[i - 1]);
          } catch (e) {
            debugPrint(
              "$runtimeType Error running migration script index ${i - 1} $e",
            );
            rethrow;
          }
        }
        await tx.execute('PRAGMA user_version = $toVersion');
      });
    } else if (currentVersion > toVersion) {
      throw AssertionError(
        "currentVersion($currentVersion) cannot be greater than toVersion($toVersion)",
      );
    }
  }
}
