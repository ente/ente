import "dart:async";
import "dart:io";
import "dart:math";

import "package:collection/collection.dart";
import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import "package:photos/db/common/base.dart";
import "package:photos/db/common/conflict_algo.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/freeable_space_info.dart';
import 'package:photos/models/location/location.dart';
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/services/filter/db_filters.dart";
import 'package:sqlite_async/sqlite_async.dart';

class FilesDB with SqlDbBase {
  /*
  Note: columnUploadedFileID and columnCollectionID have to be compared against
  both NULL and -1 because older clients might have entries where the DEFAULT
  was unset, and a migration script to set the DEFAULT would break in case of
  duplicate entries for un-uploaded files that were created due to a collision
  in background and foreground syncs.
  */
  static const _databaseName = "ente.files.db";

  static const int _maxMaterializationPageSize = 2000;

  static final Logger _logger = Logger("FilesDB");

  static const filesTable = 'files';
  static const tempTable = 'temp_files';
  static const deviceFolderEnteMoveQueueTable = 'device_folder_ente_move_queue';

  static const columnGeneratedID = '_id';
  static const columnUploadedFileID = 'uploaded_file_id';
  static const columnOwnerID = 'owner_id';
  static const columnCollectionID = 'collection_id';
  static const columnLocalID = 'local_id';
  static const columnTitle = 'title';
  static const columnDeviceFolder = 'device_folder';
  static const columnLatitude = 'latitude';
  static const columnLongitude = 'longitude';
  static const columnFileType = 'file_type';
  static const columnFileSubType = 'file_sub_type';
  static const columnDuration = 'duration';
  static const columnExif = 'exif';
  static const columnHash = 'hash';
  static const columnMetadataVersion = 'metadata_version';
  static const columnIsDeleted = 'is_deleted';
  static const columnCreationTime = 'creation_time';
  static const columnModificationTime = 'modification_time';
  static const columnUpdationTime = 'updation_time';
  static const columnAddedTime = 'added_time';
  static const columnEncryptedKey = 'encrypted_key';
  static const columnKeyDecryptionNonce = 'key_decryption_nonce';
  static const columnFileDecryptionHeader = 'file_decryption_header';
  static const columnThumbnailDecryptionHeader = 'thumbnail_decryption_header';
  static const columnMetadataDecryptionHeader = 'metadata_decryption_header';
  static const columnFileSize = 'file_size';
  // MMD is magic metadata.
  static const columnMMdEncodedJson = 'mmd_encoded_json';
  static const columnMMdVersion = 'mmd_ver';

  static const columnPubMMdEncodedJson = 'pub_mmd_encoded_json';
  static const columnPubMMdVersion = 'pub_mmd_ver';

  // JSON fields become columns only when needed for queries.
  static const columnMMdVisibility = 'mmd_visibility';

  // When columns change, also update _columnNames,
  // _generateColumnsAndPlaceholdersForInsert, and
  // _generateUpdateAssignmentsWithPlaceholders.
  static final _migrationScripts = [
    ...createTable(filesTable),
    ...alterDeviceFolderToAllowNULL(),
    ...alterTimestampColumnTypes(),
    ...addIndices(),
    ...addMetadataColumns(),
    ...addMagicMetadataColumns(),
    ...addUniqueConstraintOnCollectionFiles(),
    ...addPubMagicMetadataColumns(),
    ...createOnDeviceFilesAndPathCollection(),
    ...addFileSizeColumn(),
    ...updateIndexes(),
    ...createEntityDataTable(),
    ...addAddedTime(),
    ...addFileMaterializationOrderIndex(),
    ...createDeviceFolderEnteMoveQueue(),
    ...addDeviceFolderEnteMoveQueueState(),
    ...upgradeDeviceFolderEnteMoveQueueIdentity(),
  ];

  static const List<String> _columnNames = [
    columnGeneratedID,
    columnLocalID,
    columnUploadedFileID,
    columnOwnerID,
    columnCollectionID,
    columnTitle,
    columnDeviceFolder,
    columnLatitude,
    columnLongitude,
    columnFileType,
    columnModificationTime,
    columnEncryptedKey,
    columnKeyDecryptionNonce,
    columnFileDecryptionHeader,
    columnThumbnailDecryptionHeader,
    columnMetadataDecryptionHeader,
    columnCreationTime,
    columnUpdationTime,
    columnFileSubType,
    columnDuration,
    columnExif,
    columnHash,
    columnMetadataVersion,
    columnMMdEncodedJson,
    columnMMdVersion,
    columnMMdVisibility,
    columnPubMMdEncodedJson,
    columnPubMMdVersion,
    columnFileSize,
    columnAddedTime,
  ];

  FilesDB._privateConstructor();

  static final FilesDB instance = FilesDB._privateConstructor();

  Future<SqliteDatabase> get sqliteAsyncDB => getOrOpenDatabase(
    () => openMigratedDatabase(
      _databaseName,
      _migrationScripts,
      maxReaders: 5,
      logPath: (path) => _logger.info("DB path " + path),
    ),
  );

  static List<String> createTable(String tableName) {
    return [
      '''
        CREATE TABLE $tableName (
          $columnGeneratedID INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          $columnLocalID TEXT,
          $columnUploadedFileID INTEGER DEFAULT -1,
          $columnOwnerID INTEGER,
          $columnCollectionID INTEGER DEFAULT -1,
          $columnTitle TEXT NOT NULL,
          $columnDeviceFolder TEXT,
          $columnLatitude REAL,
          $columnLongitude REAL,
          $columnFileType INTEGER,
          $columnModificationTime TEXT NOT NULL,
          $columnEncryptedKey TEXT,
          $columnKeyDecryptionNonce TEXT,
          $columnFileDecryptionHeader TEXT,
          $columnThumbnailDecryptionHeader TEXT,
          $columnMetadataDecryptionHeader TEXT,
          $columnIsDeleted INTEGER DEFAULT 0,
          $columnCreationTime TEXT NOT NULL,
          $columnUpdationTime TEXT,
          UNIQUE($columnLocalID, $columnUploadedFileID, $columnCollectionID)
        );
      ''',
    ];
  }

  static List<String> addIndices() {
    return [
      '''
        CREATE INDEX IF NOT EXISTS collection_id_index ON $filesTable($columnCollectionID);
      ''',
      '''
        CREATE INDEX IF NOT EXISTS device_folder_index ON $filesTable($columnDeviceFolder);
      ''',
      '''
        CREATE INDEX IF NOT EXISTS creation_time_index ON $filesTable($columnCreationTime);
      ''',
      '''
        CREATE INDEX IF NOT EXISTS updation_time_index ON $filesTable($columnUpdationTime);
      ''',
    ];
  }

  static List<String> alterDeviceFolderToAllowNULL() {
    return [
      ...createTable(tempTable),
      '''
        INSERT INTO $tempTable
        SELECT *
        FROM $filesTable;

        DROP TABLE $filesTable;
        
        ALTER TABLE $tempTable 
        RENAME TO $filesTable;
    ''',
    ];
  }

  static List<String> alterTimestampColumnTypes() {
    return [
      '''
        DROP TABLE IF EXISTS $tempTable;
      ''',
      '''
        CREATE TABLE $tempTable (
          $columnGeneratedID INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          $columnLocalID TEXT,
          $columnUploadedFileID INTEGER DEFAULT -1,
          $columnOwnerID INTEGER,
          $columnCollectionID INTEGER DEFAULT -1,
          $columnTitle TEXT NOT NULL,
          $columnDeviceFolder TEXT,
          $columnLatitude REAL,
          $columnLongitude REAL,
          $columnFileType INTEGER,
          $columnModificationTime INTEGER NOT NULL,
          $columnEncryptedKey TEXT,
          $columnKeyDecryptionNonce TEXT,
          $columnFileDecryptionHeader TEXT,
          $columnThumbnailDecryptionHeader TEXT,
          $columnMetadataDecryptionHeader TEXT,
          $columnCreationTime INTEGER NOT NULL,
          $columnUpdationTime INTEGER,
          UNIQUE($columnLocalID, $columnUploadedFileID, $columnCollectionID)
        );
      ''',
      '''
        INSERT INTO $tempTable
        SELECT 
          $columnGeneratedID,
          $columnLocalID,
          $columnUploadedFileID,
          $columnOwnerID,
          $columnCollectionID,
          $columnTitle,
          $columnDeviceFolder,
          $columnLatitude,
          $columnLongitude,
          $columnFileType,
          CAST($columnModificationTime AS INTEGER),
          $columnEncryptedKey,
          $columnKeyDecryptionNonce,
          $columnFileDecryptionHeader,
          $columnThumbnailDecryptionHeader,
          $columnMetadataDecryptionHeader,
          CAST($columnCreationTime AS INTEGER),
          CAST($columnUpdationTime AS INTEGER)
        FROM $filesTable;
      ''',
      '''
        DROP TABLE $filesTable;
      ''',
      '''
        ALTER TABLE $tempTable 
        RENAME TO $filesTable;
      ''',
    ];
  }

  static List<String> addMetadataColumns() {
    return [
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnFileSubType INTEGER;
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnDuration INTEGER;
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnExif TEXT;
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnHash TEXT;
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnMetadataVersion INTEGER;
      ''',
    ];
  }

  static List<String> addMagicMetadataColumns() {
    return [
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnMMdEncodedJson TEXT DEFAULT '{}';
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnMMdVersion INTEGER DEFAULT 0;
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnMMdVisibility INTEGER DEFAULT $visibleVisibility;
      ''',
    ];
  }

