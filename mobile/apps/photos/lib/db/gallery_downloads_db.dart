import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/db/common/base.dart";
import "package:photos/module/download/task.dart";
import "package:sqlite_async/sqlite_async.dart";

class GalleryDownloadsDB with SqlDbBase {
  static const _databaseName = "ente.gallery_downloads.db";
  static const tableName = "gallery_download_tasks";

  static const columnID = "id";
  static const columnFilename = "filename";
  static const columnTotalBytes = "total_bytes";
  static const columnBytesDownloaded = "bytes_downloaded";
  static const columnStatus = "status";
  static const columnError = "error";
  static const columnFilePath = "file_path";
  static const columnSourceFile = "source_file";
  static const columnCreatedAt = "created_at";
  static const columnUpdatedAt = "updated_at";

  static final Logger _logger = Logger("GalleryDownloadsDB");

  static final _migrationScripts = [
    '''
    CREATE TABLE IF NOT EXISTS $tableName (
      $columnID INTEGER PRIMARY KEY,
      $columnFilename TEXT NOT NULL,
      $columnTotalBytes INTEGER NOT NULL,
      $columnBytesDownloaded INTEGER NOT NULL DEFAULT 0,
      $columnStatus TEXT NOT NULL,
      $columnError TEXT,
      $columnFilePath TEXT,
      $columnCreatedAt INTEGER NOT NULL,
      $columnUpdatedAt INTEGER NOT NULL
    );
    ''',
    '''
    CREATE INDEX IF NOT EXISTS gallery_download_tasks_updated_at_index
    ON $tableName($columnUpdatedAt);
    ''',
    '''
    ALTER TABLE $tableName ADD COLUMN $columnSourceFile TEXT;
    ''',
  ];

  GalleryDownloadsDB._privateConstructor();

  static final GalleryDownloadsDB instance =
      GalleryDownloadsDB._privateConstructor();

  static Future<SqliteDatabase>? _sqliteAsyncDBFuture;

  Future<SqliteDatabase> get sqliteAsyncDB async {
    _sqliteAsyncDBFuture ??= _initSqliteAsyncDatabase();
    return _sqliteAsyncDBFuture!;
  }

  Future<SqliteDatabase> _initSqliteAsyncDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    _logger.info("DB path $path");
    final database = SqliteDatabase(path: path);
    await migrate(database, _migrationScripts);
    return database;
  }

  Future<void> upsertTask(DownloadTask task) async {
    final db = await sqliteAsyncDB;
    await db.execute(
      '''
      INSERT OR REPLACE INTO $tableName (
        $columnID,
        $columnFilename,
        $columnTotalBytes,
        $columnBytesDownloaded,
        $columnStatus,
        $columnError,
        $columnFilePath,
        $columnSourceFile,
        $columnCreatedAt,
        $columnUpdatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        task.id,
        task.filename,
        task.totalBytes,
        task.bytesDownloaded,
        task.status.name,
        task.error,
        task.filePath,
        task.sourceFileJson,
        task.createdAt,
        task.updatedAt,
      ],
    );
  }

  Future<List<DownloadTask>> getAllTasks() async {
    final db = await sqliteAsyncDB;
    final rows = await db.getAll('''
      SELECT
        $columnID as id,
        $columnFilename as filename,
        $columnTotalBytes as totalBytes,
        $columnBytesDownloaded as bytesDownloaded,
        $columnStatus as status,
        $columnError as error,
        $columnFilePath as filePath,
        $columnSourceFile as sourceFileJson,
        $columnCreatedAt as createdAt,
        $columnUpdatedAt as updatedAt
      FROM $tableName
      ORDER BY $columnCreatedAt ASC
      ''');
    return rows.map((row) => DownloadTask.fromMap(row)).toList();
  }

  Future<void> deleteTask(int id) async {
    final db = await sqliteAsyncDB;
    await db.execute("DELETE FROM $tableName WHERE $columnID = ?", [id]);
  }

  Future<void> deleteTasks(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final db = await sqliteAsyncDB;
    final params = List.filled(ids.length, "?").join(", ");
    await db.execute(
      "DELETE FROM $tableName WHERE $columnID IN ($params)",
      ids,
    );
  }

  Future<void> clearTable() async {
    final db = await sqliteAsyncDB;
    await db.execute("DELETE FROM $tableName");
  }
}
