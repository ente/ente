import 'dart:convert';

import 'package:photos/db/common/base.dart';
import "package:photos/gateways/collections/models/public_url.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:sqlite_async/sqlite_async.dart';

class CollectionsDB with SqlDbBase {
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

  CollectionsDB._privateConstructor();

  static final CollectionsDB instance = CollectionsDB._privateConstructor();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(_databaseName, [
      ...intitialScript,
      ...migrationScripts,
    ]),
  );

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.execute('DELETE FROM $table');
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
    await _insertBatch(db, [
      for (final collection in collections)
        _getParametersForCollection(collection),
    ]);
  }

  Future<List<Collection>> getAllCollections() async {
    final db = await instance.database;
    final rows = await db.getAll('SELECT * FROM $table');
    final collections = <Collection>[];
    for (final row in rows) {
      collections.add(_convertToCollection(row));
    }
    return collections;
  }

  Future<Map<int, int>> getActiveIDsAndRemoteUpdateTime() async {
    final db = await instance.database;
    final rows = await db.getAll(
      '''
      SELECT $columnID, $columnUpdationTime
      FROM $table
      WHERE $columnIsDeleted = ? OR $columnIsDeleted IS NULL
      ''',
      [_sqlBoolFalse],
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
    final rows = await db.execute(
      'DELETE FROM $table WHERE $columnID = ? RETURNING $columnID',
      [collectionID],
    );
    return rows.length;
  }

  Future<void> _insertBatch(
    SqliteDatabase db,
    List<List<Object?>> parameterSets,
  ) async {
    if (parameterSets.isEmpty) return;
    await db.executeBatch('''
      INSERT OR REPLACE INTO $table (
        $columnID, $columnOwner, $columnEncryptedKey,
        $columnKeyDecryptionNonce, $columnName, $columnEncryptedName,
        $columnNameDecryptionNonce, $columnType, $columnEncryptedPath,
        $columnPathDecryptionNonce, $columnVersion, $columnSharees,
        $columnPublicURLs, $columnUpdationTime, $columnSharedAt,
        $columnIsDeleted, $columnMMdVersion, $columnMMdEncodedJson,
        $columnPubMMdVersion, $columnPubMMdEncodedJson,
        $columnSharedMMdVersion, $columnSharedMMdJson
      ) VALUES (${SqlDbBase.getParams(22)})
      ''', parameterSets);
  }

  List<Object?> _getParametersForCollection(Collection collection) {
    return [
      collection.id,
      collection.owner.toJson(),
      collection.encryptedKey,
      collection.keyDecryptionNonce,
      // ignore: deprecated_member_use_from_same_package
      collection.name,
      collection.encryptedName,
      collection.nameDecryptionNonce,
      typeToString(collection.type),
      collection.attributes.encryptedPath,
      collection.attributes.pathDecryptionNonce,
      collection.attributes.version,
      json.encode(collection.sharees.map((x) => x.toMap()).toList()),
      json.encode(collection.publicURLs.map((x) => x.toMap()).toList()),
      collection.updationTime,
      collection.sharedAt,
      collection.isDeleted ? _sqlBoolTrue : _sqlBoolFalse,
      collection.mMdVersion,
      collection.mMdEncodedJson ?? '{}',
      collection.mMbPubVersion,
      collection.mMdPubEncodedJson ?? '{}',
      collection.sharedMmdVersion,
      collection.sharedMmdJson ?? '{}',
    ];
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
