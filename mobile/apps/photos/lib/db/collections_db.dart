import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import "package:photos/gateways/collections/models/public_url.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_migration/sqflite_migration.dart';

class CollectionsDB {
  static const _databaseName = "ente.collections.db";
  static const table = 'collections';
  static const tempTable = 'temp_collections';
  static const _sqlBoolTrue = 1;
  static const _sqlBoolFalse = 0;

  static const columnID = 'collection_id';
  static const columnOwner = 'owner';
  static const columnEncryptedKey = 'encrypted_key';
  static const columnKeyDecryptionNonce = 'key_decryption_nonce';
  static const columnName = 'name';
  static const columnEncryptedName = 'encrypted_name';
  static const columnNameDecryptionNonce = 'name_decryption_nonce';
  static const columnType = 'type';
  static const columnEncryptedPath = 'encrypted_path';
  static const columnPathDecryptionNonce = 'path_decryption_nonce';
  static const columnVersion = 'version';
  static const columnSharees = 'sharees';
  static const columnPublicURLs = 'public_urls';
  // MMD -> Magic Metadata
  static const columnMMdEncodedJson = 'mmd_encoded_json';
  static const columnMMdVersion = 'mmd_ver';

  static const columnPubMMdEncodedJson = 'pub_mmd_encoded_json';
  static const columnPubMMdVersion = 'pub_mmd_ver';

  static const columnSharedMMdJson = 'shared_mmd_json';
  static const columnSharedMMdVersion = 'shared_mmd_ver';

  static const columnUpdationTime = 'updation_time';
  static const columnSharedAt = 'shared_at';
  static const columnIsDeleted = 'is_deleted';

  static final intitialScript = [...createTable(table)];
  static final migrationScripts = [
    ...alterNameToAllowNULL(),
    ...addEncryptedName(),
    ...addVersion(),
    ...addIsDeleted(),
    ...addPublicURLs(),
    ...addPrivateMetadata(),
    ...addPublicMetadata(),
    ...addShareeMetadata(),
    ...addSharedAt(),
  ];

  final dbConfig = MigrationConfig(
    initializationScript: intitialScript,
    migrationScripts: migrationScripts,
  );

  CollectionsDB._privateConstructor();

