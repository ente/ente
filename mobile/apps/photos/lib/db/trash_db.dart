import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/models/file/trash_file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:sqflite/sqflite.dart';

// Store only fields needed to query trash. Restore fetches the full file.
class TrashDB {
  static const _databaseName = "ente.trash.db";
  static const _databaseVersion = 2;
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

  Future _onCreate(Database db, int version) async {
    await db.execute('''
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
          $columnFileSize INTEGER DEFAULT NULL,
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
      ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnFileSize INTEGER DEFAULT NULL',
      );
    }
  }

  TrashDB._privateConstructor();

  static final TrashDB instance = TrashDB._privateConstructor();

  static Future<Database>? _dbFuture;

  Future<Database> get database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    _logger.info("DB path " + path);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.delete(tableName);
  }

  Future<int> count() async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableName'),
    );
    return count ?? 0;
  }

  Future<void> insertMultiple(List<EnteTrashFile> trashFiles) async {
    final startTime = DateTime.now();
    final db = await instance.database;
    var batch = db.batch();
    int batchCounter = 0;
    for (final trash in trashFiles) {
      if (batchCounter == 400) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCounter = 0;
      }
      batch.insert(
        tableName,
        _getRowForTrash(trash),
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
      "Batch insert of " +
          trashFiles.length.toString() +
          " took " +
          duration.inMilliseconds.toString() +
          "ms.",
    );
  }

  Future<int> delete(List<int> uploadedFileIDs) async {
    final db = await instance.database;
    return db.delete(
      tableName,
      where: '$columnUploadedFileID IN (${uploadedFileIDs.join(', ')})',
    );
  }

  Future<int> update(EnteTrashFile file) async {
    final db = await instance.database;
    return await db.update(
      tableName,
      _getRowForTrash(file),
      where: '$columnUploadedFileID = ?',
      whereArgs: [file.uploadedFileID],
    );
  }

  Future<FileLoadResult> getTrashedFiles(
    int startTime,
    int endTime, {
    int? limit,
    bool? asc,
  }) async {
    final db = await instance.database;
    final results = await db.query(
      tableName,
      where: '$columnCreationTime >= ? AND $columnCreationTime <= ?',
      whereArgs: [startTime, endTime],
      orderBy: '$columnTrashDeleteBy DESC',
      limit: limit,
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

  Map<String, dynamic> _getRowForTrash(EnteTrashFile trash) {
    final row = <String, dynamic>{};
    row[columnTrashUpdatedAt] = trash.updateAt;
    row[columnTrashDeleteBy] = trash.deleteBy;
    row[columnUploadedFileID] = trash.uploadedFileID;
    row[columnCollectionID] = trash.collectionID;
    row[columnOwnerID] = trash.ownerID;
    row[columnEncryptedKey] = trash.encryptedKey;
    row[columnKeyDecryptionNonce] = trash.keyDecryptionNonce;
    row[columnFileDecryptionHeader] = trash.fileDecryptionHeader;
    row[columnThumbnailDecryptionHeader] = trash.thumbnailDecryptionHeader;
    row[columnUpdationTime] = trash.updationTime;
    row[columnFileSize] = trash.fileSize;

    row[columnLocalID] = trash.localID;
    row[columnCreationTime] = trash.creationTime;
    row[columnFileMetadata] = jsonEncode(trash.metadata);

    row[columnMMdVersion] = trash.mMdVersion;
    row[columnMMdEncodedJson] = trash.mMdEncodedJson ?? '{}';

    row[columnPubMMdVersion] = trash.pubMmdVersion;
    row[columnPubMMdEncodedJson] = trash.pubMmdEncodedJson ?? '{}';
    return row;
  }
}
