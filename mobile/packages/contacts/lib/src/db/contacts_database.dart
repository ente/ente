import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ente_contacts/src/models/contact_data.dart';
import 'package:ente_contacts/src/models/contact_record.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef ContactsDatabaseDirectoryResolver = Future<Directory> Function();

class ContactsDatabase {
  static const _databasePrefix = 'ente.contacts.';
  static const _databaseSuffix = '.db';
  static const _databaseVersion = 1;
  static const _contactsTable = 'contacts';
  static const _attachmentsTable = 'cached_attachments';
  static const _stateTable = 'contact_state';

  ContactsDatabase({ContactsDatabaseDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver;

  final ContactsDatabaseDirectoryResolver? _directoryResolver;

  Database? _database;
  Future<Database>? _dbFuture;
  int? _configuredUserId;

  Future<void> configure({required int userId}) async {
    if (_configuredUserId == userId && _dbFuture != null) {
      return;
    }
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _dbFuture = null;
    _configuredUserId = userId;
  }

  Future<Database> get database async {
    final userId = _configuredUserId;
    if (userId == null) {
      throw StateError(
        'ContactsDatabase.configure(userId: ...) must be called first',
      );
    }
    _dbFuture ??= _initDatabase(userId);
    _database ??= await _dbFuture!;
    return _database!;
  }

  Future<void> upsertContacts(List<ContactRecord> contacts) async {
    if (contacts.isEmpty) {
      return;
    }
    final db = await database;
    final batch = db.batch();
    for (final contact in contacts) {
      batch.insert(_contactsTable, {
        'id': contact.id,
        'contact_user_id': contact.contactUserId,
        'email': contact.email,
        'data_json': contact.data == null
            ? null
            : jsonEncode(contact.data!.toJson()),
        'profile_picture_attachment_id': contact.profilePictureAttachmentId,
        'is_deleted': contact.isDeleted ? 1 : 0,
        'created_at': contact.createdAt,
        'updated_at': contact.updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<ContactRecord?> getContact(String id) async {
    final db = await database;
    final rows = await db.query(
      _contactsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  Future<ContactRecord?> getContactByUserId(
    int contactUserId, {
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      _contactsTable,
      where: includeDeleted
          ? 'contact_user_id = ?'
          : 'contact_user_id = ? AND is_deleted = 0',
      whereArgs: [contactUserId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  Future<List<ContactRecord>> getContacts({bool includeDeleted = false}) async {
    final db = await database;
    final rows = await db.query(
      _contactsTable,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> getLastSyncedUpdatedAt() async {
    final db = await database;
    final rows = await db.query(_stateTable, limit: 1);
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['last_synced_updated_at'] as int?) ?? 0;
  }

  Future<void> setLastSyncedUpdatedAt(int value) async {
    final db = await database;
    await db.update(_stateTable, {
      'id': 1,
      'last_synced_updated_at': value,
    }, where: 'id = 1');
  }

  Future<void> resetState() async {
    final db = await database;
    await db.delete(_contactsTable);
    await db.delete(_attachmentsTable);
    await setLastSyncedUpdatedAt(0);
  }

  Future<Uint8List?> getCachedAttachment(String attachmentId) async {
    final db = await database;
    final rows = await db.query(
      _attachmentsTable,
      columns: const ['bytes'],
      where: 'attachment_id = ?',
      whereArgs: [attachmentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['bytes'] as Uint8List?;
  }

  Future<void> upsertCachedAttachment(
    String attachmentId,
    Uint8List bytes,
  ) async {
    final db = await database;
    await db.insert(_attachmentsTable, {
      'attachment_id': attachmentId,
      'bytes': bytes,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCachedAttachment(String attachmentId) async {
    final db = await database;
    await db.delete(
      _attachmentsTable,
      where: 'attachment_id = ?',
      whereArgs: [attachmentId],
    );
  }

  Future<void> deleteUnreferencedCachedAttachments() async {
    final db = await database;
    await db.delete(
      _attachmentsTable,
      where:
          '''
        attachment_id NOT IN (
          SELECT profile_picture_attachment_id
          FROM $_contactsTable
          WHERE profile_picture_attachment_id IS NOT NULL
        )
      ''',
    );
  }

  Future<void> clearTable() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _dbFuture = null;
    }
    final directory = await _resolvedDirectory();
    if (!directory.existsSync()) {
      return;
    }
    for (final entity in directory.listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith(_databasePrefix)) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }
  }

  Future<Database> _initDatabase(int userId) async {
    final path = p.join(
      (await _resolvedDirectory()).path,
      '$_databasePrefix$userId$_databaseSuffix',
    );

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      final databaseFactory = databaseFactoryFfi;
      return databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
        ),
      );
    }

    return openDatabase(path, version: _databaseVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_contactsTable (
        id TEXT PRIMARY KEY,
        contact_user_id INTEGER NOT NULL,
        email TEXT,
        data_json TEXT,
        profile_picture_attachment_id TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_contacts_contact_user_id ON $_contactsTable(contact_user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_contacts_updated_at ON $_contactsTable(updated_at)',
    );
    await db.execute('''
      CREATE TABLE $_attachmentsTable (
        attachment_id TEXT PRIMARY KEY,
        bytes BLOB NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_stateTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_synced_updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert(_stateTable, {'id': 1, 'last_synced_updated_at': 0});
  }

  Future<Directory> _resolvedDirectory() async {
    if (_directoryResolver != null) {
      final directory = await _directoryResolver();
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      return directory;
    }
    final Directory directory;
    if (Platform.isMacOS) {
      directory = await getApplicationSupportDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  ContactRecord _fromRow(Map<String, Object?> row) {
    final dataJson = row['data_json'] as String?;
    return ContactRecord(
      id: row['id']! as String,
      contactUserId: row['contact_user_id']! as int,
      email: row['email'] as String?,
      data: dataJson == null
          ? null
          : ContactData.fromJson(jsonDecode(dataJson) as Map<String, dynamic>),
      profilePictureAttachmentId:
          row['profile_picture_attachment_id'] as String?,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
      createdAt: row['created_at']! as int,
      updatedAt: row['updated_at']! as int,
    );
  }
}
