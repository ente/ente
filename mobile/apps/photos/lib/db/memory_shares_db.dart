import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/models/api/memory_share/memory_share.dart';
import 'package:sqflite/sqflite.dart';

class MemorySharesDB {
  static const _databaseName = "ente.memory_shares.db";
  static const _databaseVersion = 1;

  static const _table = 'memory_shares';

  static const _columnID = 'id';
  static const _columnType = 'type';
  static const _columnMetadataCipher = 'metadata_cipher';
  static const _columnMetadataNonce = 'metadata_nonce';
  static const _columnMemEncKey = 'mem_enc_key';
  static const _columnMemKeyDecryptionNonce = 'mem_key_decryption_nonce';
  static const _columnAccessToken = 'access_token';
  static const _columnIsDeleted = 'is_deleted';
  static const _columnCreatedAt = 'created_at';
  static const _columnUpdatedAt = 'updated_at';
  static const _columnUrl = 'url';
  static const _columnMemoryHash = 'memory_hash';
  static const _columnPreviewUploadedFileID = 'preview_uploaded_file_id';
  static const _columnFileCount = 'file_count';

  MemorySharesDB._();
  static final MemorySharesDB instance = MemorySharesDB._();

  static Future<Database>? _dbFuture;

  Future<Database> get database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_table (
        $_columnID INTEGER PRIMARY KEY NOT NULL,
        $_columnType TEXT NOT NULL,
        $_columnMetadataCipher TEXT,
        $_columnMetadataNonce TEXT,
        $_columnMemEncKey TEXT NOT NULL,
        $_columnMemKeyDecryptionNonce TEXT NOT NULL,
        $_columnAccessToken TEXT NOT NULL,
        $_columnIsDeleted INTEGER NOT NULL DEFAULT 0,
        $_columnCreatedAt INTEGER NOT NULL,
        $_columnUpdatedAt INTEGER,
        $_columnUrl TEXT NOT NULL,
        $_columnMemoryHash TEXT,
        $_columnPreviewUploadedFileID INTEGER,
        $_columnFileCount INTEGER
      )
    ''');
  }

  Future<void> upsert(MemoryShare share) async {
    final db = await database;
    await db.insert(
      _table,
      _toRow(share),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MemoryShare>> getAll() async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: '$_columnIsDeleted = 0',
      orderBy: '$_columnCreatedAt DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<MemoryShare?> getById(int id) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: '$_columnID = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<MemoryShare?> getByMemoryHash(String memoryHash) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: '$_columnMemoryHash = ? AND $_columnIsDeleted = 0',
      whereArgs: [memoryHash],
      orderBy: '$_columnCreatedAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(_table, where: '$_columnID = ?', whereArgs: [id]);
  }

  Future<void> clearTable() async {
    final db = await database;
    await db.delete(_table);
  }

  Map<String, dynamic> _toRow(MemoryShare share) {
    return {
      _columnID: share.id,
      _columnType: share.type.name,
      _columnMetadataCipher: share.metadataCipher,
      _columnMetadataNonce: share.metadataNonce,
      _columnMemEncKey: share.encryptedKey,
      _columnMemKeyDecryptionNonce: share.keyDecryptionNonce,
      _columnAccessToken: share.accessToken,
      _columnIsDeleted: share.isDeleted ? 1 : 0,
      _columnCreatedAt: share.createdAt,
      _columnUpdatedAt: share.updatedAt,
      _columnUrl: share.url,
      _columnMemoryHash: share.memoryHash,
      _columnPreviewUploadedFileID: share.previewUploadedFileID,
      _columnFileCount: share.fileCount,
    };
  }

  MemoryShare _fromRow(Map<String, dynamic> row) {
    return MemoryShare(
      id: row[_columnID] as int,
      type: MemoryShareType.fromString(row[_columnType] as String),
      metadataCipher: row[_columnMetadataCipher] as String?,
      metadataNonce: row[_columnMetadataNonce] as String?,
      encryptedKey: row[_columnMemEncKey] as String,
      keyDecryptionNonce: row[_columnMemKeyDecryptionNonce] as String,
      accessToken: row[_columnAccessToken] as String,
      isDeleted: (row[_columnIsDeleted] as int) == 1,
      createdAt: row[_columnCreatedAt] as int,
      updatedAt: row[_columnUpdatedAt] as int?,
      url: row[_columnUrl] as String,
      memoryHash: row[_columnMemoryHash] as String?,
      previewUploadedFileID: row[_columnPreviewUploadedFileID] as int?,
      fileCount: row[_columnFileCount] as int?,
    );
  }
}
