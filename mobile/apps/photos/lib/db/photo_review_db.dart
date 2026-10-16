import "package:collection/collection.dart";
import "package:logging/logging.dart";
import "package:photos/db/common/base.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:sqlite_async/sqlite_async.dart";

class PhotoReviewDB with SqlDbBase {
  static const _databaseName = "ente.photo_review.db";
  static const decisionsTable = "review_decisions";
  static const monthsTable = "review_months";

  static const columnFileKey = "file_key";
  static const columnUploadedFileID = "uploaded_file_id";
  static const columnLocalID = "local_id";
  static const columnMonthKey = "month_key";
  static const columnDecision = "decision";
  static const columnUpdatedAt = "updated_at";
  static const columnMarkedReviewed = "marked_reviewed";
  static const columnFreedBytes = "freed_bytes";
  static const columnFreedCount = "freed_count";

  static const _lookupChunkSize = 500;

  static final Logger _logger = Logger("PhotoReviewDB");

  static final _migrationScripts = [
    '''
    CREATE TABLE IF NOT EXISTS $decisionsTable (
      $columnFileKey TEXT PRIMARY KEY,
      $columnUploadedFileID INTEGER,
      $columnLocalID TEXT,
      $columnMonthKey TEXT NOT NULL,
      $columnDecision INTEGER NOT NULL,
      $columnUpdatedAt INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS review_decisions_month_index
    ON $decisionsTable($columnMonthKey);
    CREATE INDEX IF NOT EXISTS review_decisions_local_id_index
    ON $decisionsTable($columnLocalID);
    CREATE TABLE IF NOT EXISTS $monthsTable (
      $columnMonthKey TEXT PRIMARY KEY,
      $columnMarkedReviewed INTEGER NOT NULL DEFAULT 0,
      $columnFreedBytes INTEGER NOT NULL DEFAULT 0,
      $columnFreedCount INTEGER NOT NULL DEFAULT 0,
      $columnUpdatedAt INTEGER NOT NULL
    );
    ''',
  ];

  PhotoReviewDB._privateConstructor();