  static List<String> addUniqueConstraintOnCollectionFiles() {
    return [
      '''
      DELETE from $filesTable where $columnCollectionID || '-' || $columnUploadedFileID IN 
      (SELECT $columnCollectionID || '-' || $columnUploadedFileID from $filesTable WHERE 
      $columnCollectionID is not NULL AND $columnUploadedFileID is NOT NULL 
      AND $columnCollectionID != -1 AND $columnUploadedFileID  != -1 
      GROUP BY ($columnCollectionID || '-' || $columnUploadedFileID) HAVING count(*) > 1) 
      AND  ($columnCollectionID || '-' ||  $columnUploadedFileID || '-' || $columnGeneratedID) NOT IN 
      (SELECT $columnCollectionID || '-' ||  $columnUploadedFileID || '-' || max($columnGeneratedID) 
      from $filesTable WHERE 
      $columnCollectionID is not NULL AND $columnUploadedFileID is NOT NULL 
      AND $columnCollectionID != -1 AND $columnUploadedFileID  != -1 GROUP BY 
      ($columnCollectionID || '-' || $columnUploadedFileID) HAVING count(*) > 1);
      ''',
      '''
      CREATE UNIQUE INDEX IF NOT EXISTS cid_uid ON $filesTable ($columnCollectionID, $columnUploadedFileID)
      WHERE $columnCollectionID is not NULL AND $columnUploadedFileID is not NULL
      AND $columnCollectionID != -1 AND $columnUploadedFileID  != -1;
      ''',
    ];
  }

  static List<String> addPubMagicMetadataColumns() {
    return [
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnPubMMdEncodedJson TEXT DEFAULT '{}';
      ''',
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnPubMMdVersion INTEGER DEFAULT 0;
      ''',
    ];
  }

  static List<String> createOnDeviceFilesAndPathCollection() {
    return [
      '''
        CREATE TABLE IF NOT EXISTS device_files (
          id TEXT NOT NULL,
          path_id TEXT NOT NULL,
          UNIQUE(id, path_id)
       );
       ''',
      '''
       CREATE TABLE IF NOT EXISTS device_collections (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT,
          modified_at INTEGER NOT NULL DEFAULT 0,
          should_backup INTEGER NOT NULL DEFAULT 0,
          count INTEGER NOT NULL DEFAULT 0,
          collection_id INTEGER DEFAULT -1,
          upload_strategy INTEGER DEFAULT 0,
          cover_id TEXT
      );
      ''',
      '''
      CREATE INDEX IF NOT EXISTS df_id_idx ON device_files (id);
      ''',
      '''
      CREATE INDEX IF NOT EXISTS df_path_id_idx ON device_files (path_id);
      ''',
    ];
  }

  static List<String> createEntityDataTable() {
    return [
      '''
       CREATE TABLE IF NOT EXISTS entities (
          id TEXT PRIMARY KEY NOT NULL,
          type TEXT NOT NULL,
          ownerID INTEGER NOT NULL,
          data TEXT NOT NULL DEFAULT '{}',
          updatedAt INTEGER NOT NULL
      );
      ''',
    ];
  }

  static List<String> createDeviceFolderEnteMoveQueue() {
    return [
      '''
      CREATE TABLE IF NOT EXISTS $deviceFolderEnteMoveQueueTable (
        owner_id INTEGER NOT NULL,
        source_path_id TEXT NOT NULL,
        destination_path_id TEXT NOT NULL,
        source_collection_id INTEGER NOT NULL,
        local_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(owner_id, source_path_id, destination_path_id, source_collection_id, local_id)
      );
      ''',
      '''
      CREATE INDEX IF NOT EXISTS dfemq_owner_idx
      ON $deviceFolderEnteMoveQueueTable (owner_id, created_at);
      ''',
    ];
  }

  static List<String> addDeviceFolderEnteMoveQueueState() {
    return [
      '''
      ALTER TABLE $deviceFolderEnteMoveQueueTable
      ADD COLUMN destination_collection_id INTEGER;
      ''',
      '''
      ALTER TABLE $deviceFolderEnteMoveQueueTable
      ADD COLUMN state TEXT NOT NULL DEFAULT 'ready';
      ''',
      '''
      CREATE INDEX IF NOT EXISTS dfemq_owner_state_idx
      ON $deviceFolderEnteMoveQueueTable (owner_id, state, created_at);
      ''',
      '''
      DELETE FROM $deviceFolderEnteMoveQueueTable
      WHERE destination_collection_id IS NULL;
      ''',
    ];
  }

  static List<String> upgradeDeviceFolderEnteMoveQueueIdentity() {
    const replacementTable = '${deviceFolderEnteMoveQueueTable}_replacement';
    return [
      '''
      CREATE TABLE $replacementTable (
        owner_id INTEGER NOT NULL,
        source_path_id TEXT NOT NULL,
        destination_path_id TEXT NOT NULL,
        source_collection_id INTEGER NOT NULL,
        destination_collection_id INTEGER NOT NULL,
        local_id TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'ready',
        created_at INTEGER NOT NULL,
        UNIQUE(
          owner_id, source_path_id, destination_path_id,
          source_collection_id, destination_collection_id, local_id
        )
      );
      ''',
      '''
      INSERT INTO $replacementTable (
        owner_id, source_path_id, destination_path_id,
        source_collection_id, destination_collection_id, local_id,
        state, created_at
      )
      SELECT
        owner_id, source_path_id, destination_path_id,
        source_collection_id, destination_collection_id, local_id,
        state, created_at
      FROM $deviceFolderEnteMoveQueueTable;
      ''',
      '''
      DROP TABLE $deviceFolderEnteMoveQueueTable;
      ''',
      '''
      ALTER TABLE $replacementTable RENAME TO $deviceFolderEnteMoveQueueTable;
      ''',
      '''
      CREATE INDEX dfemq_owner_idx
      ON $deviceFolderEnteMoveQueueTable (owner_id, created_at);
      ''',
      '''
      CREATE INDEX dfemq_owner_state_idx
      ON $deviceFolderEnteMoveQueueTable (owner_id, state, created_at);
      ''',
    ];
  }

  static List<String> addFileSizeColumn() {
    return [
      '''
      ALTER TABLE $filesTable ADD COLUMN $columnFileSize INTEGER;
      ''',
    ];
  }

  static List<String> updateIndexes() {
    return [
      '''
      DROP INDEX IF EXISTS device_folder_index;
      ''',
      '''
      CREATE INDEX IF NOT EXISTS file_hash_index ON $filesTable($columnHash);
      ''',
    ];
  }

  static List<String> addAddedTime() {
    return [
      '''
        ALTER TABLE $filesTable ADD COLUMN $columnAddedTime INTEGER NOT NULL DEFAULT -1;
      ''',
      '''
        CREATE INDEX IF NOT EXISTS added_time_index ON $filesTable($columnAddedTime);
      ''',
    ];
  }

  static List<String> addFileMaterializationOrderIndex() {
    return [
      '''
        CREATE INDEX IF NOT EXISTS file_materialization_order_index
        ON $filesTable(
          $columnCreationTime,
          $columnModificationTime,
          $columnGeneratedID
        );
      ''',
    ];
  }

  Future<void> clearTable() async {
    final db = await instance.sqliteAsyncDB;
    await db.execute('DELETE FROM $filesTable');
    await db.execute('DELETE FROM device_files');
    await db.execute('DELETE FROM device_collections');
    await db.execute('DELETE FROM entities');
  }

  Future<void> deleteDB() async {
    if (kDebugMode) {
      debugPrint("Deleting files db");
      final Directory documentsDirectory =
          await getApplicationDocumentsDirectory();
      final String path = join(documentsDirectory.path, _databaseName);
      File(path).deleteSync(recursive: true);
      resetDatabaseFuture();
    }
  }

  Future<void> insertMultiple(
    List<EnteFile> files, {
    SqliteAsyncConflictAlgorithm conflictAlgorithm =
        SqliteAsyncConflictAlgorithm.replace,
  }) async {
    if (files.isEmpty) return;

    final startTime = DateTime.now();
    final db = await sqliteAsyncDB;

    final withIdParams = <List<Object?>>[];
    const withIdColumnNames = _columnNames;
    final withoutIdParams = <List<Object?>>[];
    final withoutIdColumns = _columnNames
        .where((column) => column != columnGeneratedID)
        .toList();

    for (final file in files) {
      if (file.generatedID == null) {
        withoutIdParams.add(_getParameterSetForFile(file));

        if (withoutIdParams.length == 400) {
          await _insertBatch(
            conflictAlgorithm,
            withoutIdColumns,
            db,
            withoutIdParams,
          );
          withoutIdParams.clear();
        }
      } else {
        withIdParams.add(_getParameterSetForFile(file));
        if (withIdParams.length == 400) {
          await _insertBatch(
            conflictAlgorithm,
            withIdColumnNames,
            db,
            withIdParams,
          );
          withIdParams.clear();
        }
      }
    }

    if (withIdParams.isNotEmpty) {
      await _insertBatch(
        conflictAlgorithm,
        withIdColumnNames,
        db,
        withIdParams,
      );
    }

    if (withoutIdParams.isNotEmpty) {
      await _insertBatch(
        conflictAlgorithm,
        withoutIdColumns,
        db,
        withoutIdParams,
      );
    }
    final duration = DateTime.now().difference(startTime);
    _logger.info(
      "Batch insert of ${files.length} took ${duration.inMilliseconds}ms.",
    );
  }

  Future<void> insert(EnteFile file) async {
    _logger.info("Inserting $file");
    final db = await instance.sqliteAsyncDB;
    final columnsAndPlaceholders = _generateColumnsAndPlaceholdersForInsert(
      fileGenId: file.generatedID,
    );
    final values = _getParameterSetForFile(file);

    await db.execute(
      'INSERT OR REPLACE INTO $filesTable (${columnsAndPlaceholders["columns"]}) VALUES (${columnsAndPlaceholders["placeholders"]})',
      values,
    );
  }

