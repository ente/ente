import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:photos/db/common/base.dart';
import 'package:photos/models/file/trash_file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:sqlite_async/sqlite_async.dart';

// Store only fields needed to query trash. Restore fetches the full file.
class TrashDB with SqlDbBase {
  static const _databaseName = "ente.trash.db";
  static final Logger _logger = Logger("TrashDB");
  static const tableName = 'trash';

  static const columnUploadedFileID = 'uploaded_file_id';
  static const columnCollectionID = 'collection_id';
  static const columnOwnerID = 'owner_id';
  static const columnTrashUpdatedAt = 't_updated_at';
  static const columnTrashDeleteBy = 't_delete_by';
  static const columnEncryptedKey = 'encrypted_key';
  static const columnKeyDecryptionNonce = 'key_decryption_nonce';
  static const columnFileDecryptionHeader = 'file_decryption_header';
  static const columnThumbnailDecryptionHeader = 'thumbnail_decryption_header';
  static const columnUpdationTime = 'updation_time';
  static const columnFileSize = 'file_size';

  static const columnCreationTime = 'creation_time';
  static const columnLocalID = 'local_id';

  static const columnFileMetadata = 'file_metadata';

  static const columnMMdEncodedJson = 'mmd_encoded_json';
  static const columnMMdVersion = 'mmd_ver';

  static const columnPubMMdEncodedJson = 'pub_mmd_encoded_json';
  static const columnPubMMdVersion = 'pub_mmd_ver';

  static const _migrationScripts = [
    '''
        CREATE TABLE $tableName (
          $columnUploadedFileID INTEGER PRIMARY KEY NOT NULL,
          $columnCollectionID INTEGER NOT NULL,
          $columnOwnerID INTEGER,
          $columnTrashUpdatedAt INTEGER NOT NULL,
          $columnTrashDeleteBy INTEGER NOT NULL,
          $columnEncryptedKey TEXT,
          $columnKeyDecryptionNonce TEXT,
          $columnFileDecryptionHeader TEXT,
          $columnThumbnailDecryptionHeader TEXT,
          $columnUpdationTime INTEGER,
          $columnLocalID TEXT,
          $columnCreationTime INTEGER NOT NULL,
          $columnFileMetadata TEXT DEFAULT '{}',
          $columnMMdEncodedJson TEXT DEFAULT '{}',
          $columnMMdVersion INTEGER DEFAULT 0,
          $columnPubMMdEncodedJson TEXT DEFAULT '{}',
          $columnPubMMdVersion INTEGER DEFAULT 0
        );
      CREATE INDEX IF NOT EXISTS creation_time_index ON $tableName($columnCreationTime); 
      CREATE INDEX IF NOT EXISTS delete_by_time_index ON $tableName($columnTrashDeleteBy);
      CREATE INDEX IF NOT EXISTS updated_at_time_index ON $tableName($columnTrashUpdatedAt);
      ''',
    'ALTER TABLE $tableName ADD COLUMN $columnFileSize INTEGER DEFAULT NULL',
  ];

  TrashDB._privateConstructor();

