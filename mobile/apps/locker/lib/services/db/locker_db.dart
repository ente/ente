import 'dart:convert';
import 'dart:io';

import "package:ente_base/models/database.dart";
import 'package:ente_crypto_api/ente_crypto_api.dart';
import "package:ente_sharing/models/user.dart";
import 'package:flutter/foundation.dart';
import 'package:locker/models/file_type.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/collections/models/public_url.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/utils/crypto_helper.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LockerDB extends EnteBaseDatabase {
  LockerDB._privateConstructor();

  static final LockerDB instance = LockerDB._privateConstructor();

  Database? _database;
  int _collectionSyncTime = 0;
  final Map<int, int> _collectionSyncTimesCache = {};
  final Set<int> _offlineMarkedFileIDsCache = {};

  static const String databaseName = 'locker.db';
  static const String _collectionsTable = 'collections';
  static const String _filesTable = 'files';
  static const String trashTable = 'trash_files';
  static const String _collectionFilesTable = 'collection_files';
  static const String _offlineFilesTable = 'offline_marks';
  static const String _syncTimesTable = 'sync_times';
  static const int _collectionPayloadVersion = 1;
  static const int _filePayloadVersion = 1;
  static const int _trashPayloadVersion = 1;
  static const int _databaseVersion = 2;

  static final List<Future<void> Function(DatabaseExecutor)> _migrationScripts =
      [_createOfflineFilesTable];

  Future<void> init() async {
    _database = await _initDatabase();
    await _loadCaches();
  }

  Future<void> _loadCaches() async {
    final syncTimes = await _db.query(
      _syncTimesTable,
      where: 'key LIKE ?',
      whereArgs: ['collection_sync_time_%'],
    );

    for (final row in syncTimes) {
      final key = row['key'] as String;
      final collectionId = int.tryParse(
        key.replaceFirst('collection_sync_time_', ''),
      );
      if (collectionId != null) {
        _collectionSyncTimesCache[collectionId] = row['value'] as int;
      }
    }

    final globalSyncTime = await getSyncTimeAsync();
    _collectionSyncTime = globalSyncTime;
    await _populateOfflineMarkedFileIDsCache();
  }

  Future<void> _populateOfflineMarkedFileIDsCache() async {
    final offlineMarkedRows = await _db.query(
      _offlineFilesTable,
      columns: ['uploaded_file_id'],
    );
    _offlineMarkedFileIDsCache
      ..clear()
      ..addAll(offlineMarkedRows.map((row) => row['uploaded_file_id'] as int));
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    await _deleteObsoleteDatabases(documentsDirectory.path);
    final path = join(documentsDirectory.path, databaseName);
    if (kDebugMode) {
      debugPrint('LockerDB path: $path');
    }

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, _) => _createTables(db),
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion >= newVersion) {
      return;
    }

    await db.transaction((txn) async {
      for (var index = oldVersion - 1; index < newVersion - 1; index++) {
        await _migrationScripts[index](txn);
      }
    });
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_collectionsTable (
        id INTEGER PRIMARY KEY,
        owner_id INTEGER,
        type TEXT,
        updation_time INTEGER,
        is_deleted INTEGER DEFAULT 0,
        encrypted_key TEXT,
        key_decryption_nonce TEXT,
        payload_encrypted_data TEXT NOT NULL,
        payload_decryption_nonce TEXT NOT NULL,
        payload_version INTEGER DEFAULT $_collectionPayloadVersion
      )
    ''');

    await _createFilesTable(db);
    await _createTrashTable(db);
    await _createOfflineFilesTable(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_collectionFilesTable (
        collection_id INTEGER,
        uploaded_file_id INTEGER,
        PRIMARY KEY (collection_id, uploaded_file_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_syncTimesTable (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_collection_id ON $_filesTable (collection_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_uploaded_file_id ON $_filesTable (uploaded_file_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_collection_files_uploaded_file_id ON $_collectionFilesTable (uploaded_file_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_collections_updation_time ON $_collectionsTable (updation_time)
    ''');
  }

  Future<void> _createFilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_filesTable (
        uploaded_file_id INTEGER PRIMARY KEY,
        collection_id INTEGER,
        owner_id INTEGER,
        updation_time INTEGER,
        encrypted_key TEXT,
        key_decryption_nonce TEXT,
        file_decryption_header TEXT,
        thumbnail_decryption_header TEXT,
        metadata_decryption_header TEXT,
        file_size INTEGER,
        payload_encrypted_data TEXT NOT NULL,
        payload_decryption_header TEXT NOT NULL,
        payload_version INTEGER DEFAULT $_filePayloadVersion
      )
    ''');
  }

  static Future<void> _createOfflineFilesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_offlineFilesTable (
        uploaded_file_id INTEGER PRIMARY KEY
      )
    ''');
  }

  Future<void> _createTrashTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LockerDB.trashTable} (
        uploaded_file_id INTEGER PRIMARY KEY,
        collection_id INTEGER,
        owner_id INTEGER,
        updation_time INTEGER,
        encrypted_key TEXT,
        key_decryption_nonce TEXT,
        file_decryption_header TEXT,
        thumbnail_decryption_header TEXT,
        metadata_decryption_header TEXT,
        file_size INTEGER,
        created_at INTEGER,
        update_at INTEGER,
        delete_by INTEGER,
        payload_encrypted_data TEXT NOT NULL,
        payload_decryption_header TEXT NOT NULL,
        payload_version INTEGER DEFAULT $_trashPayloadVersion
      )
    ''');
  }

  Future<void> _deleteObsoleteDatabases(String baseDir) async {
    const obsoleteNames = <String>['collection_store.db', 'trash.db'];
    for (final name in obsoleteNames) {
      final obsoletePath = join(baseDir, name);
      if (obsoletePath == join(baseDir, databaseName)) {
        continue;
      }
      try {
        await deleteDatabase(obsoletePath);
      } catch (_) {
        // Ignore cleanup errors; the app can continue with the new DB.
      }
      try {
        final walFile = File('$obsoletePath-wal');
        if (await walFile.exists()) {
          await walFile.delete();
        }
        final shmFile = File('$obsoletePath-shm');
        if (await shmFile.exists()) {
          await shmFile.delete();
        }
      } catch (_) {
        // Ignore sidecar cleanup failures.
      }
    }
  }

  Database get _db {
    if (_database == null) {
      throw Exception('Database not initialized. Call init() first.');
    }
    return _database!;
  }

  Database get database => _db;

  Future<void> setSyncTime(int lastSyncTime) async {
    _collectionSyncTime = lastSyncTime;
    await _db.insert(_syncTimesTable, {
      'key': 'collection_sync_time',
      'value': lastSyncTime,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  int getSyncTime() {
    return _collectionSyncTime;
  }

  Future<int> getSyncTimeAsync() async {
    final result = await _db.query(
      _syncTimesTable,
      where: 'key = ?',
      whereArgs: ['collection_sync_time'],
    );

    if (result.isNotEmpty) {
      _collectionSyncTime = result.first['value'] as int;
      return _collectionSyncTime;
    }
    return 0;
  }

  int getCollectionSyncTime(int collectionId) {
    return _collectionSyncTimesCache[collectionId] ?? 0;
  }

  Future<int> getCollectionSyncTimeAsync(int collectionId) async {
    final result = await _db.query(
      _syncTimesTable,
      where: 'key = ?',
      whereArgs: ['collection_sync_time_$collectionId'],
    );

    int syncTime = 0;
    if (result.isNotEmpty) {
      syncTime = result.first['value'] as int;
    }

    _collectionSyncTimesCache[collectionId] = syncTime;
    return syncTime;
  }

  Future<void> setCollectionSyncTime(int collectionId, int lastSyncTime) async {
    await _db.insert(_syncTimesTable, {
      'key': 'collection_sync_time_$collectionId',
      'value': lastSyncTime,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _collectionSyncTimesCache[collectionId] = lastSyncTime;
  }

  Future<Collection> getCollection(int id) async {
    final result = await _db.query(
      _collectionsTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) {
      throw Exception('Collection with id $id not found');
    }

    return _mapToCollection(result.first);
  }

  Future<void> updateCollections(List<Collection> collections) async {
    final batch = _db.batch();

    for (final collection in collections) {
      batch.delete(
        _collectionsTable,
        where: 'id = ?',
        whereArgs: [collection.id],
      );

      batch.insert(_collectionsTable, _collectionToMap(collection));
    }

    await batch.commit();
  }

  Future<void> deleteCollection(Collection collection) async {
    final batch = _db.batch();

    batch.delete(
      _collectionsTable,
      where: 'id = ?',
      whereArgs: [collection.id],
    );

    batch.delete(
      _collectionFilesTable,
      where: 'collection_id = ?',
      whereArgs: [collection.id],
    );

    final filesInCollection = await _db.query(
      _collectionFilesTable,
      where: 'collection_id = ?',
      whereArgs: [collection.id],
    );

    for (final fileMap in filesInCollection) {
      final uploadedFileId = fileMap['uploaded_file_id'] as int;
      final otherCollections = await _db.query(
        _collectionFilesTable,
        where: 'uploaded_file_id = ? AND collection_id != ?',
        whereArgs: [uploadedFileId, collection.id],
      );

      if (otherCollections.isEmpty) {
        batch.delete(
          _filesTable,
          where: 'uploaded_file_id = ?',
          whereArgs: [uploadedFileId],
        );
      }
    }

    await batch.commit();
  }

  Future<List<Collection>> getCollections() async {
    final result = await _db.query(_collectionsTable);
    return result.map((row) => _mapToCollection(row)).toList();
  }

  Future<void> addFilesToCollection(
    Collection collection,
    List<EnteFile> files,
  ) async {
    final batch = _db.batch();

    for (final file in files) {
      final fileMap = await _fileToMap(file);
      batch.insert(
        _filesTable,
        fileMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      batch.insert(_collectionFilesTable, {
        'collection_id': collection.id,
        'uploaded_file_id': file.uploadedFileID!,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit();
  }

  Future<void> deleteFilesFromCollection(
    Collection collection,
    List<EnteFile> files,
  ) async {
    final batch = _db.batch();

    for (final file in files) {
      batch.delete(
        _collectionFilesTable,
        where: 'collection_id = ? AND uploaded_file_id = ?',
        whereArgs: [collection.id, file.uploadedFileID!],
      );

      final otherCollections = await _db.query(
        _collectionFilesTable,
        where: 'uploaded_file_id = ? AND collection_id != ?',
        whereArgs: [file.uploadedFileID!, collection.id],
      );

      if (otherCollections.isEmpty) {
        batch.delete(
          _filesTable,
          where: 'uploaded_file_id = ?',
          whereArgs: [file.uploadedFileID!],
        );
      }
    }

    await batch.commit();
  }

  Future<void> deleteFilesByUploadedFileIDs(List<int> uploadedFileIDs) async {
    if (uploadedFileIDs.isEmpty) {
      return;
    }

    final batch = _db.batch();

    for (final uploadedFileID in uploadedFileIDs) {
      batch.delete(
        _collectionFilesTable,
        where: 'uploaded_file_id = ?',
        whereArgs: [uploadedFileID],
      );
      batch.delete(
        _filesTable,
        where: 'uploaded_file_id = ?',
        whereArgs: [uploadedFileID],
      );
    }

    await batch.commit();
  }

  Future<List<EnteFile>> getFilesInCollection(Collection collection) async {
    final result = await _db.rawQuery(
      '''
      SELECT f.*
      FROM $_filesTable f
      INNER JOIN $_collectionFilesTable cf ON f.uploaded_file_id = cf.uploaded_file_id
      WHERE cf.collection_id = ?
    ''',
      [collection.id],
    );
    final Set<int> seenFileIds = {};
    final List<EnteFile> uniqueFiles = [];

    for (final row in result) {
      final file = await _mapFromRow(row);

      if (!seenFileIds.contains(file.uploadedFileID)) {
        seenFileIds.add(file.uploadedFileID!);
        uniqueFiles.add(file);
      }
    }

    return uniqueFiles;
  }

  Future<List<Collection>> getCollectionsForFile(EnteFile file) async {
    final result = await _db.rawQuery(
      '''
      SELECT c.*
      FROM $_collectionsTable c
      INNER JOIN $_collectionFilesTable cf ON c.id = cf.collection_id
      WHERE cf.uploaded_file_id = ?
    ''',
      [file.uploadedFileID!],
    );

    return result.map((row) => _mapToCollection(row)).toList();
  }

  Future<Map<int, List<EnteFile>>> getAllFilesGroupByCollectionID(
    List<int> uploadedFileIDs,
  ) async {
    if (uploadedFileIDs.isEmpty) {
      return {};
    }

    final Map<int, List<EnteFile>> collectionToFilesMap = {};

    // Query to get all collection mappings for the given file IDs
    final placeholders = List.filled(uploadedFileIDs.length, '?').join(',');
    final result = await _db.rawQuery('''
      SELECT
        cf.collection_id AS mapping_collection_id,
        f.*
      FROM $_collectionFilesTable cf
      JOIN $_filesTable f ON cf.uploaded_file_id = f.uploaded_file_id
      WHERE cf.uploaded_file_id IN ($placeholders)
    ''', uploadedFileIDs);

    // Group files by collection ID
    for (final row in result) {
      final collectionId = row['mapping_collection_id'] as int;
      final file = await _mapFromRow(row)
        ..collectionID = collectionId;

      collectionToFilesMap.putIfAbsent(collectionId, () => []);
      collectionToFilesMap[collectionId]!.add(file);
    }

    return collectionToFilesMap;
  }

  Future<List<EnteFile>> getAllFiles() async {
    final result = await _db.query(_filesTable);
    final files = <EnteFile>[];
    for (final row in result) {
      files.add(await _mapFromRow(row));
    }
    return files;
  }

  /// Removes orphaned files that exist in files but have no collection mappings.
  Future<void> cleanupOrphanedFiles() async {
    final orphanedFiles = await _db.rawQuery('''
      SELECT f.uploaded_file_id
      FROM $_filesTable f
      LEFT JOIN $_collectionFilesTable cf ON f.uploaded_file_id = cf.uploaded_file_id
      WHERE cf.uploaded_file_id IS NULL
    ''');

    if (orphanedFiles.isEmpty) {
      return;
    }

    final batch = _db.batch();
    for (final row in orphanedFiles) {
      final fileId = row['uploaded_file_id'];
      batch.delete(
        _filesTable,
        where: 'uploaded_file_id = ?',
        whereArgs: [fileId],
      );
    }

    await batch.commit();
  }

  bool isFileMarkedOfflineById(int? uploadedFileID) {
    return uploadedFileID != null &&
        _offlineMarkedFileIDsCache.contains(uploadedFileID);
  }

  bool isFileMarkedOffline(EnteFile file) {
    return isFileMarkedOfflineById(file.uploadedFileID);
  }

  Future<void> setFilesMarkedOffline(
    Iterable<int> uploadedFileIDs,
    bool isMarkedOffline,
  ) async {
    final ids = uploadedFileIDs.toSet();
    if (ids.isEmpty) {
      return;
    }

    final batch = _db.batch();
    for (final uploadedFileID in ids) {
      if (isMarkedOffline) {
        batch.insert(_offlineFilesTable, {
          'uploaded_file_id': uploadedFileID,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        batch.delete(
          _offlineFilesTable,
          where: 'uploaded_file_id = ?',
          whereArgs: [uploadedFileID],
        );
      }
    }
    await batch.commit();
    if (isMarkedOffline) {
      _offlineMarkedFileIDsCache.addAll(ids);
    } else {
      _offlineMarkedFileIDsCache.removeAll(ids);
    }
  }

  Future<bool> hasActiveFile(int uploadedFileID) async {
    final rows = await _db.rawQuery(
      '''
      SELECT 1
      FROM $_collectionFilesTable cf
      INNER JOIN $_collectionsTable c
        ON c.id = cf.collection_id
      WHERE c.is_deleted = 0
        AND cf.uploaded_file_id = ?
      LIMIT 1
      ''',
      [uploadedFileID],
    );
    return rows.isNotEmpty;
  }

  Future<List<int>> getStaleOfflineMarkedFileIDs() async {
    final rows = await _db.rawQuery('''
      SELECT om.uploaded_file_id
      FROM $_offlineFilesTable om
      WHERE NOT EXISTS (
        SELECT 1
        FROM $_collectionFilesTable cf
        INNER JOIN $_collectionsTable c
          ON c.id = cf.collection_id
        WHERE cf.uploaded_file_id = om.uploaded_file_id
          AND c.is_deleted = 0
      )
      ''');

    return rows.map((row) => row['uploaded_file_id'] as int).toList();
  }

  Map<String, dynamic> _collectionToMap(Collection collection) {
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
    final encryptedPayload = CryptoUtil.encryptSync(
      utf8.encode(jsonEncode(_collectionPayloadToMap(collection))),
      collectionKey,
    );

    return {
      'id': collection.id,
      'owner_id': collection.owner.id,
      'type': typeToString(collection.type),
      'updation_time': collection.updationTime,
      'is_deleted': collection.isDeleted ? 1 : 0,
      'encrypted_key': collection.encryptedKey,
      'key_decryption_nonce': collection.keyDecryptionNonce,
      'payload_encrypted_data': CryptoUtil.bin2base64(
        encryptedPayload.encryptedData!,
      ),
      'payload_decryption_nonce': CryptoUtil.bin2base64(
        encryptedPayload.nonce!,
      ),
      'payload_version': _collectionPayloadVersion,
    };
  }

  Map<String, dynamic> _collectionPayloadToMap(Collection collection) {
    return {
      'owner_email': collection.owner.email,
      // ignore: deprecated_member_use
      'owner_name': collection.owner.name,
      'name': collection.name,
      'attributes_version': collection.attributes.version,
      'attributes_encrypted_path': collection.attributes.encryptedPath,
      'attributes_path_decryption_nonce':
          collection.attributes.pathDecryptionNonce,
      'sharees': collection.sharees.map((user) => user.toMap()).toList(),
      'public_urls': collection.publicURLs.map((url) => url.toMap()).toList(),
      'decrypted_path': collection.decryptedPath,
      'm_md_encoded_json': collection.mMdEncodedJson,
      'm_md_pub_encoded_json': collection.mMdPubEncodedJson,
      'shared_mmd_json': collection.sharedMmdJson,
      'm_md_version': collection.mMdVersion,
      'm_mb_pub_version': collection.mMbPubVersion,
      'shared_mmd_version': collection.sharedMmdVersion,
    };
  }

  Collection _mapToCollection(Map<String, dynamic> map) {
    final payload = _collectionPayloadFromRow(map);

    final owner = User(
      id: map['owner_id'] as int?,
      email: payload['owner_email'] as String? ?? '',
      name: payload['owner_name'] as String?,
    );

    final attributes = CollectionAttributes(
      version: payload['attributes_version'] as int? ?? 0,
      encryptedPath: payload['attributes_encrypted_path'] as String?,
      pathDecryptionNonce:
          payload['attributes_path_decryption_nonce'] as String?,
    );

    final shareesData = payload['sharees'] as List<dynamic>? ?? const [];
    final sharees = shareesData
        .map((shareeeMap) => User.fromMap(shareeeMap as Map<String, dynamic>))
        .toList();

    final publicURLsData = payload['public_urls'] as List<dynamic>? ?? const [];
    final publicURLs = publicURLsData
        .map((urlMap) => PublicURL.fromMap(urlMap as Map<String, dynamic>))
        .toList();

    final collection = Collection(
      map['id'] as int,
      owner,
      map['encrypted_key'] as String,
      map['key_decryption_nonce'] as String?,
      payload['name'] as String?,
      null,
      null,
      typeFromString(map['type'] as String),
      attributes,
      sharees,
      publicURLs,
      map['updation_time'] as int,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );

    collection.decryptedPath = payload['decrypted_path'] as String?;
    collection.mMdEncodedJson = payload['m_md_encoded_json'] as String?;
    collection.mMdPubEncodedJson = payload['m_md_pub_encoded_json'] as String?;
    collection.sharedMmdJson = payload['shared_mmd_json'] as String?;
    collection.mMdVersion = payload['m_md_version'] as int? ?? 0;
    collection.mMbPubVersion = payload['m_mb_pub_version'] as int? ?? 0;
    collection.sharedMmdVersion = payload['shared_mmd_version'] as int? ?? 0;

    return collection;
  }

  Map<String, dynamic> _collectionPayloadFromRow(Map<String, dynamic> map) {
    final encryptedPayloadData = map['payload_encrypted_data'] as String?;
    final payloadDecryptionNonce = map['payload_decryption_nonce'] as String?;
    if (encryptedPayloadData == null || payloadDecryptionNonce == null) {
      return _legacyCollectionPayloadFromRow(map);
    }

    final collectionKey = _getCollectionKeyFromRow(map);
    final decryptedPayload = CryptoUtil.decryptSync(
      CryptoUtil.base642bin(encryptedPayloadData),
      collectionKey,
      CryptoUtil.base642bin(payloadDecryptionNonce),
    );
    return jsonDecode(utf8.decode(decryptedPayload)) as Map<String, dynamic>;
  }

  Map<String, dynamic> _legacyCollectionPayloadFromRow(
    Map<String, dynamic> map,
  ) {
    final shareesJson = map['sharees'] as String? ?? '[]';
    final publicUrlsJson = map['public_urls'] as String? ?? '[]';

    return {
      'owner_email': map['owner_email'],
      'owner_name': map['owner_name'],
      'name': map['name'],
      'attributes_version': map['attributes_version'],
      'attributes_encrypted_path': map['attributes_encrypted_path'],
      'attributes_path_decryption_nonce':
          map['attributes_path_decryption_nonce'],
      'sharees': jsonDecode(shareesJson) as List<dynamic>,
      'public_urls': jsonDecode(publicUrlsJson) as List<dynamic>,
      'decrypted_path': map['decrypted_path'],
      'm_md_encoded_json': map['m_md_encoded_json'],
      'm_md_pub_encoded_json': map['m_md_pub_encoded_json'],
      'shared_mmd_json': map['shared_mmd_json'],
      'm_md_version': map['m_md_version'],
      'm_mb_pub_version': map['m_mb_pub_version'],
      'shared_mmd_version': map['shared_mmd_version'],
    };
  }

  Uint8List _getCollectionKeyFromRow(Map<String, dynamic> map) {
    final encryptedKey = map['encrypted_key'] as String?;
    if (encryptedKey == null) {
      throw Exception('Invalid collections row: missing encrypted key');
    }

    final owner = User(id: map['owner_id'] as int?, email: '');
    final collection = Collection(
      map['id'] as int,
      owner,
      encryptedKey,
      map['key_decryption_nonce'] as String?,
      null,
      null,
      null,
      typeFromString(map['type'] as String),
      CollectionAttributes(),
      <User>[],
      <PublicURL>[],
      map['updation_time'] as int? ?? 0,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
    return CryptoHelper.instance.getCollectionKey(collection);
  }

  Future<Map<String, dynamic>> _fileToMap(EnteFile file) async {
    final fileKey = await _getFileKey(file);
    final encryptedPayload = await CryptoUtil.encryptData(
      utf8.encode(jsonEncode(_filePayloadToMap(file))),
      fileKey,
    );

    return {
      'uploaded_file_id': file.uploadedFileID,
      'collection_id': file.collectionID,
      'owner_id': file.ownerID,
      'updation_time': file.updationTime,
      'encrypted_key': file.encryptedKey,
      'key_decryption_nonce': file.keyDecryptionNonce,
      'file_decryption_header': file.fileDecryptionHeader,
      'thumbnail_decryption_header': file.thumbnailDecryptionHeader,
      'metadata_decryption_header': file.metadataDecryptionHeader,
      'file_size': file.fileSize,
      'payload_encrypted_data': CryptoUtil.bin2base64(
        encryptedPayload.encryptedData!,
      ),
      'payload_decryption_header': CryptoUtil.bin2base64(
        encryptedPayload.header!,
      ),
      'payload_version': _filePayloadVersion,
    };
  }

  Map<String, dynamic> _filePayloadToMap(EnteFile file) {
    return {
      'local_path': file.localPath,
      'title': file.title,
      'creation_time': file.creationTime,
      'modification_time': file.modificationTime,
      'added_time': file.addedTime,
      'hash': file.hash,
      'metadata_version': file.metadataVersion,
      'file_type': file.fileType?.index,
      'm_md_encoded_json': file.mMdEncodedJson,
      'm_md_version': file.mMdVersion,
      'pub_mmd_encoded_json': file.pubMmdEncodedJson,
      'pub_mmd_version': file.pubMmdVersion,
    };
  }

  Future<EnteFile> _mapFromRow(Map<String, dynamic> map) async {
    final encryptedPayloadData = map['payload_encrypted_data'] as String?;
    final payloadDecryptionHeader = map['payload_decryption_header'] as String?;
    if (encryptedPayloadData == null || payloadDecryptionHeader == null) {
      throw Exception('Invalid files row: missing encrypted payload');
    }

    final fileKey = await _getFileKeyFromRow(map);
    final decryptedPayload = await CryptoUtil.decryptData(
      CryptoUtil.base642bin(encryptedPayloadData),
      fileKey,
      CryptoUtil.base642bin(payloadDecryptionHeader),
    );

    final payload =
        jsonDecode(utf8.decode(decryptedPayload)) as Map<String, dynamic>;

    final file = EnteFile();
    file.uploadedFileID = map['uploaded_file_id'];
    file.collectionID = map['collection_id'];
    file.encryptedKey = map['encrypted_key'];
    file.keyDecryptionNonce = map['key_decryption_nonce'];

    file.localPath = payload['local_path'];
    file.ownerID = map['owner_id'] ?? payload['owner_id'];
    file.title = payload['title'];
    file.creationTime = payload['creation_time'];
    file.modificationTime = payload['modification_time'];
    file.updationTime = map['updation_time'] ?? payload['updation_time'];
    file.addedTime = payload['added_time'];
    file.hash = payload['hash'];
    file.metadataVersion = payload['metadata_version'];
    file.fileDecryptionHeader =
        map['file_decryption_header'] ?? payload['file_decryption_header'];
    file.thumbnailDecryptionHeader =
        map['thumbnail_decryption_header'] ??
        payload['thumbnail_decryption_header'];
    file.metadataDecryptionHeader =
        map['metadata_decryption_header'] ??
        payload['metadata_decryption_header'];
    file.fileSize = map['file_size'] ?? payload['file_size'];
    if (payload['file_type'] != null) {
      file.fileType = getFileType(payload['file_type']);
    }
    file.mMdEncodedJson = payload['m_md_encoded_json'];
    file.mMdVersion = payload['m_md_version'] ?? 0;
    file.pubMmdEncodedJson = payload['pub_mmd_encoded_json'];
    file.pubMmdVersion = payload['pub_mmd_version'] ?? 1;

    return file;
  }

  Future<Uint8List> _getFileKey(EnteFile file) async {
    if (file.collectionID == null ||
        file.encryptedKey == null ||
        file.keyDecryptionNonce == null) {
      throw Exception('Missing file key data for file ${file.uploadedFileID}');
    }

    final collection = await getCollection(file.collectionID!);
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
    return CryptoHelper.instance.getFileKey(
      file.encryptedKey!,
      file.keyDecryptionNonce!,
      collectionKey,
    );
  }

  Future<Uint8List> _getFileKeyFromRow(Map<String, dynamic> map) async {
    final collectionID = map['collection_id'] as int?;
    final encryptedKey = map['encrypted_key'] as String?;
    final keyDecryptionNonce = map['key_decryption_nonce'] as String?;

    if (collectionID == null ||
        encryptedKey == null ||
        keyDecryptionNonce == null) {
      throw Exception(
        'Missing key fields in files for file ${map['uploaded_file_id']}',
      );
    }

    final collection = await getCollection(collectionID);
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
    return CryptoHelper.instance.getFileKey(
      encryptedKey,
      keyDecryptionNonce,
      collectionKey,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  @override
  Future<void> clearTable() async {
    await _database?.delete(_collectionsTable);
    await _database?.delete(_filesTable);
    await _database?.delete(LockerDB.trashTable);
    await _database?.delete(_collectionFilesTable);
    await _database?.delete(_offlineFilesTable);
    await _database?.delete(_syncTimesTable);
    _collectionSyncTimesCache.clear();
    _offlineMarkedFileIDsCache.clear();
    _collectionSyncTime = 0;
  }
}