  Future<int> insertAndGetId(EnteFile file) async {
    _logger.info("Inserting $file");
    final db = await instance.sqliteAsyncDB;
    final columnsAndPlaceholders = _generateColumnsAndPlaceholdersForInsert(
      fileGenId: file.generatedID,
    );
    final values = _getParameterSetForFile(file);
    return await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT OR REPLACE INTO $filesTable (${columnsAndPlaceholders["columns"]}) VALUES (${columnsAndPlaceholders["placeholders"]})',
        values,
      );
      final result = await tx.get('SELECT last_insert_rowid()');
      return result["last_insert_rowid()"] as int;
    });
  }

  Future<EnteFile?> getFile(int generatedID) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnGeneratedID = ?',
      [generatedID],
    );
    if (results.isEmpty) {
      return null;
    }
    return convertToFiles(results)[0];
  }

  Future<EnteFile?> getUploadedFile(int uploadedID, int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnUploadedFileID = ? AND $columnCollectionID = ?',
      [uploadedID, collectionID],
    );
    if (results.isEmpty) {
      return null;
    }
    return convertToFiles(results)[0];
  }

  Future<EnteFile?> getAnyUploadedFile(int uploadedID) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnUploadedFileID = ?',
      [uploadedID],
    );
    if (results.isEmpty) {
      return null;
    }
    return convertToFiles(results)[0];
  }

  Future<Set<int>> getUploadedFileIDs(int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT $columnUploadedFileID FROM $filesTable'
      ' WHERE $columnCollectionID = ? AND ($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS NOT -1)',
      [collectionID],
    );
    final ids = <int>{};
    for (final result in results) {
      ids.add(result[columnUploadedFileID] as int);
    }
    return ids;
  }

  Future<Map<int, Set<int>>> getExistingFileIDsByCollection(
    Set<(int fileID, int collectionID)> pairs,
  ) async {
    if (pairs.isEmpty) return {};

    final db = await instance.sqliteAsyncDB;
    final existing = <int, Set<int>>{};
    final fileIDsByCollection = <int, Set<int>>{};
    for (final (fileID, collectionID) in pairs) {
      fileIDsByCollection.putIfAbsent(collectionID, () => {}).add(fileID);
    }

    // Keep placeholders under common SQLite variable limits.
    const maxInParams = 900;

    for (final entry in fileIDsByCollection.entries) {
      final collectionID = entry.key;
      final fileIDs = entry.value.toList(growable: false);
      for (var i = 0; i < fileIDs.length; i += maxInParams) {
        final end = (i + maxInParams > fileIDs.length)
            ? fileIDs.length
            : i + maxInParams;
        final chunk = fileIDs.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final results = await db.getAll(
          'SELECT $columnUploadedFileID FROM $filesTable '
          'WHERE $columnCollectionID = ? '
          'AND $columnUploadedFileID IN ($placeholders)',
          [collectionID, ...chunk],
        );
        for (final row in results) {
          final fileID = row[columnUploadedFileID] as int;
          existing.putIfAbsent(collectionID, () => {}).add(fileID);
        }
      }
    }

    return existing;
  }

  Future<(Set<int>, Map<String, int>)> getUploadAndHash(
    int collectionID,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT $columnUploadedFileID, $columnHash FROM $filesTable'
      ' WHERE $columnCollectionID = ? AND ($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS NOT -1)',
      [collectionID],
    );
    final ids = <int>{};
    final hash = <String, int>{};
    for (final result in results) {
      ids.add(result[columnUploadedFileID] as int);
      if (result[columnHash] != null) {
        hash[result[columnHash] as String] =
            result[columnUploadedFileID] as int;
      }
    }
    return (ids, hash);
  }

  Future<FreeableFileIDs> getFreeableFileIDs({
    required int ownerID,
    Set<String> excludeLocalIDs = const {},
  }) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT $columnLocalID, $columnUploadedFileID, $columnFileSize FROM $filesTable'
      ' WHERE $columnLocalID IS NOT NULL AND ($columnOwnerID IS NULL OR $columnOwnerID = ?) '
      'AND ($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS NOT -1) '
      'AND $columnUpdationTime IS NOT NULL',
      [ownerID],
    );
    final Set<String> localIDs = <String>{};
    final Set<int> uploadedIDs = <int>{};
    int localSize = 0;
    for (final result in results) {
      final String localID = result[columnLocalID] as String;
      if (excludeLocalIDs.contains(localID)) continue;
      final int? fileSize = result[columnFileSize] as int?;
      if (!localIDs.contains(localID) && fileSize != null) {
        localSize += fileSize;
      }
      localIDs.add(localID);
      uploadedIDs.add(result[columnUploadedFileID] as int);
    }
    return FreeableFileIDs(localIDs.toList(), uploadedIDs.toList(), localSize);
  }

  Future<FileLoadResult> getAllPendingOrUploadedFiles(
    int startTime,
    int endTime,
    int ownerID, {
    int? limit,
    bool? asc,
    int visibility = visibleVisibility,
    DBFilterOptions? filterOptions,
    bool applyOwnerCheck = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[startTime, endTime];
    if (applyOwnerCheck) {
      where.add(
        '$columnCreationTime >= ? AND $columnCreationTime <= ? '
        'AND ($columnOwnerID IS NULL OR $columnOwnerID = ?) '
        'AND ($columnCollectionID IS NOT NULL AND $columnCollectionID IS NOT -1)',
      );
      args.add(ownerID);
    } else {
      where.add(
        '$columnCreationTime >= ? AND $columnCreationTime <= ? '
        'AND ($columnCollectionID IS NOT NULL AND $columnCollectionID IS NOT -1)',
      );
    }

    where.add('$columnMMdVisibility = ?');
    args.add(visibility);

    if (filterOptions?.ignoreSharedItems ?? false) {
      where.add('($columnOwnerID IS NULL OR $columnOwnerID = ?)');
      args.add(ownerID);
    }

    return _loadMaterializedFiles(
      whereClause: where.join(' AND '),
      whereArguments: args,
      order: asc ?? false
          ? _MaterializedFileOrder.creationThenModificationThenIdAscending
          : _MaterializedFileOrder.creationThenModificationThenIdDescending,
      limit: limit,
      filterOptions: filterOptions,
      convertPage: _convertPageOnCallerIsolate,
    );
  }

  Future<FileLoadResult> getAllLocalAndUploadedFiles(
    int startTime,
    int endTime,
    int ownerID, {
    int? limit,
    bool? asc,
    required DBFilterOptions filterOptions,
  }) async {
    final args = <Object?>[startTime, endTime, visibleVisibility];
    final where = <String>[
      '$columnCreationTime >= ? AND $columnCreationTime <= ?',
      '($columnMMdVisibility IS NULL OR $columnMMdVisibility = ?)',
      '($columnLocalID IS NOT NULL OR '
          '($columnCollectionID IS NOT NULL AND $columnCollectionID IS NOT -1))',
    ];

    if (filterOptions.ignoreSharedItems) {
      where.add('($columnOwnerID IS NULL OR $columnOwnerID = ?)');
      args.add(ownerID);
    }

    return _loadMaterializedFiles(
      whereClause: where.join(' AND '),
      whereArguments: args,
      order: asc ?? false
          ? _MaterializedFileOrder.creationThenModificationThenIdAscending
          : _MaterializedFileOrder.creationThenModificationThenIdDescending,
      limit: limit,
      filterOptions: filterOptions,
      convertPage: _convertPageOnCallerIsolate,
    );
  }

  List<EnteFile> deduplicateByLocalID(List<EnteFile> files) {
    final localIDs = <String>{};
    final List<EnteFile> deduplicatedFiles = [];
    for (final file in files) {
      final id = file.localID;
      if (id == null) {
        continue;
      }
      if (localIDs.contains(id)) {
        continue;
      }
      localIDs.add(id);
      deduplicatedFiles.add(file);
    }
    return deduplicatedFiles;
  }

  Future<FileLoadResult> getFilesInCollection(
    int collectionID,
    int startTime,
    int endTime, {
    int? limit,
    bool? asc,
    int visibility = visibleVisibility,
  }) async {
    final db = await instance.sqliteAsyncDB;
    final order = (asc ?? false ? 'ASC' : 'DESC');
    String query =
        'SELECT * FROM $filesTable WHERE $columnCollectionID = ? AND $columnCreationTime >= ? AND $columnCreationTime <= ? ORDER BY $columnCreationTime $order, $columnModificationTime $order';
    final List<Object> args = [collectionID, startTime, endTime];
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    final results = await db.getAll(query, args);
    final files = convertToFiles(results);
    return FileLoadResult(files, files.length == limit);
  }

  Future<List<EnteFile>> getAllFilesCollection(int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    const String whereClause = '$columnCollectionID = ?';
    final List<Object> whereArgs = [collectionID];
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $whereClause',
      whereArgs,
    );
    final files = convertToFiles(results);
    return files;
  }

  Future<List<EnteFile>> getAllFilesFromCollections(
    Iterable<int> collectionID,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final String sql =
        'SELECT * FROM $filesTable WHERE $columnCollectionID IN (${collectionID.join(',')})';
    final results = await db.getAll(sql);
    final files = convertToFiles(results);
    return files;
  }

  Future<List<EnteFile>> getNewFilesInCollection(
    int collectionID,
    int addedTime,
  ) async {
    final db = await instance.sqliteAsyncDB;
    const String whereClause =
        '$columnCollectionID = ? AND $columnAddedTime > ?';
    final List<Object> whereArgs = [collectionID, addedTime];
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $whereClause',
      whereArgs,
    );
    final files = convertToFiles(results);
    return files;
  }

  Future<List<EnteFile?>> getUploadedFilesBatch(
    List<int> fileIDs,
    int collectionID,
  ) async {
    if (fileIDs.isEmpty) return [];

    final db = await instance.sqliteAsyncDB;
    final placeholders = fileIDs.map((_) => '?').join(',');
    final query =
        '''
      SELECT * FROM $filesTable
      WHERE $columnUploadedFileID IN ($placeholders)
        AND $columnCollectionID = ?
    ''';

    final results = await db.getAll(query, [...fileIDs, collectionID]);
    final files = convertToFiles(results);

    final fileMap = <int, EnteFile>{};
    for (final file in files) {
      if (file.uploadedFileID != null) {
        fileMap[file.uploadedFileID!] = file;
      }
    }

    // Return in same order as input, with null for missing
    return fileIDs.map((id) => fileMap[id]).toList();
  }

  Future<List<EnteFile>> getRecentlySharedFiles({
    required int currentUserID,
    int limit = 100,
    int offset = 0,
    int? addedTimeAfterOrEqualTo,
  }) async {
    final db = await instance.sqliteAsyncDB;
    final whereClauses = <String>[
      '$columnOwnerID IS NOT NULL',
      '$columnOwnerID != ?',
      '$columnAddedTime > 0',
      '$columnUploadedFileID IS NOT NULL',
    ];
    final args = <Object>[currentUserID];
    if (addedTimeAfterOrEqualTo != null) {
      whereClauses.add('$columnAddedTime >= ?');
      args.add(addedTimeAfterOrEqualTo);
    }
    args.add(limit);
    args.add(offset);

    final query =
        '''
      SELECT * FROM $filesTable
      WHERE ${whereClauses.join('\n        AND ')}
      ORDER BY $columnAddedTime DESC, $columnUploadedFileID DESC
      LIMIT ?
      OFFSET ?
    ''';
    final results = await db.getAll(query, args);
    return convertToFiles(results);
  }

  Future<FileLoadResult> getFilesInCollections(
    List<int> collectionIDs,
    int startTime,
    int endTime,
    int userID, {
    int? limit,
    bool? asc,
  }) async {
    if (collectionIDs.isEmpty) {
      return FileLoadResult(<EnteFile>[], false);
    }
    final inParam = collectionIDs.map((id) => "'$id'").join(',');

    final db = await instance.sqliteAsyncDB;
    final order = (asc ?? false ? 'ASC' : 'DESC');
    final String whereClause =
        '$columnCollectionID  IN ($inParam) AND $columnCreationTime >= ? AND '
        '$columnCreationTime <= ? AND $columnOwnerID = ?';
    final List<Object> whereArgs = [startTime, endTime, userID];

    String query =
        'SELECT * FROM $filesTable WHERE $whereClause ORDER BY '
        '$columnCreationTime $order, $columnModificationTime $order';
    if (limit != null) {
      query += ' LIMIT ?';
      whereArgs.add(limit);
    }
    final results = await db.getAll(query, whereArgs);
    final files = convertToFiles(results);
    final dedupeResult = await applyDBFilters(
      files,
      DBFilterOptions.dedupeOption,
    );
    _logger.info("Fetched " + dedupeResult.length.toString() + " files");
    return FileLoadResult(files, files.length == limit);
  }

  Future<List<EnteFile>> getFilesPendingForUpload() async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE ($columnUploadedFileID IS NULL OR '
      '$columnUploadedFileID IS -1) AND $columnCollectionID IS NOT NULL AND '
      '$columnCollectionID IS NOT -1 AND $columnLocalID IS NOT NULL AND '
      '$columnLocalID IS NOT -1 '
      'ORDER BY $columnCreationTime DESC',
    );
    final files = convertToFiles(results);
    files.removeWhere(
      (e) =>
          e.collectionID == null ||
          e.localID == null ||
          e.uploadedFileID != null,
    );
    return files;
  }

  Future<List<EnteFile>> getUnUploadedLocalFiles() async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE ($columnUploadedFileID IS NULL OR '
      '$columnUploadedFileID IS -1) AND $columnLocalID IS NOT NULL '
      'GROUP BY $columnLocalID ORDER BY $columnCreationTime DESC',
    );
    return convertToFiles(results);
  }

  Future<List<EnteFile>> getUnUploadedLocalFilesPendingOfflineProcessing(
    int processingVersion, {
    required int limit,
    ({int creationTime, int generatedID})? cursor,
  }) async {
    final db = await instance.sqliteAsyncDB;
    final args = <Object?>[processingVersion];
    var query =
        'SELECT * FROM $filesTable WHERE $columnGeneratedID IN ('
        'SELECT MAX($columnGeneratedID) FROM $filesTable WHERE '
        '($columnUploadedFileID IS '
        'NULL OR $columnUploadedFileID IS -1) AND $columnLocalID IS NOT NULL '
        'AND $columnLocalID IS NOT -1 AND ($columnMetadataVersion IS NULL OR '
        '$columnMetadataVersion < ?) GROUP BY $columnLocalID)';
    if (cursor != null) {
      query +=
          ' AND ($columnCreationTime < ? OR ($columnCreationTime = ? AND '
          '$columnGeneratedID < ?))';
      args.addAll([
        cursor.creationTime,
        cursor.creationTime,
        cursor.generatedID,
      ]);
    }
    query +=
        ' ORDER BY $columnCreationTime DESC, $columnGeneratedID DESC LIMIT ?';
    args.add(limit);
    final results = await db.getAll(query, args);
    return convertToFiles(results);
  }

  Future<List<int>> getUploadedFileIDsToBeUpdated(int ownerID) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT DISTINCT $columnUploadedFileID FROM $filesTable WHERE '
      '($columnLocalID IS NOT NULL AND $columnOwnerID = ? AND '
      '($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS NOT -1) '
      'AND $columnUpdationTime IS NULL) ORDER BY $columnCreationTime DESC ',
      [ownerID],
    );
    final uploadedFileIDs = <int>[];
    for (final row in rows) {
      uploadedFileIDs.add(row[columnUploadedFileID] as int);
    }
    return uploadedFileIDs;
  }

  Future<List<EnteFile>> getFilesInAllCollection(
    int uploadedFileID,
    int userID,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnLocalID IS NOT NULL AND '
      '$columnOwnerID = ? AND $columnUploadedFileID = ?',
      [userID, uploadedFileID],
    );
    if (results.isEmpty) {
      return <EnteFile>[];
    }
    return convertToFiles(results);
  }

  Future<Set<String>> getExistingLocalFileIDs(int ownerID) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT DISTINCT $columnLocalID FROM $filesTable '
      'WHERE $columnLocalID IS NOT NULL AND ($columnOwnerID IS NULL OR '
      '$columnOwnerID = ?)',
      [ownerID],
    );
    final result = <String>{};
    for (final row in rows) {
      result.add(row[columnLocalID] as String);
    }
    return result;
  }

  Future<Set<String>> getLocalIDsMarkedForOrAlreadyUploaded(int ownerID) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT DISTINCT $columnLocalID FROM $filesTable '
      'WHERE $columnLocalID IS NOT NULL AND ($columnCollectionID IS NOT NULL '
      'AND $columnCollectionID != -1) AND ($columnOwnerID = ? OR '
      '$columnOwnerID IS NULL)',
      [ownerID],
    );
    final result = <String>{};
    for (final row in rows) {
      result.add(row[columnLocalID] as String);
    }
    return result;
  }

  Future<int> removeQueuedLocalFiles(Set<String> localIDs, int ownerID) async {
    if (localIDs.isEmpty) {
      _logger.finest("No local IDs provided for removal");
      return 0;
    }

    final db = await instance.sqliteAsyncDB;
    const batchSize = 10000;
    int totalRemoved = 0;
    final localIDsList = localIDs.toList();

    for (int i = 0; i < localIDsList.length; i += batchSize) {
      final endIndex = (i + batchSize > localIDsList.length)
          ? localIDsList.length
          : i + batchSize;
      final batch = localIDsList.sublist(i, endIndex);
      final placeholders = List.filled(batch.length, '?').join(',');

      final result = await db.execute('''
      SELECT DISTINCT $columnLocalID
      FROM $filesTable
      WHERE 
      $columnOwnerID = $ownerID
      AND $columnLocalID IN ($placeholders)
      AND ($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID != -1)
    ''', batch);

      if (result.isNotEmpty) {
        final alreadyUploadedLocalIDs = result
            .map((row) => row[columnLocalID] as String)
            .toList();
        final localIdPlaceholder = List.filled(
          alreadyUploadedLocalIDs.length,
          '?',
        ).join(',');

        final deleteResult = await db.execute('''
        DELETE FROM $filesTable
        WHERE $columnLocalID IN ($localIdPlaceholder)
        AND ($columnUploadedFileID IS NULL OR $columnUploadedFileID = -1)
      ''', alreadyUploadedLocalIDs);

        final removedCount = deleteResult.length;
        if (removedCount > 0) {
          _logger.warning(
            "Batch ${(i ~/ batchSize) + 1}: Removed $removedCount queued duplicates",
          );
          totalRemoved += removedCount;
        }
      }
    }

    if (totalRemoved > 0) {
      _logger.warning(
        "Removed $totalRemoved queued files that had uploaded duplicates",
      );
    } else {
      _logger.finest("No queued duplicates found for uploaded files");
    }

    return totalRemoved;
  }

  Future<Set<String>> getLocalFileIDsForCollection(int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT $columnLocalID FROM $filesTable '
      'WHERE $columnLocalID IS NOT NULL AND $columnCollectionID = ?',
      [collectionID],
    );
    final result = <String>{};
    for (final row in rows) {
      result.add(row[columnLocalID] as String);
    }
    return result;
  }

  Future<void> setCollectionIDForUnMappedLocalFiles(
    int collectionID,
    Set<String> localIDs,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final inParam = localIDs.map((id) => "'$id'").join(',');
    await db.execute('''
      UPDATE $filesTable
      SET $columnCollectionID = $collectionID
      WHERE $columnLocalID IN ($inParam) AND ($columnCollectionID IS NULL OR 
      $columnCollectionID = -1);
    ''');
  }

  Future<void> markFilesForReUpload(
    int ownerID,
    String localID,
    String? title,
    Location? location,
    int creationTime,
    int modificationTime,
    FileType fileType,
  ) async {
    final db = await instance.sqliteAsyncDB;

    await db.execute(
      '''
      UPDATE $filesTable
      SET  $columnTitle = ?,
            $columnLatitude = ?,
            $columnLongitude = ?,
            $columnCreationTime = ?,
            $columnModificationTime = ?,
            $columnUpdationTime = NULL,
            $columnFileType = ?
      WHERE $columnLocalID = ? AND ($columnOwnerID = ? OR $columnOwnerID IS NULL);
    ''',
      [
        title,
        location?.latitude,
        location?.longitude,
        creationTime,
        modificationTime,
        getInt(fileType),
        localID,
        ownerID,
      ],
    );
  }

  Future<void> updateOfflineImportMetadataForLocalID(
    String localID, {
    required int processingVersion,
    int? creationTime,
    Location? location,
    int? fileSize,
  }) async {
    final db = await instance.sqliteAsyncDB;
    await db.execute(
      '''
      UPDATE $filesTable
      SET  $columnCreationTime = COALESCE(?, $columnCreationTime),
            $columnLatitude = COALESCE(?, $columnLatitude),
            $columnLongitude = COALESCE(?, $columnLongitude),
            $columnFileSize = COALESCE(?, $columnFileSize),
            $columnMetadataVersion = ?
      WHERE $columnLocalID = ? AND ($columnUploadedFileID IS NULL OR $columnUploadedFileID = -1);
    ''',
      [
        creationTime,
        location?.latitude,
        location?.longitude,
        fileSize,
        processingVersion,
        localID,
      ],
    );
  }

  Future<List<EnteFile>> getUnlinkedLocalMatchesForRemoteFile(
    int ownerID,
    String localID,
    FileType fileType, {
    required String title,
    required String deviceFolder,
  }) async {
    final db = await instance.sqliteAsyncDB;
    // on iOS, match using localID and fileType. title can either match or
    // might be null based on how the file was imported
    String query =
        '''SELECT * FROM $filesTable WHERE ($columnOwnerID = ?
        OR $columnOwnerID IS NULL) AND $columnLocalID = ? 
        AND $columnFileType = ? AND ($columnTitle=? OR $columnTitle IS NULL) ''';
    List<Object> whereArgs = [ownerID, localID, getInt(fileType), title];
    if (Platform.isAndroid) {
      query =
          '''SELECT * FROM $filesTable WHERE ($columnOwnerID = ? OR
          $columnOwnerID IS NULL) AND $columnLocalID = ? AND $columnFileType = ? 
          AND $columnTitle=? AND $columnDeviceFolder= ? ''';
      whereArgs = [ownerID, localID, getInt(fileType), title, deviceFolder];
    }

    final rows = await db.getAll(query, whereArgs);

    return convertToFiles(rows);
  }

  Future<Map<String, EnteFile>>
  getUserOwnedFilesWithSameHashForGivenListOfFiles(
    List<EnteFile> files,
    int userID,
  ) async {
    final db = await sqliteAsyncDB;
    final List<String> hashes = [];
    for (final file in files) {
      if (file.hash != null && file.hash != '') {
        hashes.add(file.hash!);
      }
    }
    if (hashes.isEmpty) {
      return {};
    }
    final inParam = hashes.map((e) => "'$e'").join(',');
    final rows = await db.getAll('''
      SELECT * FROM $filesTable WHERE $columnHash IN ($inParam) AND $columnOwnerID = $userID;
      ''');
    final matchedFiles = convertToFiles(rows);
    return Map.fromIterable(matchedFiles, key: (e) => e.hash);
  }

  Future<List<EnteFile>> getUploadedFilesWithHash(
    String hash,
    FileType fileType,
    int ownerID,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT * FROM $filesTable WHERE ($columnUploadedFileID != NULL OR '
      '$columnUploadedFileID != -1) AND $columnOwnerID = ? AND '
      '$columnFileType = ? AND $columnHash = ?',
      [ownerID, getInt(fileType), hash],
    );
    return convertToFiles(rows);
  }

  Future<void> update(EnteFile file) async {
    final db = await instance.sqliteAsyncDB;
    final parameterSet = _getParameterSetForFile(file)..add(file.generatedID);
    final updateAssignments = _generateUpdateAssignmentsWithPlaceholders(
      fileGenId: file.generatedID,
    );
    await db.execute(
      'UPDATE $filesTable '
      'SET $updateAssignments WHERE $columnGeneratedID = ?',
      parameterSet,
    );
  }

  Future<void> updateUploadedFileAcrossCollections(EnteFile file) async {
    final db = await instance.sqliteAsyncDB;
    // _id, collection_id and the encrypted key material must not be written
    // here: the same uploadedFileID can exist as multiple rows (one per
    // collection), each with its own _id, collection_id and encrypted_key/
    // key_decryption_nonce (the file key wrapped with that collection's key).
    // Writing one collection's values across all rows would corrupt the others.
    final parameterSet = _getParameterSetForFile(
      file,
      omitCollectionId: true,
      omitGeneratedId: true,
      omitKeyMaterial: true,
    )..add(file.uploadedFileID);
    final updateAssignments = _generateUpdateAssignmentsWithPlaceholders(
      fileGenId: null,
      omitCollectionId: true,
      omitKeyMaterial: true,
    );
    await db.execute(
      'UPDATE $filesTable '
      'SET $updateAssignments WHERE $columnUploadedFileID = ?',
      parameterSet,
    );
  }

  Future<void> updateLocalIDForUploaded(int uploadedID, String localID) async {
    final db = await instance.sqliteAsyncDB;
    await db.execute(
      'UPDATE $filesTable SET $columnLocalID = ? WHERE $columnUploadedFileID = ?'
      ' AND $columnLocalID IS NULL',
      [localID, uploadedID],
    );
  }

  Future<List<EnteFile>> getUploadedFilesForLocalIDs(
    Iterable<String> localIDs, {
    int? collectionID,
  }) async {
    final ids = localIDs.toSet().toList(growable: false);
    if (ids.isEmpty) return const [];
    final db = await sqliteAsyncDB;
    final rows = <Map<String, Object?>>[];
    for (final batch in ids.slices(900)) {
      final placeholders = List.filled(batch.length, '?').join(',');
      final collectionClause = collectionID == null
          ? ''
          : ' AND $columnCollectionID = ?';
      rows.addAll(
        await db.getAll(
          'SELECT * FROM $filesTable WHERE $columnLocalID IN ($placeholders) '
          'AND $columnUploadedFileID IS NOT NULL AND $columnUploadedFileID != -1'
          '$collectionClause',
          collectionID == null ? batch : [...batch, collectionID],
        ),
      );
    }
    return convertToFiles(rows);
  }

  Future<Set<String>> getUploadedLocalIDs(
    Iterable<String> localIDs, {
    int? collectionID,
  }) async {
    final ids = localIDs.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final db = await sqliteAsyncDB;
    final uploaded = <String>{};
    for (final batch in ids.slices(900)) {
      final placeholders = List.filled(batch.length, '?').join(',');
      final collectionClause = collectionID == null
          ? ''
          : ' AND $columnCollectionID = ?';
      final rows = await db.getAll(
        'SELECT DISTINCT $columnLocalID FROM $filesTable '
        'WHERE $columnLocalID IN ($placeholders) '
        'AND $columnUploadedFileID IS NOT NULL AND $columnUploadedFileID != -1'
        '$collectionClause',
        collectionID == null ? batch : [...batch, collectionID],
      );
      uploaded.addAll(rows.map((row) => row[columnLocalID] as String));
    }
    return uploaded;
  }

  Future<void> deleteByGeneratedID(int genID) async {
    final db = await instance.sqliteAsyncDB;

    await db.execute('DELETE FROM $filesTable WHERE $columnGeneratedID = ?', [
      genID,
    ]);
  }

  Future<void> deleteMultipleUploadedFiles(List<int> uploadedFileIDs) async {
    final db = await instance.sqliteAsyncDB;
    final inParam = uploadedFileIDs.join(',');

    await db.execute(
      'DELETE FROM $filesTable WHERE $columnUploadedFileID IN ($inParam)',
    );
  }

  Future<void> deleteMultipleByGeneratedIDs(List<int> generatedIDs) async {
    if (generatedIDs.isEmpty) {
      return;
    }

    final db = await instance.sqliteAsyncDB;
    final inParam = generatedIDs.join(',');

    await db.execute(
      'DELETE FROM $filesTable WHERE $columnGeneratedID IN ($inParam)',
    );
  }

  Future<void> deleteLocalFile(EnteFile file) async {
    final db = await instance.sqliteAsyncDB;
    if (file.localID != null) {
      unawaited(
        db.execute(
          'DELETE FROM $filesTable WHERE $columnLocalID = ? AND ($columnUploadedFileID IS NULL OR $columnUploadedFileID = -1)',
          [file.localID],
        ),
      );
    } else {
      unawaited(
        db.execute(
          'DELETE FROM $filesTable WHERE $columnGeneratedID = ? AND ($columnUploadedFileID IS NULL OR $columnUploadedFileID = -1)',
          [file.generatedID],
        ),
      );
    }
  }

  Future<void> deleteLocalFiles(List<String> localIDs) async {
    final inParam = localIDs.map((id) => "'$id'").join(',');
    final db = await instance.sqliteAsyncDB;
    await db.execute('''
      UPDATE $filesTable
      SET $columnLocalID = NULL
      WHERE $columnLocalID IN ($inParam);
    ''');
  }

  Future<List<EnteFile>> getLocalFiles(
    List<String> localIDs, {
    bool dedupeByLocalID = false,
  }) async {
    late final String query;
    final inParam = localIDs.map((id) => "'$id'").join(',');
    final db = await instance.sqliteAsyncDB;
    if (dedupeByLocalID) {
      query =
          '''
      SELECT * FROM $filesTable
      WHERE $columnLocalID IN ($inParam)
      GROUP BY $columnLocalID;
    ''';
    } else {
      query =
          '''
      SELECT * FROM $filesTable
      WHERE $columnLocalID IN ($inParam);
    ''';
    }
    final results = await db.getAll(query);
    return convertToFiles(results);
  }

  Future<Set<String>> getAllLocalIDsNewerThan(int creationTimeThreshold) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      '''
      SELECT DISTINCT $columnLocalID
      FROM $filesTable
      WHERE $columnCreationTime >= ? AND $columnLocalID IS NOT NULL
    ''',
      [creationTimeThreshold],
    );
    return rows.map((row) => row[columnLocalID] as String).toSet();
  }

  Future<void> deleteUnSyncedLocalFiles(List<String> localIDs) async {
    final inParam = localIDs.map((id) => "'$id'").join(',');
    final db = await instance.sqliteAsyncDB;
    unawaited(
      db.execute('''
      DELETE FROM $filesTable
      WHERE ($columnUploadedFileID is NULL OR $columnUploadedFileID = -1 ) AND $columnLocalID IN ($inParam)
    '''),
    );
  }

  Future<int> deleteFilesFromCollection(
    int collectionID,
    List<int> uploadedFileIDs,
  ) async {
    final db = await instance.sqliteAsyncDB;
    return db.writeTransaction((tx) async {
      await tx.execute(
        '''
      DELETE FROM $filesTable
      WHERE $columnCollectionID = ? AND $columnUploadedFileID IN (${uploadedFileIDs.join(', ')});
    ''',
        [collectionID],
      );
      final res = await tx.get('SELECT changes()');
      return res['changes()'] as int;
    });
  }

  Future<int> collectionFileCount(int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    final row = await db.get(
      'SELECT COUNT(*) FROM $filesTable where $columnCollectionID = '
      '$collectionID AND $columnUploadedFileID IS NOT -1',
    );
    return row['COUNT(*)'] as int;
  }

  Future<int> archivedFilesCount(
    int visibility,
    int ownerID,
    Set<int> hiddenCollections,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final count = await db.getAll(
      'SELECT COUNT(distinct($columnUploadedFileID)) as COUNT FROM $filesTable where '
      '$columnMMdVisibility'
      ' = $visibility AND $columnOwnerID = $ownerID AND $columnCollectionID NOT IN (${hiddenCollections.join(', ')})',
    );
    return count.first['COUNT'] as int;
  }

  Future<void> deleteCollection(int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    await db.execute('DELETE FROM $filesTable WHERE $columnCollectionID = ?', [
      collectionID,
    ]);
  }

  Future<void> removeFromCollection(int collectionID, List<int> fileIDs) async {
    final db = await instance.sqliteAsyncDB;
    final inParam = fileIDs.join(',');
    await db.execute(
      '''
      DELETE FROM $filesTable
      WHERE $columnCollectionID = ? AND $columnUploadedFileID IN ($inParam);
      ''',
      [collectionID],
    );
  }

  Future<List<EnteFile>> getPendingUploadForCollection(int collectionID) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnCollectionID = ? AND '
      '($columnUploadedFileID IS NULL OR $columnUploadedFileID = -1)',
      [collectionID],
    );
    return convertToFiles(results);
  }

  Future<Set<String>> getLocalIDsPresentInEntries(
    List<EnteFile> existingFiles,
    int collectionID,
  ) async {
    final inParam = existingFiles
        .where((file) => file.localID != null)
        .map((file) => "'${file.localID}'")
        .join(',');
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll('''
      SELECT $columnLocalID
      FROM $filesTable
      WHERE $columnLocalID IN ($inParam) AND $columnCollectionID != 
      $collectionID AND $columnLocalID IS NOT NULL;
    ''');
    final result = <String>{};
    for (final row in rows) {
      result.add(row[columnLocalID] as String);
    }
    return result;
  }

  Future<Map<int, int>> getCollectionIDToMaxCreationTime() async {
    final enteWatch = EnteWatch("getCollectionIDToMaxCreationTime")..start();
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll('''
      SELECT $columnCollectionID, MAX($columnCreationTime) AS max_creation_time
      FROM $filesTable
      WHERE 
      ($columnCollectionID IS NOT NULL AND $columnCollectionID IS NOT -1
       AND $columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS 
       NOT -1)
      GROUP BY $columnCollectionID;
    ''');
    final result = <int, int>{};
    for (final row in rows) {
      result[row[columnCollectionID] as int] = row['max_creation_time'] as int;
    }
    enteWatch.log("query done");
    return result;
  }

  Future<Map<int, int>> getFileIDToCreationTime() async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll('''
      SELECT $columnUploadedFileID, $columnCreationTime
      FROM $filesTable
      WHERE 
      ($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS NOT -1);
    ''');
    final result = <int, int>{};
    for (final row in rows) {
      result[row[columnUploadedFileID] as int] = row[columnCreationTime] as int;
    }
    return result;
  }

  Future<EnteFile?> getCollectionFileFirstOrLast(
    int collectionID,
    bool sortAsc,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final order = sortAsc ? 'ASC' : 'DESC';
    final rows = await db.getAll(
      '''
      SELECT * FROM $filesTable
      WHERE $columnCollectionID = ? AND ($columnUploadedFileID IS NOT NULL
      AND $columnUploadedFileID IS NOT -1)
      ORDER BY $columnCreationTime $order, $columnModificationTime $order
      LIMIT 1;
    ''',
      [collectionID],
    );
    if (rows.isEmpty) {
      return null;
    }
    return convertToFiles(rows).first;
  }

  Future<bool> doesFileExistInCollection(
    int uploadedFileID,
    int collectionID,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnUploadedFileID = ? AND '
      '$columnCollectionID = ? LIMIT 1',
      [uploadedFileID, collectionID],
    );
    return rows.isNotEmpty;
  }

  Future<Map<int, EnteFile>> getFileIDToFileFromIDs(List<int> ids) async {
    final result = <int, EnteFile>{};
    if (ids.isEmpty) {
      return result;
    }
    final inParam = ids.map((id) => "'$id'").join(',');
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnUploadedFileID IN ($inParam)',
    );
    final files = convertToFiles(results);
    for (final file in files) {
      result[file.uploadedFileID!] = file;
    }
    return result;
  }

  Future<List<EnteFile>> getFilesFromIDs(
    List<int> ids, {
    bool asc = false,
    bool dedupeByUploadId = false,
    Set<int> collectionsToIgnore = const {},
  }) async {
    final order = (asc ? 'ASC' : 'DESC');
    if (ids.isEmpty) {
      return [];
    }

    final inParam = ids.map((id) => "'$id'").join(',');
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnUploadedFileID IN ($inParam) ORDER BY $columnCreationTime $order',
    );
    final files = convertToFiles(results);
    final result = await applyDBFilters(
      files,
      DBFilterOptions(
        ignoredCollectionIDs: collectionsToIgnore,
        dedupeUploadID: dedupeByUploadId,
      ),
    );

    return result;
  }

  Future<Map<int, List<EnteFile>>> getAllFilesGroupByCollectionID(
    List<int> ids,
  ) async {
    final result = <int, List<EnteFile>>{};
    if (ids.isEmpty) {
      return result;
    }
    final inParam = ids.map((id) => "'$id'").join(',');
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      'SELECT * FROM $filesTable WHERE $columnUploadedFileID IN ($inParam)',
    );
    final files = convertToFiles(results);
    for (EnteFile eachFile in files) {
      if (!result.containsKey(eachFile.collectionID)) {
        result[eachFile.collectionID as int] = <EnteFile>[];
      }
      result[eachFile.collectionID]!.add(eachFile);
    }
    return result;
  }

  Future<Set<int>> getAllCollectionIDsOfFile(int uploadedFileID) async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll(
      '''
      SELECT DISTINCT $columnCollectionID FROM $filesTable
      WHERE $columnUploadedFileID = ? AND $columnCollectionID != -1
    ''',
      [uploadedFileID],
    );
    final collectionIDsOfFile = <int>{};
    for (var result in results) {
      collectionIDsOfFile.add(result['collection_id'] as int);
    }
    return collectionIDsOfFile;
  }

  Future<Map<int, ({int collectionID, int addedTime})>>
  getEarliestPositiveAddedTimeRowsForUploadedFiles(
    Set<int> uploadedFileIDs,
    int ownerID,
  ) async {
    if (uploadedFileIDs.isEmpty) {
      return {};
    }

    final db = await instance.sqliteAsyncDB;
    final result = <int, ({int collectionID, int addedTime})>{};
    const maxInParams = 900;
    final uploadIDs = uploadedFileIDs.toList(growable: false);

    for (var i = 0; i < uploadIDs.length; i += maxInParams) {
      final end = (i + maxInParams > uploadIDs.length)
          ? uploadIDs.length
          : i + maxInParams;
      final chunk = uploadIDs.sublist(i, end);
      final inParam = chunk.join(',');
      final rows = await db.getAll(
        '''
        SELECT $columnUploadedFileID, $columnCollectionID, $columnAddedTime
        FROM $filesTable
        WHERE $columnOwnerID = ?
        AND $columnUploadedFileID IN ($inParam)
        AND $columnAddedTime > 0
        ''',
        [ownerID],
      );
      for (final row in rows) {
        final uploadedFileID = row[columnUploadedFileID] as int?;
        final collectionID = row[columnCollectionID] as int?;
        final addedTime = row[columnAddedTime] as int?;
        if (uploadedFileID == null ||
            collectionID == null ||
            addedTime == null) {
          continue;
        }
        final current = result[uploadedFileID];
        if (current == null ||
            addedTime < current.addedTime ||
            (addedTime == current.addedTime &&
                collectionID < current.collectionID)) {
          result[uploadedFileID] = (
            collectionID: collectionID,
            addedTime: addedTime,
          );
        }
      }
    }
    return result;
  }

  Future<void> resetPositiveAddedTimeForUploadedFiles(
    Set<int> uploadedFileIDs,
    int ownerID,
  ) async {
    if (uploadedFileIDs.isEmpty) {
      return;
    }

    final db = await instance.sqliteAsyncDB;
    const maxInParams = 900;
    final uploadIDs = uploadedFileIDs.toList(growable: false);

    for (var i = 0; i < uploadIDs.length; i += maxInParams) {
      final end = (i + maxInParams > uploadIDs.length)
          ? uploadIDs.length
          : i + maxInParams;
      final chunk = uploadIDs.sublist(i, end);
      final inParam = chunk.join(',');
      await db.execute(
        '''
        UPDATE $filesTable
        SET $columnAddedTime = -1
        WHERE $columnUploadedFileID IN ($inParam)
        AND $columnOwnerID = ?
        AND $columnAddedTime > 0
        ''',
        [ownerID],
      );
    }
  }

  // Collection IDs may repeat.
  Future<List<int>> getAllCollectionIDsOfFiles(
    List<int> uploadedFileIDs,
  ) async {
    final db = await instance.sqliteAsyncDB;
    final inParam = uploadedFileIDs.join(',');

    final results = await db.getAll('''
      SELECT $columnCollectionID FROM $filesTable
      WHERE $columnUploadedFileID IN ($inParam) AND $columnCollectionID != -1
    ''');
    final collectionIDsOfFiles = <int>[];
    for (var result in results) {
      collectionIDsOfFiles.add(result['collection_id'] as int);
    }
    return collectionIDsOfFiles;
  }

  Future<List<int>> getUploadedFileIDsInCollections(
    Set<int> collectionIds, {
    int? ownerID,
  }) async {
    if (collectionIds.isEmpty) {
      return [];
    }
    final db = await instance.sqliteAsyncDB;
    final inParam = collectionIds.join(',');

    String query =
        '''
      SELECT DISTINCT $columnUploadedFileID FROM $filesTable
      WHERE $columnCollectionID IN ($inParam)
      AND $columnUploadedFileID IS NOT NULL
      AND $columnUploadedFileID != -1
    ''';

    final List<Object> args = [];
    if (ownerID != null) {
      query += ' AND $columnOwnerID = ?';
      args.add(ownerID);
    }

    final results = await db.getAll(query, args);
    return results.map((row) => row[columnUploadedFileID] as int).toList();
  }

  Future<Set<int>> getCollectionIDsForUploadedFileIDs(
    List<int> uploadedFileIds,
  ) async {
    if (uploadedFileIds.isEmpty) {
      return {};
    }
    final db = await instance.sqliteAsyncDB;
    final inParam = uploadedFileIds.join(',');
    final results = await db.getAll('''
      SELECT DISTINCT $columnCollectionID FROM $filesTable
      WHERE $columnUploadedFileID IN ($inParam)
      AND $columnCollectionID IS NOT NULL
      AND $columnCollectionID != -1
    ''');
    return results.map((row) => row[columnCollectionID] as int).toSet();
  }

  List<EnteFile> convertToFilesForIsolate(Map args) {
    final List<EnteFile> files = [];
    for (final result in args["result"]) {
      files.add(_getFileFromRow(result));
    }
    return files;
  }

  List<EnteFile> convertToFiles(List<Map<String, dynamic>> results) {
    final List<EnteFile> files = [];
    for (final result in results) {
      files.add(_getFileFromRow(result));
    }
    return files;
  }

  Future<List<int>> getUploadIDsWithMissingSize(int userId) async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll(
      '''
      SELECT DISTINCT $columnUploadedFileID FROM $filesTable
      WHERE $columnOwnerID = ? AND $columnFileSize IS NULL
    ''',
      [userId],
    );
    final result = <int>[];
    for (final row in rows) {
      result.add(row[columnUploadedFileID] as int);
    }
    return result;
  }

  Future<void> updateSizeForUploadIDs(
    Map<int, int> uploadedFileIDToSize,
  ) async {
    if (uploadedFileIDToSize.isEmpty) {
      return;
    }
    final db = await instance.sqliteAsyncDB;
    final parameterSets = <List<Object?>>[];

    for (final uploadedFileID in uploadedFileIDToSize.keys) {
      parameterSets.add([uploadedFileIDToSize[uploadedFileID], uploadedFileID]);
    }

    await db.executeBatch('''
      UPDATE $filesTable
      SET $columnFileSize = ?
      WHERE $columnUploadedFileID = ?;
    ''', parameterSets);
  }

  Future<List<EnteFile>> getStreamingEligibleVideoFiles({
    DateTime? beginDate,
    required int userID,
    bool onlyFilesWithLocalId = false,
  }) async {
    final db = await instance.sqliteAsyncDB;

    String query =
        '''
      SELECT * FROM $filesTable
      WHERE $columnFileType = ?
      AND ($columnUploadedFileID IS NOT NULL AND $columnUploadedFileID != -1)
      AND $columnOwnerID = ?
      AND ($columnFileSize IS NOT NULL AND $columnFileSize <= 524288000)
      AND ($columnDuration IS NOT NULL AND ($columnDuration <= 60 AND $columnDuration > 0))
    ''';

    final List<Object> queryArgs = [getInt(FileType.video), userID];

    if (beginDate != null) {
      query += ' AND $columnCreationTime > ?';
      queryArgs.add(beginDate.microsecondsSinceEpoch);
    }

    if (onlyFilesWithLocalId) {
      query += ' AND $columnLocalID IS NOT NULL';
    }

    query += ' ORDER BY $columnCreationTime DESC';

    final results = await db.getAll(query, queryArgs);
    return convertToFiles(results);
  }

  Future<List<EnteFile>> getAllFilesFromDB(
    Set<int> collectionsToIgnore, {
    bool dedupeByUploadId = true,
  }) async {
    final result = await _loadMaterializedFiles(
      whereClause: '1 = 1',
      whereArguments: const [],
      order: _MaterializedFileOrder.creationThenIdDescending,
      filterOptions: DBFilterOptions(
        ignoredCollectionIDs: collectionsToIgnore,
        dedupeUploadID: dedupeByUploadId,
      ),
      convertPage: _convertPageInWorkerIsolate,
    );
    return result.files;
  }

  Future<List<EnteFile>> _convertPageInWorkerIsolate(
    List<Map<String, dynamic>> rows,
  ) {
    return Computer.shared().compute(
      _convertFilesDBRowsForIsolate,
      param: {"result": rows},
    );
  }

  Future<List<EnteFile>> _convertPageOnCallerIsolate(
    List<Map<String, dynamic>> rows,
  ) async {
    return convertToFiles(rows);
  }

  Future<FileLoadResult> _loadMaterializedFiles({
    required String whereClause,
    required List<Object?> whereArguments,
    required _MaterializedFileOrder order,
    required _FilePageConverter convertPage,
    DBFilterOptions? filterOptions,
    int? limit,
  }) async {
    final files = <EnteFile>[];
    final normalizedLimit = limit != null && limit >= 0 ? limit : null;
    var rawRowCount = 0;

    final database = await sqliteAsyncDB;
    await database.readTransaction((transaction) async {
      _FilePageBoundary? pageBoundary;
      var remaining = normalizedLimit;

      while (remaining == null || remaining > 0) {
        final requestedRows = remaining == null
            ? _maxMaterializationPageSize
            : min(_maxMaterializationPageSize, remaining);

        final rows = await transaction.getAll(
          _buildMaterializedFileQuery(
            whereClause: whereClause,
            order: order,
            hasPageBoundary: pageBoundary != null,
          ),
          <Object?>[
            ...whereArguments,
            if (pageBoundary != null) ...pageBoundary.values,
            requestedRows,
          ],
        );

        rawRowCount += rows.length;
        if (rows.length > requestedRows ||
            rows.length > _maxMaterializationPageSize) {
          throw StateError(
            'FilesDB materialization page exceeded its configured bound',
          );
        }

        if (rows.isEmpty) {
          break;
        }

        pageBoundary = order.boundaryFrom(rows.last);
        final convertedPage = await convertPage(rows);
        files.addAll(convertedPage);

        if (remaining != null) {
          remaining -= rows.length;
        }
        if (rows.length < requestedRows) {
          break;
        }
      }
    });

    final filteredFiles = await applyDBFilters(files, filterOptions);
    return FileLoadResult(filteredFiles, limit != null && rawRowCount == limit);
  }

  String _buildMaterializedFileQuery({
    required String whereClause,
    required _MaterializedFileOrder order,
    required bool hasPageBoundary,
  }) {
    final pageBoundaryClause = hasPageBoundary
        ? ' AND (${order.columns.join(', ')}) ${order.comparison} '
              '(${List.filled(order.columns.length, '?').join(', ')})'
        : '';
    return 'SELECT * FROM $filesTable '
        'WHERE ($whereClause)$pageBoundaryClause '
        'ORDER BY ${order.orderByClause} LIMIT ?';
  }

  Future<bool> hasAnyFile() async {
    final db = await instance.sqliteAsyncDB;
    final rows = await db.getAll('SELECT 1 FROM $filesTable LIMIT 1');
    return rows.isNotEmpty;
  }

  Future<FileLoadResult> fetchAllUploadedAndSharedFilesWithLocation(
    int startTime,
    int endTime, {
    int? limit,
    bool? asc,
    required DBFilterOptions? filterOptions,
  }) async {
    final db = await instance.sqliteAsyncDB;
    final order = (asc ?? false ? 'ASC' : 'DESC');
    String query =
        '''
      SELECT * FROM $filesTable 
      WHERE $columnLatitude IS NOT NULL AND $columnLongitude IS NOT NULL AND
      ($columnLatitude IS NOT 0 OR $columnLongitude IS NOT 0) AND 
      $columnCreationTime >= ? AND $columnCreationTime <= ? AND
      ($columnLocalID IS NOT NULL OR ($columnCollectionID IS NOT NULL AND 
      $columnCollectionID IS NOT -1)) 
      ORDER BY $columnCreationTime $order, $columnModificationTime $order
      ''';

    final args = [startTime, endTime];

    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }

    final results = await db.getAll(query, args);
    final files = convertToFiles(results);
    final List<EnteFile> filteredFiles = await applyDBFilters(
      files,
      filterOptions,
    );
    return FileLoadResult(filteredFiles, files.length == limit);
  }

  Future<int> remoteFileCount() async {
    final db = await instance.sqliteAsyncDB;
    final results = await db.getAll('''
      SELECT DISTINCT $columnUploadedFileID FROM $filesTable
      WHERE  $columnUploadedFileID IS NOT NULL AND $columnUploadedFileID IS NOT -1
    ''');
    final ids = <int>{};
    for (final result in results) {
      ids.add(result[columnUploadedFileID] as int);
    }
    return ids.length;
  }

  Future<List<EnteFile>> getHiddenFilesWithLocalCopy(
    Set<int> hiddenCollectionIds,
    int ownerID,
  ) async {
    if (hiddenCollectionIds.isEmpty) {
      return [];
    }
    final db = await instance.sqliteAsyncDB;
    final inParam = hiddenCollectionIds.join(',');
    final results = await db.getAll(
      '''
      SELECT * FROM $filesTable
      WHERE $columnCollectionID IN ($inParam)
      AND $columnOwnerID = ?
      AND $columnLocalID IS NOT NULL AND $columnLocalID != ''
      AND $columnUploadedFileID IS NOT NULL AND $columnUploadedFileID != -1
      GROUP BY $columnUploadedFileID
      ORDER BY $columnCreationTime DESC
      ''',
      [ownerID],
    );
    return convertToFiles(results);
  }

  Future<bool> hasHiddenFilesWithLocalCopy(
    Set<int> hiddenCollectionIds,
    int ownerID,
  ) async {
    if (hiddenCollectionIds.isEmpty) {
      return false;
    }
    final db = await instance.sqliteAsyncDB;
    final inParam = hiddenCollectionIds.join(',');
    final results = await db.getAll(
      '''
      SELECT 1 FROM $filesTable
      WHERE $columnCollectionID IN ($inParam)
      AND $columnOwnerID = ?
      AND $columnLocalID IS NOT NULL AND $columnLocalID != ''
      AND $columnUploadedFileID IS NOT NULL AND $columnUploadedFileID != -1
      LIMIT 1
      ''',
      [ownerID],
    );
    return results.isNotEmpty;
  }

  Future<void> clearLocalIDsForUploadedFileIDs(
    List<int> uploadedFileIDs,
  ) async {
    if (uploadedFileIDs.isEmpty) {
      return;
    }
    final db = await instance.sqliteAsyncDB;
    final inParam = uploadedFileIDs.join(',');
    await db.execute('''
      UPDATE $filesTable
      SET $columnLocalID = NULL
      WHERE $columnUploadedFileID IN ($inParam)
      ''');
  }

  String _generateUpdateAssignmentsWithPlaceholders({
    required int? fileGenId,
    bool omitCollectionId = false,
    bool omitKeyMaterial = false,
  }) {
    final assignments = <String>[];

    for (String columnName in _columnNames) {
      if (columnName == columnGeneratedID && fileGenId == null) {
        continue;
      }
      if (columnName == columnCollectionID && omitCollectionId) {
        continue;
      }
      if (omitKeyMaterial &&
          (columnName == columnEncryptedKey ||
              columnName == columnKeyDecryptionNonce)) {
        continue;
      }
      assignments.add("$columnName = ?");
    }

    return assignments.join(",");
  }

  Map<String, String> _generateColumnsAndPlaceholdersForInsert({
    required int? fileGenId,
  }) {
    final columnNames = <String>[];

    for (String columnName in _columnNames) {
      if (columnName == columnGeneratedID && fileGenId == null) {
        continue;
      }

      columnNames.add(columnName);
    }

    return {
      "columns": columnNames.join(","),
      "placeholders": List.filled(columnNames.length, "?").join(","),
    };
  }

  List<Object?> _getParameterSetForFile(
    EnteFile file, {
    bool omitCollectionId = false,
    bool omitGeneratedId = false,
    bool omitKeyMaterial = false,
  }) {
    final values = <Object?>[];

    double? latitude = file.location?.latitude;
    double? longitude = file.location?.longitude;

    int? creationTime = file.creationTime;
    if (file.pubMagicMetadata != null) {
      if (file.pubMagicMetadata!.editedTime != null) {
        creationTime = file.pubMagicMetadata!.editedTime;
      }
      if (file.pubMagicMetadata!.lat != null &&
          file.pubMagicMetadata!.long != null) {
        latitude = file.pubMagicMetadata!.lat;
        longitude = file.pubMagicMetadata!.long;
      }
    }

    if (file.generatedID != null && !omitGeneratedId) {
      values.add(file.generatedID);
    }
    values.addAll([
      file.localID,
      file.uploadedFileID ?? -1,
      file.ownerID,
      if (!omitCollectionId) file.collectionID ?? -1,
      file.title,
      file.deviceFolder,
      latitude,
      longitude,
      getInt(file.fileType),
      file.modificationTime,
      if (!omitKeyMaterial) file.encryptedKey,
      if (!omitKeyMaterial) file.keyDecryptionNonce,
      file.fileDecryptionHeader,
      file.thumbnailDecryptionHeader,
      file.metadataDecryptionHeader,
      creationTime,
      file.updationTime,
      file.fileSubType ?? -1,
      file.duration ?? 0,
      file.exif,
      file.hash,
      file.metadataVersion,
      file.mMdEncodedJson ?? '{}',
      file.mMdVersion,
      file.magicMetadata.visibility,
      file.pubMmdEncodedJson ?? '{}',
      file.pubMmdVersion,
      file.fileSize,
      file.addedTime ?? -1,
    ]);

    return values;
  }

  Future<void> _insertBatch(
    SqliteAsyncConflictAlgorithm conflictAlgorithm,
    Iterable<String> columnNames,
    SqliteDatabase db,
    List<List<Object?>> parameterSets,
  ) async {
    final valuesPlaceholders = List.filled(columnNames.length, "?").join(",");
    final columnNamesJoined = columnNames.join(",");
    await db.executeBatch('''
          INSERT OR ${conflictAlgorithm.name.toUpperCase()} INTO $filesTable($columnNamesJoined) VALUES($valuesPlaceholders)
                                  ''', parameterSets);
  }

  EnteFile _getFileFromRow(Map<String, dynamic> row) {
    final file = EnteFile();
    file.generatedID = row[columnGeneratedID];
    file.localID = row[columnLocalID];
    file.uploadedFileID = row[columnUploadedFileID] == -1
        ? null
        : row[columnUploadedFileID];
    file.ownerID = row[columnOwnerID];
    file.collectionID = row[columnCollectionID] == -1
        ? null
        : row[columnCollectionID];
    file.title = row[columnTitle];
    file.deviceFolder = row[columnDeviceFolder];
    if (row[columnLatitude] != null && row[columnLongitude] != null) {
      file.location = Location(
        latitude: row[columnLatitude],
        longitude: row[columnLongitude],
      );
    }
    file.fileType = getFileType(row[columnFileType]);
    file.creationTime = row[columnCreationTime];
    file.modificationTime = row[columnModificationTime];
    file.updationTime = row[columnUpdationTime] ?? -1;
    file.addedTime = row[columnAddedTime];
    file.encryptedKey = row[columnEncryptedKey];
    file.keyDecryptionNonce = row[columnKeyDecryptionNonce];
    file.fileDecryptionHeader = row[columnFileDecryptionHeader];
    file.thumbnailDecryptionHeader = row[columnThumbnailDecryptionHeader];
    file.metadataDecryptionHeader = row[columnMetadataDecryptionHeader];
    file.fileSubType = row[columnFileSubType] ?? -1;
    file.duration = row[columnDuration] ?? 0;
    file.exif = row[columnExif];
    file.hash = row[columnHash];
    file.metadataVersion = row[columnMetadataVersion] ?? 0;
    file.fileSize = row[columnFileSize];

    file.mMdVersion = row[columnMMdVersion] ?? 0;
    file.mMdEncodedJson = row[columnMMdEncodedJson] ?? '{}';

    file.pubMmdVersion = row[columnPubMMdVersion] ?? 0;
    file.pubMmdEncodedJson = row[columnPubMMdEncodedJson] ?? '{}';
    return file;
  }
}