  static final TrashDB instance = TrashDB._privateConstructor();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(
      _databaseName,
      _migrationScripts,
      logPath: (path) => _logger.info("DB path " + path),
    ),
  );

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.execute('DELETE FROM $tableName');
  }

  Future<int> count() async {
    final db = await instance.database;
    final row = await db.get('SELECT COUNT(*) AS count FROM $tableName');
    return row['count'] as int;
  }

  Future<void> insertMultiple(List<EnteTrashFile> trashFiles) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    await _insertBatch(db, [
      for (final trash in trashFiles) _getParametersForTrash(trash),
    ]);
    final endTime = DateTime.now();
    final duration = Duration(
      microseconds:
          endTime.microsecondsSinceEpoch - startTime.microsecondsSinceEpoch,
    );
    _logger.info(
      "Batch insert of " +
          trashFiles.length.toString() +
          " took " +
          duration.inMilliseconds.toString() +
          "ms.",
    );
  }

  Future<int> delete(List<int> uploadedFileIDs) async {
    if (uploadedFileIDs.isEmpty) {
      return 0;
    }
    final db = await instance.database;
    var deletedRows = 0;
    for (var start = 0; start < uploadedFileIDs.length; start += 400) {
      final end = start + 400 < uploadedFileIDs.length
          ? start + 400
          : uploadedFileIDs.length;
      final ids = uploadedFileIDs.sublist(start, end);
      final rows = await db.execute('''
        DELETE FROM $tableName
        WHERE $columnUploadedFileID IN (${List.filled(ids.length, '?').join(', ')})
        RETURNING $columnUploadedFileID
        ''', ids);
      deletedRows += rows.length;
    }
    return deletedRows;
  }

  Future<void> update(EnteTrashFile file) async {
    final db = await instance.database;
    await db.execute(
      '''
      UPDATE $tableName SET
        $columnTrashUpdatedAt = ?, $columnTrashDeleteBy = ?,
        $columnCollectionID = ?, $columnOwnerID = ?,
        $columnEncryptedKey = ?, $columnKeyDecryptionNonce = ?,
        $columnFileDecryptionHeader = ?, $columnThumbnailDecryptionHeader = ?,
        $columnUpdationTime = ?, $columnFileSize = ?,
        $columnLocalID = ?, $columnCreationTime = ?,
        $columnFileMetadata = ?, $columnMMdVersion = ?,
        $columnMMdEncodedJson = ?, $columnPubMMdVersion = ?,
        $columnPubMMdEncodedJson = ?
      WHERE $columnUploadedFileID = ?
      ''',
      [
        file.updateAt,
        file.deleteBy,
        file.collectionID,
        file.ownerID,
        file.encryptedKey,
        file.keyDecryptionNonce,
        file.fileDecryptionHeader,
        file.thumbnailDecryptionHeader,
        file.updationTime,
        file.fileSize,
        file.localID,
        file.creationTime,
        jsonEncode(file.metadata),
        file.mMdVersion,
        file.mMdEncodedJson ?? '{}',
        file.pubMmdVersion,
        file.pubMmdEncodedJson ?? '{}',
        file.uploadedFileID,
      ],
    );
  }

  Future<FileLoadResult> getTrashedFiles(
    int startTime,
    int endTime, {
    int? limit,
    bool? asc,
  }) async {
    final db = await instance.database;
    final results = await db.getAll(
      '''
      SELECT * FROM $tableName
      WHERE $columnCreationTime >= ? AND $columnCreationTime <= ?
      ORDER BY $columnTrashDeleteBy DESC
      ${limit == null ? '' : 'LIMIT ?'}
      ''',
      [startTime, endTime, ?limit],
    );
    final files = results
        .map((row) => _getTrashFromRow(row))
        .toList(growable: true);
    return FileLoadResult(files, files.length == limit);
  }

  EnteTrashFile _getTrashFromRow(Map<String, dynamic> row) {
    final trashFile = EnteTrashFile();
    trashFile.updateAt = row[columnTrashUpdatedAt];
    trashFile.deleteBy = row[columnTrashDeleteBy];
    trashFile.uploadedFileID = row[columnUploadedFileID];
    // Trash rows need a synthetic generatedID for download and cache keys.
    trashFile.generatedID = -1 * trashFile.uploadedFileID!;
    trashFile.ownerID = row[columnOwnerID];
    trashFile.collectionID = row[columnCollectionID] == -1
        ? null
        : row[columnCollectionID];
    trashFile.encryptedKey = row[columnEncryptedKey];
    trashFile.keyDecryptionNonce = row[columnKeyDecryptionNonce];
    trashFile.fileDecryptionHeader = row[columnFileDecryptionHeader];
    trashFile.thumbnailDecryptionHeader = row[columnThumbnailDecryptionHeader];
    trashFile.updationTime = row[columnUpdationTime] ?? 0;
    trashFile.creationTime = row[columnCreationTime];
    final fileMetadata = row[columnFileMetadata] ?? '{}';
    trashFile.applyMetadata(jsonDecode(fileMetadata));
    trashFile.localID = row[columnLocalID];
    trashFile.fileSize = row[columnFileSize];

    trashFile.mMdVersion = row[columnMMdVersion] ?? 0;
    trashFile.mMdEncodedJson = row[columnMMdEncodedJson] ?? '{}';

    trashFile.pubMmdVersion = row[columnPubMMdVersion] ?? 0;
    trashFile.pubMmdEncodedJson = row[columnPubMMdEncodedJson] ?? '{}';

    if (trashFile.pubMagicMetadata != null &&
        trashFile.pubMagicMetadata!.editedTime != null) {
      // override existing creationTime to avoid re-writing all queries related
      // to loading the gallery
      trashFile.creationTime = trashFile.pubMagicMetadata!.editedTime!;
    }

    return trashFile;
  }

  Future<void> _insertBatch(
    SqliteDatabase db,
    List<List<Object?>> parameterSets,
  ) async {
    if (parameterSets.isEmpty) return;
    await db.executeBatch('''
      INSERT OR REPLACE INTO $tableName (
        $columnTrashUpdatedAt, $columnTrashDeleteBy, $columnUploadedFileID,
        $columnCollectionID, $columnOwnerID, $columnEncryptedKey,
        $columnKeyDecryptionNonce, $columnFileDecryptionHeader,
        $columnThumbnailDecryptionHeader, $columnUpdationTime, $columnFileSize,
        $columnLocalID, $columnCreationTime, $columnFileMetadata,
        $columnMMdVersion, $columnMMdEncodedJson, $columnPubMMdVersion,
        $columnPubMMdEncodedJson
      ) VALUES (${SqlDbBase.getParams(18)})
      ''', parameterSets);
  }

  List<Object?> _getParametersForTrash(EnteTrashFile trash) {
    return [
      trash.updateAt,
      trash.deleteBy,
      trash.uploadedFileID,
      trash.collectionID,
      trash.ownerID,
      trash.encryptedKey,
      trash.keyDecryptionNonce,
      trash.fileDecryptionHeader,
      trash.thumbnailDecryptionHeader,
      trash.updationTime,
      trash.fileSize,
      trash.localID,
      trash.creationTime,
      jsonEncode(trash.metadata),
      trash.mMdVersion,
      trash.mMdEncodedJson ?? '{}',
      trash.pubMmdVersion,
      trash.pubMmdEncodedJson ?? '{}',
    ];
  }
}
