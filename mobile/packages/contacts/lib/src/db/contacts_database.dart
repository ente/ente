import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ente_frb/contacts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_async/sqlite_async.dart';

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

  Future<SqliteDatabase>? _dbFuture;
  int? _configuredUserId;

  Future<void> configure({required int userId}) async {
    if (_configuredUserId == userId && _dbFuture != null) {
      return;
    }
    await close();
    _configuredUserId = userId;
  }

  Future<void> close() async {
    final databaseFuture = _dbFuture;
    _dbFuture = null;
    _configuredUserId = null;
    if (databaseFuture != null) {
      try {
        await (await databaseFuture).close();
      } catch (_) {}
    }
  }

  Future<SqliteDatabase> get database async {
    final userId = _configuredUserId;
    if (userId == null) {
      throw StateError(
        'ContactsDatabase.configure(userId: ...) must be called first',
      );
    }
    final databaseFuture = _dbFuture ??= _initDatabase(userId);
    try {
      return await databaseFuture;
    } catch (_) {
      if (identical(_dbFuture, databaseFuture)) {
        _dbFuture = null;
      }
      rethrow;
    }
  }

  Future<void> upsertContacts(List<ContactRecord> contacts) async {
    if (contacts.isEmpty) {
      return;
    }
    final db = await database;
    await db.executeBatch(
      '''
      INSERT OR REPLACE INTO $_contactsTable (
        id, contact_user_id, email, data_json,
        profile_picture_attachment_id, is_deleted, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [for (final contact in contacts) _contactParameters(contact)],
    );
  }

  Future<ContactRecord?> getContact(String id) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT * FROM $_contactsTable WHERE id = ? LIMIT 1',
      [id],
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
    final rows = await db.getAll(
      '''
      SELECT * FROM $_contactsTable
      WHERE contact_user_id = ?${includeDeleted ? '' : ' AND is_deleted = 0'}
      LIMIT 1
      ''',
      [contactUserId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  Future<List<ContactRecord>> getContacts({bool includeDeleted = false}) async {
    final db = await database;
    final rows = await db.getAll('''
      SELECT * FROM $_contactsTable
      ${includeDeleted ? '' : 'WHERE is_deleted = 0'}
      ORDER BY updated_at DESC
      ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> getLastSyncedUpdatedAt() async {
    final db = await database;
    final rows = await db.getAll('SELECT * FROM $_stateTable LIMIT 1');
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['last_synced_updated_at'] as int?) ?? 0;
  }

  Future<void> setLastSyncedUpdatedAt(int value) async {
    final db = await database;
    await db.execute(
      'UPDATE $_stateTable SET last_synced_updated_at = ? WHERE id = 1',
      [value],
    );
  }

  Future<void> resetState() async {
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $_contactsTable');
      await tx.execute('DELETE FROM $_attachmentsTable');
      await tx.execute(
        'UPDATE $_stateTable SET last_synced_updated_at = 0 WHERE id = 1',
      );
    });
  }

  Future<Uint8List?> getCachedAttachment(String attachmentId) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT bytes FROM $_attachmentsTable
      WHERE attachment_id = ?
      LIMIT 1
      ''',
      [attachmentId],
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
    await db.execute(
      '''
      INSERT OR REPLACE INTO $_attachmentsTable (
        attachment_id, bytes, cached_at
      ) VALUES (?, ?, ?)
      ''',
      [attachmentId, bytes, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> deleteCachedAttachment(String attachmentId) async {
    final db = await database;
    await db.execute('DELETE FROM $_attachmentsTable WHERE attachment_id = ?', [
      attachmentId,
    ]);
  }

  Future<void> deleteUnreferencedCachedAttachments() async {
    final db = await database;
    await db.execute('''
      DELETE FROM $_attachmentsTable
      WHERE attachment_id NOT IN (
        SELECT profile_picture_attachment_id
        FROM $_contactsTable
        WHERE profile_picture_attachment_id IS NOT NULL
      )
    ''');
  }

  Future<void> clearTable() async {
    await close();
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

  Future<SqliteDatabase> _initDatabase(int userId) async {
    final path = p.join(
      (await _resolvedDirectory()).path,
      '$_databasePrefix$userId$_databaseSuffix',
    );

    final database = SqliteDatabase(path: path, maxReaders: 1);
    try {
      await _migrate(database);
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<void> _migrate(SqliteDatabase database) async {
    final probe = await database.writeLock(
      (tx) => tx.get('PRAGMA user_version'),
    );
    final probedVersion = probe['user_version'] as int;
    if (probedVersion == _databaseVersion) {
      return;
    }
    if (probedVersion > _databaseVersion) {
      throw StateError(
        'Contacts database version $probedVersion is newer than supported '
        'version $_databaseVersion',
      );
    }
    final didMigrate = await database.writeTransaction((tx) async {
      final result = await tx.get('PRAGMA user_version');
      final currentVersion = result['user_version'] as int;
      if (currentVersion == _databaseVersion) {
        return false;
      }
      if (currentVersion > _databaseVersion) {
        throw StateError(
          'Contacts database version $currentVersion is newer than supported '
          'version $_databaseVersion',
        );
      }

      if (currentVersion < 1) {
        await tx.execute('''
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
        await tx.execute(
          'CREATE UNIQUE INDEX idx_contacts_contact_user_id '
          'ON $_contactsTable(contact_user_id)',
        );
        await tx.execute(
          'CREATE INDEX idx_contacts_updated_at '
          'ON $_contactsTable(updated_at)',
        );
        await tx.execute('''
          CREATE TABLE $_attachmentsTable (
            attachment_id TEXT PRIMARY KEY,
            bytes BLOB NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
        await tx.execute('''
          CREATE TABLE $_stateTable (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_synced_updated_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await tx.execute(
          'INSERT INTO $_stateTable (id, last_synced_updated_at) VALUES (1, 0)',
        );
      }
      await tx.execute('PRAGMA user_version = $_databaseVersion');
      return true;
    });
    if (didMigrate) {
      await database.refreshSchema();
    }
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
      name: dataJson == null
          ? null
          : (jsonDecode(dataJson) as Map<String, dynamic>)['name'] as String,
      profilePictureAttachmentId:
          row['profile_picture_attachment_id'] as String?,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
      createdAt: row['created_at']! as int,
      updatedAt: row['updated_at']! as int,
    );
  }

  List<Object?> _contactParameters(ContactRecord contact) => [
    contact.id,
    contact.contactUserId,
    contact.email,
    contact.name == null
        ? null
        : jsonEncode({
            'contactUserId': contact.contactUserId,
            'name': contact.name,
          }),
    contact.profilePictureAttachmentId,
    contact.isDeleted ? 1 : 0,
    contact.createdAt,
    contact.updatedAt,
  ];
}