typedef _FilePageConverter =
    Future<List<EnteFile>> Function(List<Map<String, dynamic>> rows);

enum _MaterializedFileOrder {
  creationThenIdDescending([
    FilesDB.columnCreationTime,
    FilesDB.columnGeneratedID,
  ], false),
  creationThenModificationThenIdDescending([
    FilesDB.columnCreationTime,
    FilesDB.columnModificationTime,
    FilesDB.columnGeneratedID,
  ], false),
  creationThenModificationThenIdAscending([
    FilesDB.columnCreationTime,
    FilesDB.columnModificationTime,
    FilesDB.columnGeneratedID,
  ], true);

  final List<String> columns;
  final bool ascending;

  const _MaterializedFileOrder(this.columns, this.ascending);

  String get comparison => ascending ? '>' : '<';

  String get orderByClause => columns
      .map((column) => '$column ${ascending ? 'ASC' : 'DESC'}')
      .join(', ');

  _FilePageBoundary boundaryFrom(Map<String, dynamic> row) => _FilePageBoundary(
    columns.map<Object?>((column) => row[column]).toList(growable: false),
  );
}

class _FilePageBoundary {
  final List<Object?> values;

  const _FilePageBoundary(this.values);
}

List<EnteFile> _convertFilesDBRowsForIsolate(Map<dynamic, dynamic> arguments) =>
    FilesDB.instance.convertToFilesForIsolate(arguments);
