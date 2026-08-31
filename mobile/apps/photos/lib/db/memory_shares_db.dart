import 'package:photos/db/common/base.dart';
import 'package:photos/models/api/memory_share/memory_share.dart';
import 'package:sqlite_async/sqlite_async.dart';

class MemorySharesDB with SqlDbBase {
  static const _databaseName = "ente.memory_shares.db";

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

  static const _migrationScripts = [
    '''
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
    ''',
  ];

  MemorySharesDB._();
  static final MemorySharesDB instance = MemorySharesDB._();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(_databaseName, _migrationScripts),
  );

  Future<void> upsert(MemoryShare share) async {
    final db = await database;
    await db.execute('''
      INSERT OR REPLACE INTO $_table (
        $_columnID, $_columnType, $_columnMetadataCipher,
        $_columnMetadataNonce, $_columnMemEncKey,
        $_columnMemKeyDecryptionNonce, $_columnAccessToken,
        $_columnIsDeleted, $_columnCreatedAt, $_columnUpdatedAt, $_columnUrl,
        $_columnMemoryHash, $_columnPreviewUploadedFileID, $_columnFileCount
      ) VALUES (${SqlDbBase.getParams(14)})
      ''', _toParameters(share));
  }

  Future<List<MemoryShare>> getAll() async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT * FROM $_table WHERE $_columnIsDeleted = 0 ORDER BY $_columnCreatedAt DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<MemoryShare?> getById(int id) async {
    final db = await database;
    final rows = await db.getAll('SELECT * FROM $_table WHERE $_columnID = ?', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<MemoryShare?> getByMemoryHash(String memoryHash) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_table
      WHERE $_columnMemoryHash = ? AND $_columnIsDeleted = 0
      ORDER BY $_columnCreatedAt DESC
      LIMIT 1
      ''',
      [memoryHash],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.execute('DELETE FROM $_table WHERE $_columnID = ?', [id]);
  }

  Future<void> clearTable() async {
    final db = await database;
    await db.execute('DELETE FROM $_table');
  }

  List<Object?> _toParameters(MemoryShare share) {
    return [
      share.id,
      share.type.name,
      share.metadataCipher,
      share.metadataNonce,
      share.encryptedKey,
      share.keyDecryptionNonce,
      share.accessToken,
      share.isDeleted ? 1 : 0,
      share.createdAt,
      share.updatedAt,
      share.url,
      share.memoryHash,
      share.previewUploadedFileID,
      share.fileCount,
    ];
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
