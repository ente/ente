import 'dart:async';
import 'dart:io';

import 'package:ente_auth/models/authenticator/auth_entity.dart';
import 'package:ente_auth/models/authenticator/local_auth_entity.dart';
import 'package:ente_auth/utils/directory_utils.dart';
import 'package:ente_base/ente_base.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AuthenticatorDB extends EnteBaseDatabase {
  static const _databaseName = "ente.authenticator.db";
  static const _databaseVersion = 1;

  static const entityTable = 'entities';

  AuthenticatorDB._privateConstructor();
  static final AuthenticatorDB instance = AuthenticatorDB._privateConstructor();

  static Future<Database>? _dbFuture;

  Future<Database> get database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux) {
      var databaseFactory = databaseFactoryFfi;
      return await databaseFactory.openDatabase(
        await DirectoryUtils.getDatabasePath(_databaseName),
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
        ),
      );
    }
    final Directory documentsDirectory = Platform.isMacOS
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    debugPrint(path);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
                CREATE TABLE $entityTable (
                  _generatedID INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                  id TEXT,
                  encryptedData TEXT NOT NULL,
                  header TEXT NOT NULL,
                  createdAt INTEGER NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  shouldSync INTEGER DEFAULT 0,
                  UNIQUE(id)
                );
      ''');
  }

  Future<int> insert(String encData, String header) async {
    final db = await instance.database;
    final int timeInMicroSeconds = DateTime.now().microsecondsSinceEpoch;
    final insertedID = await db.insert(entityTable, {
      "encryptedData": encData,
      "header": header,
      "shouldSync": 1,
      "createdAt": timeInMicroSeconds,
      "updatedAt": timeInMicroSeconds,
    });
    return insertedID;
  }

  Future<int> updateEntry(
    int generatedID,
    String encData,
    String header,
  ) async {
    final db = await instance.database;
    final int timeInMicroSeconds = DateTime.now().microsecondsSinceEpoch;
    int affectedRows = await db.update(
      entityTable,
      {
        "encryptedData": encData,
        "header": header,
        "shouldSync": 1,
        "updatedAt": timeInMicroSeconds,
      },
      where: '_generatedID = ?',
      whereArgs: [generatedID],
    );
    return affectedRows;
  }

  Future<void> insertOrReplace(List<AuthEntity> authEntities) async {
    final db = await instance.database;
    final batch = db.batch();
    for (AuthEntity authEntity in authEntities) {
      final insertRow = authEntity.toMap();
      insertRow.remove('isDeleted');
      insertRow.putIfAbsent('shouldSync', () => 0);
      batch.insert(
        entityTable,
        insertRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateLocalEntity(LocalAuthEntity localAuthEntity) async {
    final db = await instance.database;
    await db.update(
      entityTable,
      localAuthEntity.toMap(),
      where: '_generatedID = ?',
      whereArgs: [localAuthEntity.generatedID],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LocalAuthEntity?> getEntryByID(int genID) async {
    final db = await instance.database;
    final rows = await db.query(
      entityTable,
      where: '_generatedID = ?',
      whereArgs: [genID],
    );
    final listOfAuthEntities = _convertRows(rows);
    if (listOfAuthEntities.isEmpty) {
      return null;
    } else {
      return listOfAuthEntities.first;
    }
  }

  Future<List<LocalAuthEntity>> getAll() async {
    final db = await instance.database;
    final rows = await db.rawQuery("SELECT * from $entityTable");
    return _convertRows(rows);
  }

  // removeSyncedData will remove all the data which is synced with the server
  Future<int> removeSyncedData() async {
    final db = await instance.database;
    return await db.delete(
      entityTable,
      where: 'shouldSync = ?',
      whereArgs: [0],
    );
  }

  // getCount of entries which are not synced with the server
  Future<int> getNeedSyncCount() async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) from $entityTable WHERE shouldSync = 1",
    );
    return Sqflite.firstIntValue(rows)!;
  }

  // deleteByID will prefer generated id if both ids are passed during deletion
  Future<void> deleteByIDs({List<int>? generatedIDs, List<String>? ids}) async {
    final db = await instance.database;
    final batch = db.batch();
    const whereGenID = '_generatedID = ?';
    const whereID = 'id = ?';
    if (generatedIDs != null) {
      for (int genId in generatedIDs) {
        batch.delete(entityTable, where: whereGenID, whereArgs: [genId]);
      }
    }
    if (ids != null) {
      for (String id in ids) {
        batch.delete(entityTable, where: whereID, whereArgs: [id]);
      }
    }
    final _ = await batch.commit();
    debugPrint("Done");
  }

  @override
  Future<void> clearTable() async {
    final db = await instance.database;
    await db.delete(entityTable);
  }

  List<LocalAuthEntity> _convertRows(List<Map<String, dynamic>> rows) {
    final keys = <LocalAuthEntity>[];
    for (final row in rows) {
      keys.add(LocalAuthEntity.fromMap(row));
    }
    return keys;
  }
}