  static final CollectionsDB instance = CollectionsDB._privateConstructor();

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

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.delete(table);
  }

  static List<String> createTable(String tableName) {
    return [
      '''
        CREATE TABLE $tableName (
          $columnID INTEGER PRIMARY KEY NOT NULL,
          $columnOwner TEXT NOT NULL,
          $columnEncryptedKey TEXT NOT NULL,
          $columnKeyDecryptionNonce TEXT,
          $columnName TEXT,
          $columnType TEXT NOT NULL,
          $columnEncryptedPath TEXT,
          $columnPathDecryptionNonce TEXT,
          $columnSharees TEXT,
          $columnUpdationTime TEXT NOT NULL
        );
    ''',
    ];
  }

  static List<String> alterNameToAllowNULL() {
    return [
      ...createTable(tempTable),
      '''
        INSERT INTO $tempTable
        SELECT *
        FROM $table;

        DROP TABLE $table;
        
        ALTER TABLE $tempTable 
        RENAME TO $table;
    ''',
    ];
  }

  static List<String> addEncryptedName() {
    return [
      '''
        ALTER TABLE $table
        ADD COLUMN $columnEncryptedName TEXT;
      ''',
      '''ALTER TABLE $table
        ADD COLUMN $columnNameDecryptionNonce TEXT;
      ''',
    ];
  }

  static List<String> addVersion() {
    return [
      '''
        ALTER TABLE $table
        ADD COLUMN $columnVersion INTEGER DEFAULT 0;
      ''',
    ];
  }

  static List<String> addIsDeleted() {
    return [
      '''
        ALTER TABLE $table
        ADD COLUMN $columnIsDeleted INTEGER DEFAULT $_sqlBoolFalse;
      ''',
    ];
  }

  static List<String> addPublicURLs() {
    return [
      '''
        ALTER TABLE $table 
        ADD COLUMN $columnPublicURLs TEXT;
      ''',
    ];
  }

  static List<String> addPrivateMetadata() {
    return [
      '''
        ALTER TABLE $table ADD COLUMN $columnMMdEncodedJson TEXT DEFAULT '{}';
      ''',
      '''
        ALTER TABLE $table ADD COLUMN $columnMMdVersion INTEGER DEFAULT 0;
      ''',
    ];
  }

  static List<String> addPublicMetadata() {
    return [
      '''
        ALTER TABLE $table ADD COLUMN $columnPubMMdEncodedJson TEXT DEFAULT '
        {}';
      ''',
      '''
        ALTER TABLE $table ADD COLUMN $columnPubMMdVersion INTEGER DEFAULT 0;
      ''',
    ];
  }

  static List<String> addShareeMetadata() {
    return [
      '''
        ALTER TABLE $table ADD COLUMN $columnSharedMMdJson TEXT DEFAULT '
        {}';
      ''',
      '''
        ALTER TABLE $table ADD COLUMN $columnSharedMMdVersion INTEGER DEFAULT 0;
      ''',
    ];
  }

  static List<String> addSharedAt() {
    return [
      '''
        ALTER TABLE $table ADD COLUMN $columnSharedAt INTEGER;
      ''',
    ];
  }

  Future<void> insert(List<Collection> collections) async {
    final db = await instance.database;
    var batch = db.batch();
    int batchCounter = 0;
    for (final collection in collections) {
      if (batchCounter == 400) {
        await batch.commit(noResult: true);
        batch = db.batch();
        batchCounter = 0;
      }
      batch.insert(
        table,
        _getRowForCollection(collection),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batchCounter++;
    }
    await batch.commit(noResult: true);
  }

  Future<List<Collection>> getAllCollections() async {
    final db = await instance.database;
    final rows = await db.query(table);
    final collections = <Collection>[];
    for (final row in rows) {
      collections.add(_convertToCollection(row));
    }
    return collections;
  }

  // getActiveCollectionIDsAndUpdationTime returns map of collectionID to
  // updationTime for non-deleted collections
  Future<Map<int, int>> getActiveIDsAndRemoteUpdateTime() async {
    final db = await instance.database;
    final rows = await db.query(
      table,
      where: '($columnIsDeleted = ? OR $columnIsDeleted IS NULL)',
      whereArgs: [_sqlBoolFalse],
      columns: [columnID, columnUpdationTime],
    );
    final collectionIDsAndUpdationTime = <int, int>{};
    for (final row in rows) {
      collectionIDsAndUpdationTime[row[columnID] as int] = int.parse(
        row[columnUpdationTime] as String,
      );
    }
    return collectionIDsAndUpdationTime;
  }

  Future<int> deleteCollection(int collectionID) async {
    final db = await instance.database;
    return db.delete(table, where: '$columnID = ?', whereArgs: [collectionID]);
  }

  Map<String, dynamic> _getRowForCollection(Collection collection) {
    final row = <String, dynamic>{};
    row[columnID] = collection.id;
    row[columnOwner] = collection.owner.toJson();
    row[columnEncryptedKey] = collection.encryptedKey;
    row[columnKeyDecryptionNonce] = collection.keyDecryptionNonce;
    // ignore: deprecated_member_use_from_same_package
    row[columnName] = collection.name;
    row[columnEncryptedName] = collection.encryptedName;
    row[columnNameDecryptionNonce] = collection.nameDecryptionNonce;
    row[columnType] = typeToString(collection.type);
    row[columnEncryptedPath] = collection.attributes.encryptedPath;
    row[columnPathDecryptionNonce] = collection.attributes.pathDecryptionNonce;
    row[columnVersion] = collection.attributes.version;
    row[columnSharees] = json.encode(
      collection.sharees.map((x) => x.toMap()).toList(),
    );
    row[columnPublicURLs] = json.encode(
      collection.publicURLs.map((x) => x.toMap()).toList(),
    );
    row[columnUpdationTime] = collection.updationTime;
    row[columnSharedAt] = collection.sharedAt;
    if (collection.isDeleted) {
      row[columnIsDeleted] = _sqlBoolTrue;
    } else {
      row[columnIsDeleted] = _sqlBoolFalse;
    }
    row[columnMMdVersion] = collection.mMdVersion;
    row[columnMMdEncodedJson] = collection.mMdEncodedJson ?? '{}';
    row[columnPubMMdVersion] = collection.mMbPubVersion;
    row[columnPubMMdEncodedJson] = collection.mMdPubEncodedJson ?? '{}';

    row[columnSharedMMdVersion] = collection.sharedMmdVersion;
    row[columnSharedMMdJson] = collection.sharedMmdJson ?? '{}';
    return row;
  }

  Collection _convertToCollection(Map<String, dynamic> row) {
    final Collection result = Collection(
      row[columnID],
      User.fromJson(row[columnOwner]),
      row[columnEncryptedKey],
      row[columnKeyDecryptionNonce],
      row[columnName],
      row[columnEncryptedName],
      row[columnNameDecryptionNonce],
      typeFromString(row[columnType]),
      CollectionAttributes(
        encryptedPath: row[columnEncryptedPath],
        pathDecryptionNonce: row[columnPathDecryptionNonce],
        version: row[columnVersion],
      ),
      List<User>.from(
        (json.decode(row[columnSharees]) as List).map((x) => User.fromMap(x)),
      ),
      row[columnPublicURLs] == null
          ? []
          : List<PublicURL>.from(
              (json.decode(row[columnPublicURLs]) as List).map(
                (x) => PublicURL.fromMap(x),
              ),
            ),
      int.parse(row[columnUpdationTime]),
      sharedAt: _parseNullableInt(row[columnSharedAt]),
      // default to False is columnIsDeleted is not set
      isDeleted: (row[columnIsDeleted] ?? _sqlBoolFalse) == _sqlBoolTrue,
    );
    result.mMdVersion = row[columnMMdVersion] ?? 0;
    result.mMdEncodedJson = row[columnMMdEncodedJson] ?? '{}';
    result.mMbPubVersion = row[columnPubMMdVersion] ?? 0;
    result.mMdPubEncodedJson = row[columnPubMMdEncodedJson] ?? '{}';

    result.sharedMmdVersion = row[columnSharedMMdVersion] ?? 0;
    result.sharedMmdJson = row[columnSharedMMdJson] ?? '{}';
    return result;
  }

  int? _parseNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
