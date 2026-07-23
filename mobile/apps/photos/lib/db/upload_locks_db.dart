import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import "package:photos/core/errors.dart";
import "package:photos/module/upload/model/multipart.dart";
import 'package:sqflite/sqflite.dart';
import "package:sqflite_migration/sqflite_migration.dart";

class UploadLocksDB {
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

  final dbConfig = MigrationConfig(
    initializationScript: initializationScript,
    migrationScripts: migrationScripts,
  );

  UploadLocksDB._privateConstructor();
  static final UploadLocksDB instance = UploadLocksDB._privateConstructor();

  static Future<Database>? _dbFuture;
  Future<Database> get database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);

    return await openDatabaseWithMigration(path, dbConfig);
  }

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
    await db.delete(_uploadLocksTable.table);
    await db.delete(_trackUploadTable.table);
    await db.delete(_partsTable.table);
    await db.delete(_streamQueueTable.table);
  }

  Future<void> acquireLock(String id, String owner, int time) async {
    final db = await database;
    final row = <String, dynamic>{};
    row[_uploadLocksTable.columnID] = id;
    row[_uploadLocksTable.columnOwner] = owner;
    row[_uploadLocksTable.columnTime] = time;
    await db.insert(
      _uploadLocksTable.table,
      row,
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
  }

  Future<String> getLockData(String id) async {
    final db = await database;
    final rows = await db.query(
      _uploadLocksTable.table,
      where: '${_uploadLocksTable.columnID} = ?',
      whereArgs: [id],
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
    final rows = await db.query(
      _uploadLocksTable.table,
      where:
          '${_uploadLocksTable.columnID} = ? AND ${_uploadLocksTable.columnOwner} = ?',
      whereArgs: [id, owner],
    );
    return rows.length == 1;
  }

  Future<int> releaseLock(String id, String owner) async {
    final db = await database;
    return db.delete(
      _uploadLocksTable.table,
      where:
          '${_uploadLocksTable.columnID} = ? AND ${_uploadLocksTable.columnOwner} = ?',
      whereArgs: [id, owner],
    );
  }

  Future<int> releaseLocksAcquiredByOwnerBefore(String owner, int time) async {
    final db = await database;
    return db.delete(
      _uploadLocksTable.table,
      where:
          '${_uploadLocksTable.columnOwner} = ? AND ${_uploadLocksTable.columnTime} < ?',
      whereArgs: [owner, time],
    );
  }

  Future<int> releaseAllLocksAcquiredBefore(int time) async {
    final db = await database;
    return db.delete(
      _uploadLocksTable.table,
      where: '${_uploadLocksTable.columnTime} < ?',
      whereArgs: [time],
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

    final rows = await db.query(
      _trackUploadTable.table,
      where:
          '${_trackUploadTable.columnLocalID} = ?'
          ' AND ${_trackUploadTable.columnFileHash} = ?'
          ' AND ${_trackUploadTable.columnCollectionID} = ?',
      whereArgs: [localId, fileHash, collectionID],
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
    await db.update(
      _trackUploadTable.table,
      {
        _trackUploadTable.columnLastAttemptedAt:
            DateTime.now().millisecondsSinceEpoch,
      },
      where:
          '${_trackUploadTable.columnLocalID} = ?'
          ' AND ${_trackUploadTable.columnFileHash} = ?'
          ' AND ${_trackUploadTable.columnCollectionID} = ?',
      whereArgs: [localId, fileHash, collectionID],
    );
  }

  Future<MultipartInfo> getCachedLinks(
    String localId,
    String fileHash,
    int collectionID,
    String encryptedFileName,
  ) async {
    final db = await database;
    final rows = await db.query(
      _trackUploadTable.table,
      where:
          '${_trackUploadTable.columnLocalID} = ?'
          ' AND ${_trackUploadTable.columnFileHash} = ?'
          ' AND ${_trackUploadTable.columnCollectionID} = ?',
      whereArgs: [localId, fileHash, collectionID],
    );
    _validateResume(rows, localId, encryptedFileName);
    final row = rows.first;

    final objectKey = row[_trackUploadTable.columnObjectKey] as String;
    final encFileSize = row[_trackUploadTable.columnEncryptedFileSize] as int;
    final partsStatus = await db.query(
      _partsTable.table,
      where: '${_partsTable.columnObjectKey} = ?',
      whereArgs: [objectKey],
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

    // Retrieve MD5 data
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

  // validateResume checks if the cached links are valid for resuming upload
  void _validateResume(
    List<Map<String, Object?>> rows,
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

    await db.insert(_streamUploadErrorTable.table, {
      _streamUploadErrorTable.columnUploadedFileID: uploadedFileID,
      _streamUploadErrorTable.columnErrorMessage: errorMessage,
      _streamUploadErrorTable.columnLastAttemptedAt:
          DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateStreamStatus(
    int uploadedFileID,
    String errorMessage,
  ) async {
    final db = await database;
    await db.update(
      _streamUploadErrorTable.table,
      {
        _streamUploadErrorTable.columnErrorMessage: errorMessage,
        _streamUploadErrorTable.columnLastAttemptedAt:
            DateTime.now().millisecondsSinceEpoch,
      },
      where: '${_streamUploadErrorTable.columnUploadedFileID} = ?',
      whereArgs: [uploadedFileID],
    );
  }

  Future<int> deleteStreamUploadErrorEntry(int uploadedFileID) async {
    final db = await database;
    return await db.delete(
      _streamUploadErrorTable.table,
      where: '${_streamUploadErrorTable.columnUploadedFileID} = ?',
      whereArgs: [uploadedFileID],
    );
  }

  Future<Map<int, String>> getStreamUploadError() {
    return database.then((db) async {
      final rows = await db.query(
        _streamUploadErrorTable.table,
        columns: [
          _streamUploadErrorTable.columnUploadedFileID,
          _streamUploadErrorTable.columnErrorMessage,
        ],
      );
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

    await db.insert(_trackUploadTable.table, {
      _trackUploadTable.columnLocalID: localId,
      _trackUploadTable.columnFileHash: fileHash,
      _trackUploadTable.columnCollectionID: collectionID,
      _trackUploadTable.columnObjectKey: objectKey,
      _trackUploadTable.columnCompleteUrl: urls.completeURL,
      _trackUploadTable.columnEncryptedFileName: encryptedFileName,
      _trackUploadTable.columnEncryptedFileSize: fileSize,
      _trackUploadTable.columnEncryptedFileKey: fileKey,
      _trackUploadTable.columnFileEncryptionNonce: fileNonce,
      _trackUploadTable.columnKeyEncryptionNonce: keyNonce,
      _trackUploadTable.columnPartSize: partSize,
      _trackUploadTable.columnLastAttemptedAt:
          DateTime.now().millisecondsSinceEpoch,
      _trackUploadTable.columnFileMd5: ?fileMd5,
      if (partMd5s != null)
        _trackUploadTable.columnPartMd5s: jsonEncode(partMd5s),
    });

    final partsURLs = urls.partsURLs;
    final partsLength = partsURLs.length;

    for (int i = 0; i < partsLength; i++) {
      await db.insert(_partsTable.table, {
        _partsTable.columnObjectKey: objectKey,
        _partsTable.columnPartNumber: i,
        _partsTable.columnPartUrl: partsURLs[i],
        _partsTable.columnPartStatus: PartStatus.pending.name,
      });
    }
  }

  Future<void> updatePartStatus(
    String objectKey,
    int partNumber,
    String etag,
  ) async {
    final db = await database;
    await db.update(
      _partsTable.table,
      {
        _partsTable.columnPartStatus: PartStatus.uploaded.name,
        _partsTable.columnPartETag: etag,
      },
      where:
          '${_partsTable.columnObjectKey} = ? AND ${_partsTable.columnPartNumber} = ?',
      whereArgs: [objectKey, partNumber],
    );
  }

  Future<void> updateTrackUploadStatus(
    String objectKey,
    MultipartStatus status,
  ) async {
    final db = await database;
    await db.update(
      _trackUploadTable.table,
      {_trackUploadTable.columnStatus: status.name},
      where: '${_trackUploadTable.columnObjectKey} = ?',
      whereArgs: [objectKey],
    );
  }

  Future<int> deleteMultipartTrack(String localId) async {
    final db = await database;
    return await db.delete(
      _trackUploadTable.table,
      where: '${_trackUploadTable.columnLocalID} = ?',
      whereArgs: [localId],
    );
  }

  // getFileNameToLastAttemptedAtMap returns a map of encrypted file name to last attempted at time
  Future<Map<String, int>> getFileNameToLastAttemptedAtMap() {
    return database.then((db) async {
      final rows = await db.query(
        _trackUploadTable.table,
        columns: [
          _trackUploadTable.columnEncryptedFileName,
          _trackUploadTable.columnLastAttemptedAt,
        ],
      );
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
      final rows = await db.query(
        _trackUploadTable.table,
        where:
            '${_trackUploadTable.columnLocalID} = ?'
            ' AND ${_trackUploadTable.columnFileHash} = ?'
            ' AND ${_trackUploadTable.columnCollectionID} = ?',
        whereArgs: [localId, fileHash, collectionID],
      );
      if (rows.isEmpty) {
        return null;
      }
      if (rows.length > 1) {
        await db.delete(
          _trackUploadTable.table,
          where: '${_trackUploadTable.columnLocalID} = ?',
          whereArgs: [localId],
        );
        throw MultiPartError("Multiple entries found for localID: $localId");
      }
      final row = rows.first;
      return row[_trackUploadTable.columnEncryptedFileName] as String;
    });
  }

  // Stream Queue Management Methods
  Future<void> addToStreamQueue(
    int uploadedFileID,
    String queueType, // 'create' or 'recreate'
  ) async {
    final db = await database;
    await db.insert(_streamQueueTable.table, {
      _streamQueueTable.columnUploadedFileID: uploadedFileID,
      _streamQueueTable.columnQueueType: queueType,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFromStreamQueue(int uploadedFileID) async {
    final db = await database;
    await db.delete(
      _streamQueueTable.table,
      where: '${_streamQueueTable.columnUploadedFileID} = ?',
      whereArgs: [uploadedFileID],
    );
  }

  Future<Map<int, String>> getStreamQueue() async {
    final db = await database;
    final rows = await db.query(
      _streamQueueTable.table,
      columns: [
        _streamQueueTable.columnUploadedFileID,
        _streamQueueTable.columnQueueType,
      ],
    );
    final map = <int, String>{};
    for (final row in rows) {
      map[row[_streamQueueTable.columnUploadedFileID] as int] =
          row[_streamQueueTable.columnQueueType] as String;
    }
    return map;
  }

  Future<bool> isInStreamQueue(int uploadedFileID) async {
    final db = await database;
    final rows = await db.query(
      _streamQueueTable.table,
      where: '${_streamQueueTable.columnUploadedFileID} = ?',
      whereArgs: [uploadedFileID],
    );
    return rows.isNotEmpty;
  }
}
