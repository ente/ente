import 'dart:async';
import 'dart:convert';

import "package:photos/core/errors.dart";
import 'package:photos/db/common/base.dart';
import "package:photos/module/upload/model/multipart.dart";
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

class UploadLocksDB with SqlDbBase {
  static const _databaseName = "ente.upload_locks.db";

  static const _uploadLocksTable = (
    table: "upload_locks",
    columnID: "id",
    columnOwner: "owner",
    columnTime: "time",
  );

  static const _trackUploadTable = (
    table: "track_uploads",
    columnID: "id",
    columnLocalID: "local_id",
    columnFileHash: "file_hash",
    columnCollectionID: "collection_id",
    columnEncryptedFileName: "encrypted_file_name",
    columnEncryptedFileSize: "encrypted_file_size",
    columnEncryptedFileKey: "encrypted_file_key",
    columnFileEncryptionNonce: "file_encryption_nonce",
    columnKeyEncryptionNonce: "key_encryption_nonce",
    columnObjectKey: "object_key",
    columnCompleteUrl: "complete_url",
    columnStatus: "status",
    columnPartSize: "part_size",
    columnLastAttemptedAt: "last_attempted_at",
    columnCreatedAt: "created_at",
    columnFileMd5: "file_md5",
    columnPartMd5s: "part_md5s",
  );

  static const _partsTable = (
    table: "upload_parts",
    columnObjectKey: "object_key",
    columnPartNumber: "part_number",
    columnPartUrl: "part_url",
    columnPartETag: "part_etag",
    columnPartStatus: "part_status",
  );

  static const _streamUploadErrorTable = (
    table: "stream_upload_error",
    columnUploadedFileID: "uploaded_file_id",
    columnErrorMessage: "error_message",
    columnLastAttemptedAt: "last_attempted_at",
    columnCreatedAt: "created_at",
  );

  static const _streamQueueTable = (
    table: "stream_queue",
    columnUploadedFileID: "uploaded_file_id",
    columnQueueType: "queue_type", // 'create' or 'recreate'
    columnCreatedAt: "created_at",
  );

  static final initializationScript = [..._createUploadLocksTable()];

  static final migrationScripts = [
    ..._createTrackUploadsTable(),
    ..._addMD5Columns(),
  ];
  static List<String> _addMD5Columns() {
    return [
      '''
               ALTER TABLE ${_trackUploadTable.table}
               ADD COLUMN  ${_trackUploadTable.columnFileMd5} TEXT;
               ''',
      '''
               ALTER TABLE ${_trackUploadTable.table}
               ADD COLUMN ${_trackUploadTable.columnPartMd5s} TEXT;
               ''',
    ];
  }