  static final PhotoReviewDB instance = PhotoReviewDB._privateConstructor();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(
      _databaseName,
      _migrationScripts,
      logPath: (path) => _logger.info("DB path $path"),
    ),
  );

  Future<List<ReviewDecisionRecord>> getAllDecisions() async {
    final db = await database;
    final rows = await db.getAll("SELECT * FROM $decisionsTable");
    return rows.map(_decisionFromRow).toList();
  }

  Future<List<ReviewDecisionRecord>> getDecisionsForFiles(
    List<String> fileKeys,
    List<String> localIDs,
  ) async {
    final db = await database;
    return db.readTransaction((tx) async {
      final records = <ReviewDecisionRecord>[];
      for (final (column, values) in [
        (columnFileKey, fileKeys),
        (columnLocalID, localIDs),
      ]) {
        for (final chunk in values.slices(_lookupChunkSize)) {
          final placeholders = List.filled(chunk.length, "?").join(",");
          final rows = await tx.getAll(
            "SELECT * FROM $decisionsTable WHERE $column IN ($placeholders)",
            chunk,
          );
          records.addAll(rows.map(_decisionFromRow));
        }
      }
      return records;
    });
  }

  Future<Map<String, ReviewMonthRecord>> getMonthRecords() async {
    final db = await database;
    final rows = await db.getAll("SELECT * FROM $monthsTable");
    return {
      for (final row in rows) row[columnMonthKey] as String: _monthFromRow(row),
    };
  }

  Future<ReviewMonthRecord?> getMonthRecord(String monthKey) async {
    final db = await database;
    final row = await db.getOptional(
      "SELECT * FROM $monthsTable WHERE $columnMonthKey = ?",
      [monthKey],
    );
    return row == null ? null : _monthFromRow(row);
  }

  Future<void> saveDecisions(
    List<ReviewDecisionRecord> records,
    String monthKey,
    int updatedAt,
  ) async {
    if (records.isEmpty) return;
    final db = await database;
    await db.writeTransaction((tx) async {
      await _upsertDecisions(tx, records);
      await _touchMonth(tx, monthKey, updatedAt);
    });
  }

  Future<void> rekeyDecisions(
    List<ReviewDecisionRecord> records,
    List<String> staleKeys,
  ) async {
    if (records.isEmpty) return;
    final db = await database;
    await db.writeTransaction((tx) async {
      await _upsertDecisions(tx, records);
      await tx.executeBatch(
        "DELETE FROM $decisionsTable WHERE $columnFileKey = ?",
        [
          for (final key in staleKeys) [key],
        ],
      );
    });
  }

  Future<void> deleteDecision(
    String fileKey,
    String? localID,
    String monthKey,
    int updatedAt,
  ) async {
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.execute(
        '''
        DELETE FROM $decisionsTable
        WHERE $columnFileKey = ? OR $columnLocalID = ?
        ''',
        [fileKey, localID],
      );
      await _touchMonth(tx, monthKey, updatedAt);
    });
  }

  Future<void> recordDeletion(
    List<ReviewDecisionRecord> records,
    String monthKey,
    int freedBytes,
    int updatedAt,
  ) async {
    if (records.isEmpty) return;
    final db = await database;
    await db.writeTransaction((tx) async {
      await _upsertDecisions(tx, records);
      await tx.execute(
        '''
        INSERT INTO $monthsTable (
          $columnMonthKey, $columnFreedBytes, $columnFreedCount, $columnUpdatedAt
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT($columnMonthKey) DO UPDATE SET
          $columnFreedBytes = $columnFreedBytes + excluded.$columnFreedBytes,
          $columnFreedCount = $columnFreedCount + excluded.$columnFreedCount,
          $columnUpdatedAt = excluded.$columnUpdatedAt
        ''',
        [monthKey, freedBytes, records.length, updatedAt],
      );
    });
  }

  Future<void> markMonthsReviewed(List<String> monthKeys, int updatedAt) async {
    if (monthKeys.isEmpty) return;
    final db = await database;
    await db.executeBatch(
      '''
      INSERT INTO $monthsTable (
        $columnMonthKey, $columnMarkedReviewed, $columnUpdatedAt
      ) VALUES (?, 1, ?)
      ON CONFLICT($columnMonthKey) DO UPDATE SET
        $columnMarkedReviewed = 1,
        $columnUpdatedAt = excluded.$columnUpdatedAt
      ''',
      [
        for (final key in monthKeys) [key, updatedAt],
      ],
    );
  }

  Future<void> unmarkMonthReviewed(String monthKey, int updatedAt) async {
    final db = await database;
    await db.execute(
      '''
      UPDATE $monthsTable
      SET $columnMarkedReviewed = 0, $columnUpdatedAt = ?
      WHERE $columnMonthKey = ?
      ''',
      [updatedAt, monthKey],
    );
  }

  Future<void> resetMonths(List<String> monthKeys) async {
    if (monthKeys.isEmpty) return;
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.executeBatch(
        "DELETE FROM $decisionsTable WHERE $columnMonthKey = ?",
        [
          for (final key in monthKeys) [key],
        ],
      );
      await tx.executeBatch(
        "DELETE FROM $monthsTable WHERE $columnMonthKey = ?",
        [
          for (final key in monthKeys) [key],
        ],
      );
    });
  }

  Future<void> clearTable() async {
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.execute("DELETE FROM $decisionsTable");
      await tx.execute("DELETE FROM $monthsTable");
    });
  }

  Future<void> _upsertDecisions(
    SqliteWriteContext tx,
    List<ReviewDecisionRecord> records,
  ) {
    return tx.executeBatch(
      '''
      INSERT OR REPLACE INTO $decisionsTable (
        $columnFileKey, $columnUploadedFileID, $columnLocalID,
        $columnMonthKey, $columnDecision, $columnUpdatedAt
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        for (final record in records)
          [
            record.fileKey,
            record.uploadedFileID,
            record.localID,
            record.monthKey,
            record.decision.storedValue,
            record.updatedAt,
          ],
      ],
    );
  }

  Future<void> _touchMonth(
    SqliteWriteContext tx,
    String monthKey,
    int updatedAt,
  ) {
    return tx.execute(
      '''
      INSERT INTO $monthsTable ($columnMonthKey, $columnUpdatedAt)
      VALUES (?, ?)
      ON CONFLICT($columnMonthKey) DO UPDATE SET
        $columnUpdatedAt = excluded.$columnUpdatedAt
      ''',
      [monthKey, updatedAt],
    );
  }

  ReviewDecisionRecord _decisionFromRow(Map<String, dynamic> row) {
    return ReviewDecisionRecord(
      fileKey: row[columnFileKey] as String,
      uploadedFileID: row[columnUploadedFileID] as int?,
      localID: row[columnLocalID] as String?,
      monthKey: row[columnMonthKey] as String,
      decision: ReviewDecision.fromStoredValue(row[columnDecision] as int),
      updatedAt: row[columnUpdatedAt] as int,
    );
  }

  ReviewMonthRecord _monthFromRow(Map<String, dynamic> row) {
    return ReviewMonthRecord(
      monthKey: row[columnMonthKey] as String,
      markedReviewed: (row[columnMarkedReviewed] as int) == 1,
      freedBytes: row[columnFreedBytes] as int,
      freedCount: row[columnFreedCount] as int,
      updatedAt: row[columnUpdatedAt] as int,
    );
  }
}