  UploadLocksDB._privateConstructor();
  static final UploadLocksDB instance = UploadLocksDB._privateConstructor();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(_databaseName, [
      ...initializationScript,
      ...migrationScripts,
    ]),
  );

  static List<String> _createUploadLocksTable() {
    return [
      '''
                CREATE TABLE ${_uploadLocksTable.table} (
                  ${_uploadLocksTable.columnID} TEXT PRIMARY KEY NOT NULL,
                  ${_uploadLocksTable.columnOwner} TEXT NOT NULL,
                 ${_uploadLocksTable.columnTime} TEXT NOT NULL
                )
                ''',
    ];
  }

  static List<String> _createTrackUploadsTable() {
    return [
      '''
                CREATE TABLE IF NOT EXISTS ${_trackUploadTable.table} (
                  ${_trackUploadTable.columnID} INTEGER PRIMARY KEY,
                  ${_trackUploadTable.columnLocalID} TEXT NOT NULL,
                  ${_trackUploadTable.columnFileHash} TEXT NOT NULL,
                  ${_trackUploadTable.columnCollectionID} INTEGER NOT NULL,
                  ${_trackUploadTable.columnEncryptedFileName} TEXT NOT NULL,
                  ${_trackUploadTable.columnEncryptedFileSize} INTEGER NOT NULL,
                  ${_trackUploadTable.columnEncryptedFileKey} TEXT NOT NULL,
                  ${_trackUploadTable.columnFileEncryptionNonce} TEXT NOT NULL,
                  ${_trackUploadTable.columnKeyEncryptionNonce} TEXT NOT NULL,
                  ${_trackUploadTable.columnObjectKey} TEXT NOT NULL,
                  ${_trackUploadTable.columnCompleteUrl} TEXT NOT NULL,
                  ${_trackUploadTable.columnStatus} TEXT DEFAULT '${MultipartStatus.pending.name}' NOT NULL,
                  ${_trackUploadTable.columnPartSize} INTEGER NOT NULL,
                  ${_trackUploadTable.columnLastAttemptedAt} INTEGER NOT NULL,
                  ${_trackUploadTable.columnCreatedAt} INTEGER DEFAULT CURRENT_TIMESTAMP NOT NULL
                )
                ''',
      '''
                CREATE TABLE IF NOT EXISTS ${_partsTable.table} (
                  ${_partsTable.columnObjectKey} TEXT NOT NULL REFERENCES ${_trackUploadTable.table}(${_trackUploadTable.columnObjectKey}) ON DELETE CASCADE,
                  ${_partsTable.columnPartNumber} INTEGER NOT NULL,
                  ${_partsTable.columnPartUrl} TEXT NOT NULL,
                  ${_partsTable.columnPartETag} TEXT,
                  ${_partsTable.columnPartStatus} TEXT NOT NULL,
                  PRIMARY KEY (${_partsTable.columnObjectKey}, ${_partsTable.columnPartNumber})
                )
                ''',
      '''
                CREATE TABLE IF NOT EXISTS ${_streamUploadErrorTable.table} (
                  ${_streamUploadErrorTable.columnUploadedFileID} INTEGER PRIMARY KEY,
                  ${_streamUploadErrorTable.columnErrorMessage} TEXT NOT NULL,
                  ${_streamUploadErrorTable.columnLastAttemptedAt} INTEGER NOT NULL,
                  ${_streamUploadErrorTable.columnCreatedAt} INTEGER DEFAULT CURRENT_TIMESTAMP NOT NULL
                )
                ''',
      '''
                CREATE TABLE IF NOT EXISTS ${_streamQueueTable.table} (
                  ${_streamQueueTable.columnUploadedFileID} INTEGER PRIMARY KEY,
                  ${_streamQueueTable.columnQueueType} TEXT NOT NULL,
                  ${_streamQueueTable.columnCreatedAt} INTEGER DEFAULT CURRENT_TIMESTAMP NOT NULL
                )
                ''',
    ];
  }

  Future<void> clearTable() async {
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM ${_uploadLocksTable.table}');
      await tx.execute('DELETE FROM ${_trackUploadTable.table}');
      await tx.execute('DELETE FROM ${_partsTable.table}');
      await tx.execute('DELETE FROM ${_streamQueueTable.table}');
    });
  }

  Future<bool> tryAcquireLock(String id, String owner, int time) async {
    final db = await database;
    try {
      await db.execute(
        '''
        INSERT OR FAIL INTO ${_uploadLocksTable.table} (
          ${_uploadLocksTable.columnID},
          ${_uploadLocksTable.columnOwner},
          ${_uploadLocksTable.columnTime}
        ) VALUES (?, ?, ?)
        ''',
        [id, owner, time],
      );
      return true;
    } on SqliteException catch (e) {
      if (e.extendedResultCode ==
              SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY ||
          e.extendedResultCode == SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE) {
        return false;
      }
      rethrow;
    }
  }

  Future<String> getLockData(String id) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM ${_uploadLocksTable.table}
      WHERE ${_uploadLocksTable.columnID} = ?
      ''',
      [id],
    );
    if (rows.isEmpty) {
      return "No lock found for $id";
    }
    final row = rows.first;
    final time =
        int.tryParse(row[_uploadLocksTable.columnTime].toString()) ?? 0;
    final owner = row[_uploadLocksTable.columnOwner] as String;
    final duration = DateTime.now().microsecondsSinceEpoch - time;
    return "Lock for $id acquired by $owner since ${Duration(microseconds: duration)}";
  }

  Future<bool> isLocked(String id, String owner) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT 1 FROM ${_uploadLocksTable.table}
      WHERE ${_uploadLocksTable.columnID} = ?
        AND ${_uploadLocksTable.columnOwner} = ?
      ''',
      [id, owner],
    );
    return rows.length == 1;
  }

  Future<int> releaseLock(String id, String owner) async {
    final db = await database;
    final rows = await db.execute(
      '''
      DELETE FROM ${_uploadLocksTable.table}
      WHERE ${_uploadLocksTable.columnID} = ?
        AND ${_uploadLocksTable.columnOwner} = ?
      RETURNING ${_uploadLocksTable.columnID}
      ''',
      [id, owner],
    );
    return rows.length;
  }

  Future<void> releaseLocksAcquiredByOwnerBefore(String owner, int time) async {
    final db = await database;
    await db.execute(
      '''
      DELETE FROM ${_uploadLocksTable.table}
      WHERE ${_uploadLocksTable.columnOwner} = ?
        AND ${_uploadLocksTable.columnTime} < ?
      ''',
      [owner, time],
    );
  }

  Future<void> releaseAllLocksAcquiredBefore(int time) async {
    final db = await database;
    await db.execute(
      '''
      DELETE FROM ${_uploadLocksTable.table}
      WHERE ${_uploadLocksTable.columnTime} < ?
      ''',
      [time],
    );
  }

  Future<({String encryptedFileKey, String fileNonce, String keyNonce})>
  getFileEncryptionData(
    String localId,
    String fileHash,
    int collectionID,
    String encryptedFileName,
  ) async {
    final db = await database;

    final rows = await db.getAll(
      '''
      SELECT * FROM ${_trackUploadTable.table}
      WHERE ${_trackUploadTable.columnLocalID} = ?
        AND ${_trackUploadTable.columnFileHash} = ?
        AND ${_trackUploadTable.columnCollectionID} = ?
      ''',
      [localId, fileHash, collectionID],
    );

    _validateResume(rows, localId, encryptedFileName);
    final row = rows.first;

    return (
      encryptedFileKey: row[_trackUploadTable.columnEncryptedFileKey] as String,
      fileNonce: row[_trackUploadTable.columnFileEncryptionNonce] as String,
      keyNonce: row[_trackUploadTable.columnKeyEncryptionNonce] as String,
    );
  }

  Future<void> updateLastAttempted(
    String localId,
    String fileHash,
    int collectionID,
  ) async {
    final db = await database;
    await db.execute(
      '''
      UPDATE ${_trackUploadTable.table}
      SET ${_trackUploadTable.columnLastAttemptedAt} = ?
      WHERE ${_trackUploadTable.columnLocalID} = ?
        AND ${_trackUploadTable.columnFileHash} = ?
        AND ${_trackUploadTable.columnCollectionID} = ?
      ''',
      [DateTime.now().millisecondsSinceEpoch, localId, fileHash, collectionID],
    );
  }

  Future<MultipartInfo> getCachedLinks(
    String localId,
    String fileHash,
    int collectionID,
    String encryptedFileName,
  ) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM ${_trackUploadTable.table}
      WHERE ${_trackUploadTable.columnLocalID} = ?
        AND ${_trackUploadTable.columnFileHash} = ?
        AND ${_trackUploadTable.columnCollectionID} = ?
      ''',
      [localId, fileHash, collectionID],
    );
    _validateResume(rows, localId, encryptedFileName);
    final row = rows.first;

    final objectKey = row[_trackUploadTable.columnObjectKey] as String;
    final encFileSize = row[_trackUploadTable.columnEncryptedFileSize] as int;
    final partsStatus = await db.getAll(
      '''
      SELECT * FROM ${_partsTable.table}
      WHERE ${_partsTable.columnObjectKey} = ?
      ''',
      [objectKey],
    );

    final List<bool> partUploadStatus = [];
    final List<String> partsURLs = List.generate(
      partsStatus.length,
      (index) => "",
    );
    final Map<int, String> partETags = {};

    for (final part in partsStatus) {
      final partNumber = part[_partsTable.columnPartNumber] as int;
      final partUrl = part[_partsTable.columnPartUrl] as String;
      final partStatus = part[_partsTable.columnPartStatus] as String;
      partsURLs[partNumber] = partUrl;
      if (part[_partsTable.columnPartETag] != null) {
        partETags[partNumber] = part[_partsTable.columnPartETag] as String;
      }
      partUploadStatus.add(partStatus == "uploaded");
    }
    final urls = MultipartUploadURLs(
      objectKey: objectKey,
      completeURL: row[_trackUploadTable.columnCompleteUrl] as String,
      partsURLs: partsURLs,
    );

    final String? fileMd5 = row[_trackUploadTable.columnFileMd5] as String?;
    List<String>? partMd5s;
    if (row[_trackUploadTable.columnPartMd5s] != null) {
      final partMd5sJson = row[_trackUploadTable.columnPartMd5s] as String;
      partMd5s = List<String>.from(jsonDecode(partMd5sJson));
    }

    return MultipartInfo(
      urls: urls,
      status: MultipartStatus.values.byName(
        row[_trackUploadTable.columnStatus] as String,
      ),
      partUploadStatus: partUploadStatus,
      partETags: partETags,
      encFileSize: encFileSize,
      partSize: row[_trackUploadTable.columnPartSize] as int,
      fileMd5: fileMd5,
      partMd5s: partMd5s,
    );
  }

  void _validateResume(
    Iterable<Map<String, Object?>> rows,
    String localId,
    String encryptedFileName,
  ) {
    if (rows.isEmpty) {
      throw MultiPartError("No cached links found for $localId");
    }
    if (rows.length > 1) {
      throw MultiPartError("Multiple entries found for localID: $localId");
    }
    if (encryptedFileName !=
        rows.first[_trackUploadTable.columnEncryptedFileName]) {
      throw MultiPartError(
        "Encrypted file name mismatch for localID: $localId",
      );
    }
  }

  Future<void> appendStreamEntry(
    int uploadedFileID,
    String errorMessage,
  ) async {
    final db = await database;

    await db.execute(
      '''
      INSERT OR REPLACE INTO ${_streamUploadErrorTable.table} (
        ${_streamUploadErrorTable.columnUploadedFileID},
        ${_streamUploadErrorTable.columnErrorMessage},
        ${_streamUploadErrorTable.columnLastAttemptedAt}
      ) VALUES (?, ?, ?)
      ''',
      [uploadedFileID, errorMessage, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> updateStreamStatus(
    int uploadedFileID,
    String errorMessage,
  ) async {
    final db = await database;
    await db.execute(
      '''
      UPDATE ${_streamUploadErrorTable.table}
      SET ${_streamUploadErrorTable.columnErrorMessage} = ?,
          ${_streamUploadErrorTable.columnLastAttemptedAt} = ?
      WHERE ${_streamUploadErrorTable.columnUploadedFileID} = ?
      ''',
      [errorMessage, DateTime.now().millisecondsSinceEpoch, uploadedFileID],
    );
  }

  Future<void> deleteStreamUploadErrorEntry(int uploadedFileID) async {
    final db = await database;
    await db.execute(
      '''
      DELETE FROM ${_streamUploadErrorTable.table}
      WHERE ${_streamUploadErrorTable.columnUploadedFileID} = ?
      ''',
      [uploadedFileID],
    );
  }

  Future<Map<int, String>> getStreamUploadError() {
    return database.then((db) async {
      final rows = await db.getAll('''
        SELECT ${_streamUploadErrorTable.columnUploadedFileID},
               ${_streamUploadErrorTable.columnErrorMessage}
        FROM ${_streamUploadErrorTable.table}
        ''');
      final map = <int, String>{};
      for (final row in rows) {
        map[row[_streamUploadErrorTable.columnUploadedFileID] as int] =
            row[_streamUploadErrorTable.columnErrorMessage] as String;
      }
      return map;
    });
  }

  Future<void> createTrackUploadsEntry(
    String localId,
    String fileHash,
    int collectionID,
    MultipartUploadURLs urls,
    String encryptedFileName,
    int fileSize,
    String fileKey,
    String fileNonce,
    String keyNonce, {
    required int partSize,
    String? fileMd5,
    List<String>? partMd5s,
  }) async {
    final db = await database;
    final objectKey = urls.objectKey;
    final partsURLs = urls.partsURLs;
    await db.writeTransaction((tx) async {
      await tx.execute(
        '''
        INSERT INTO ${_trackUploadTable.table} (
          ${_trackUploadTable.columnLocalID},
          ${_trackUploadTable.columnFileHash},
          ${_trackUploadTable.columnCollectionID},
          ${_trackUploadTable.columnObjectKey},
          ${_trackUploadTable.columnCompleteUrl},
          ${_trackUploadTable.columnEncryptedFileName},
          ${_trackUploadTable.columnEncryptedFileSize},
          ${_trackUploadTable.columnEncryptedFileKey},
          ${_trackUploadTable.columnFileEncryptionNonce},
          ${_trackUploadTable.columnKeyEncryptionNonce},
          ${_trackUploadTable.columnPartSize},
          ${_trackUploadTable.columnLastAttemptedAt},
          ${_trackUploadTable.columnFileMd5},
          ${_trackUploadTable.columnPartMd5s}
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          localId,
          fileHash,
          collectionID,
          objectKey,
          urls.completeURL,
          encryptedFileName,
          fileSize,
          fileKey,
          fileNonce,
          keyNonce,
          partSize,
          DateTime.now().millisecondsSinceEpoch,
          fileMd5,
          partMd5s == null ? null : jsonEncode(partMd5s),
        ],
      );

      if (partsURLs.isNotEmpty) {
        await tx.executeBatch(
          '''
          INSERT INTO ${_partsTable.table} (
            ${_partsTable.columnObjectKey},
            ${_partsTable.columnPartNumber},
            ${_partsTable.columnPartUrl},
            ${_partsTable.columnPartStatus}
          ) VALUES (?, ?, ?, ?)
          ''',
          [
            for (int i = 0; i < partsURLs.length; i++)
              [objectKey, i, partsURLs[i], PartStatus.pending.name],
          ],
        );
      }
    });
  }

  Future<void> updatePartStatus(
    String objectKey,
    int partNumber,
    String etag,
  ) async {
    final db = await database;
    await db.execute(
      '''
      UPDATE ${_partsTable.table}
      SET ${_partsTable.columnPartStatus} = ?,
          ${_partsTable.columnPartETag} = ?
      WHERE ${_partsTable.columnObjectKey} = ?
        AND ${_partsTable.columnPartNumber} = ?
      ''',
      [PartStatus.uploaded.name, etag, objectKey, partNumber],
    );
  }

  Future<void> updateTrackUploadStatus(
    String objectKey,
    MultipartStatus status,
  ) async {
    final db = await database;
    await db.execute(
      '''
      UPDATE ${_trackUploadTable.table}
      SET ${_trackUploadTable.columnStatus} = ?
      WHERE ${_trackUploadTable.columnObjectKey} = ?
      ''',
      [status.name, objectKey],
    );
  }

  Future<void> deleteMultipartTrack(String localId) async {
    final db = await database;
    await db.execute(
      '''
      DELETE FROM ${_trackUploadTable.table}
      WHERE ${_trackUploadTable.columnLocalID} = ?
      ''',
      [localId],
    );
  }

  Future<Map<String, int>> getFileNameToLastAttemptedAtMap() {
    return database.then((db) async {
      final rows = await db.getAll('''
        SELECT ${_trackUploadTable.columnEncryptedFileName},
               ${_trackUploadTable.columnLastAttemptedAt}
        FROM ${_trackUploadTable.table}
        ''');
      final map = <String, int>{};
      for (final row in rows) {
        map[row[_trackUploadTable.columnEncryptedFileName] as String] =
            row[_trackUploadTable.columnLastAttemptedAt] as int;
      }
      return map;
    });
  }

  Future<String?> getEncryptedFileName(
    String localId,
    String fileHash,
    int collectionID,
  ) {
    return database.then((db) async {
      final rows = await db.getAll(
        '''
        SELECT * FROM ${_trackUploadTable.table}
        WHERE ${_trackUploadTable.columnLocalID} = ?
          AND ${_trackUploadTable.columnFileHash} = ?
          AND ${_trackUploadTable.columnCollectionID} = ?
        ''',
        [localId, fileHash, collectionID],
      );
      if (rows.isEmpty) {
        return null;
      }
      if (rows.length > 1) {
        await db.execute(
          '''
          DELETE FROM ${_trackUploadTable.table}
          WHERE ${_trackUploadTable.columnLocalID} = ?
          ''',
          [localId],
        );
        throw MultiPartError("Multiple entries found for localID: $localId");
      }
      final row = rows.first;
      return row[_trackUploadTable.columnEncryptedFileName] as String;
    });
  }

  Future<void> addToStreamQueue(
    int uploadedFileID,
    String queueType, // 'create' or 'recreate'
  ) async {
    final db = await database;
    await db.execute(
      '''
      INSERT OR REPLACE INTO ${_streamQueueTable.table} (
        ${_streamQueueTable.columnUploadedFileID},
        ${_streamQueueTable.columnQueueType}
      ) VALUES (?, ?)
      ''',
      [uploadedFileID, queueType],
    );
  }

  Future<void> removeFromStreamQueue(int uploadedFileID) async {
    final db = await database;
    await db.execute(
      '''
      DELETE FROM ${_streamQueueTable.table}
      WHERE ${_streamQueueTable.columnUploadedFileID} = ?
      ''',
      [uploadedFileID],
    );
  }

  Future<Map<int, String>> getStreamQueue() async {
    final db = await database;
    final rows = await db.getAll('''
      SELECT ${_streamQueueTable.columnUploadedFileID},
             ${_streamQueueTable.columnQueueType}
      FROM ${_streamQueueTable.table}
      ''');
    final map = <int, String>{};
    for (final row in rows) {
      map[row[_streamQueueTable.columnUploadedFileID] as int] =
          row[_streamQueueTable.columnQueueType] as String;
    }
    return map;
  }

  Future<bool> isInStreamQueue(int uploadedFileID) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT 1 FROM ${_streamQueueTable.table}
      WHERE ${_streamQueueTable.columnUploadedFileID} = ?
      ''',
      [uploadedFileID],
    );
    return rows.isNotEmpty;
  }
}
