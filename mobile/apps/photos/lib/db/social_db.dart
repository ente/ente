import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photos/db/common/base.dart';
import 'package:photos/models/social/anon_profile.dart';
import 'package:photos/models/social/comment.dart';
import 'package:photos/models/social/reaction.dart';
import 'package:sqlite_async/sqlite_async.dart';

class SocialDB with SqlDbBase {
  static final Logger _logger = Logger("SocialDB");
  static const _databaseName = "ente.social.db";

  static const _commentsTable = 'comments';
  static const _reactionsTable = 'reactions';
  static const _syncTimeTable = 'sync_time';
  static const _anonProfilesTable = 'anon_profiles';

  static const _upsertCommentSql =
      '''
    INSERT OR REPLACE INTO $_commentsTable (
      id, collection_id, file_id, data, parent_comment_id,
      parent_comment_user_id, is_deleted, user_id, anon_user_id,
      created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''';

  static const _upsertReactionSql =
      '''
    INSERT OR REPLACE INTO $_reactionsTable (
      id, collection_id, file_id, comment_id, data, is_deleted, user_id,
      anon_user_id, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ''';

  static const _upsertAnonProfileSql =
      '''
    INSERT OR REPLACE INTO $_anonProfilesTable (
      anon_user_id, collection_id, data, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?)
  ''';

  static const _migrationScripts = [
    '''
      CREATE TABLE $_commentsTable (
        id TEXT PRIMARY KEY NOT NULL,
        collection_id INTEGER NOT NULL,
        file_id INTEGER,
        data TEXT NOT NULL,
        parent_comment_id TEXT,
        parent_comment_user_id INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        user_id INTEGER NOT NULL,
        anon_user_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE $_reactionsTable (
        id TEXT PRIMARY KEY NOT NULL,
        collection_id INTEGER NOT NULL,
        file_id INTEGER,
        comment_id TEXT,
        data TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        user_id INTEGER NOT NULL,
        anon_user_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE $_syncTimeTable (
        collection_id INTEGER PRIMARY KEY NOT NULL,
        comments_sync_time INTEGER NOT NULL DEFAULT 0,
        reactions_sync_time INTEGER NOT NULL DEFAULT 0,
        anon_profiles_sync_time INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE $_anonProfilesTable (
        anon_user_id TEXT NOT NULL,
        collection_id INTEGER NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (anon_user_id, collection_id)
      );
      CREATE INDEX idx_comments_file_collection
        ON $_commentsTable(file_id, collection_id);
      CREATE INDEX idx_reactions_file_collection
        ON $_reactionsTable(file_id, collection_id);
    ''',
  ];

  SocialDB._();
  static final SocialDB instance = SocialDB._();

  Future<SqliteDatabase> get database => getOrOpenDatabase(
    () => openMigratedDatabase(
      _databaseName,
      _migrationScripts,
      logPath: (path) => _logger.info("DB path: $path"),
    ),
  );

  Future<void> addComment(Comment comment) async {
    final db = await database;
    await db.execute(_upsertCommentSql, _commentToParameters(comment));
  }

  Future<Comment?> deleteComment(String id) async {
    final db = await database;
    final rows = await db.getAll('SELECT * FROM $_commentsTable WHERE id = ?', [
      id,
    ]);

    if (rows.isEmpty) {
      debugPrint('deleteComment: Comment $id does not exist');
      return null;
    }

    final updatedAt = DateTime.now().microsecondsSinceEpoch;
    final updatedRows = await db.execute(
      '''
      UPDATE $_commentsTable
      SET is_deleted = 1, updated_at = ?
      WHERE id = ?
      RETURNING *
      ''',
      [updatedAt, id],
    );
    return _rowToComment(updatedRows.first);
  }

  Future<List<Comment>> getCommentsForFile(int fileID) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT * FROM $_commentsTable WHERE file_id = ? AND is_deleted = 0',
      [fileID],
    );
    return rows.map(_rowToComment).toList();
  }

  // Candidate collections let the file/collection index narrow this lookup.
  Future<Comment?> getLatestCommentForFile(
    int fileID, {
    required List<int> candidateCollectionIDs,
  }) async {
    if (candidateCollectionIDs.isEmpty) {
      return null;
    }

    final placeholders = List.filled(
      candidateCollectionIDs.length,
      '?',
    ).join(',');
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE file_id = ? AND is_deleted = 0
        AND collection_id IN ($placeholders)
      ORDER BY created_at DESC
      LIMIT 1
      ''',
      [fileID, ...candidateCollectionIDs],
    );
    return rows.isEmpty ? null : _rowToComment(rows.first);
  }

  Future<int> getCommentCountForFileInCollections(
    int fileID,
    List<int> collectionIDs,
  ) async {
    if (collectionIDs.isEmpty) {
      return 0;
    }

    final placeholders = List.filled(collectionIDs.length, '?').join(',');
    final db = await database;
    final result = await db.getAll(
      'SELECT COUNT(*) as count FROM $_commentsTable '
      'WHERE file_id = ? AND collection_id IN ($placeholders) '
      'AND is_deleted = 0',
      [fileID, ...collectionIDs],
    );
    return result.first['count'] as int;
  }

  Future<int> getCommentCountForFileInCollection(
    int fileID,
    int collectionID,
  ) async {
    final db = await database;
    final result = await db.getAll(
      'SELECT COUNT(*) as count FROM $_commentsTable '
      'WHERE file_id = ? AND collection_id = ? AND is_deleted = 0',
      [fileID, collectionID],
    );
    return result.first['count'] as int;
  }

  Future<List<Comment>> getCommentsForCollection(int collectionID) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE collection_id = ? AND file_id IS NULL AND is_deleted = 0
      ''',
      [collectionID],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Comment>> getRepliesForComment(String commentID) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE parent_comment_id = ? AND is_deleted = 0
      ''',
      [commentID],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<Comment?> getCommentById(String id) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT * FROM $_commentsTable WHERE id = ? AND is_deleted = 0',
      [id],
    );
    if (rows.isEmpty) return null;
    return _rowToComment(rows.first);
  }

  Future<Map<String, Comment>> getCommentsByIds(Iterable<String> ids) async {
    final idList = ids.toList();
    if (idList.isEmpty) return {};

    final placeholders = List.filled(idList.length, '?').join(',');
    final db = await database;
    final rows = await db.getAll('''
      SELECT * FROM $_commentsTable
      WHERE id IN ($placeholders) AND is_deleted = 0
      ''', idList);

    return {for (final row in rows) (row['id'] as String): _rowToComment(row)};
  }

  Future<List<Comment>> getCommentsForFilePaginated(
    int fileID, {
    required int collectionID,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE file_id = ? AND collection_id = ? AND is_deleted = 0
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [fileID, collectionID, limit, offset],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Comment>> getCommentsForCollectionPaginated(
    int collectionID, {
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE collection_id = ? AND file_id IS NULL AND is_deleted = 0
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [collectionID, limit, offset],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Reaction>> getReactionsForFile(int fileID) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_reactionsTable
      WHERE file_id = ? AND comment_id IS NULL AND is_deleted = 0
      ''',
      [fileID],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<bool> hasUserReactedToFileInCollections(
    int fileID,
    int userID,
    List<int> collectionIDs,
  ) async {
    if (collectionIDs.isEmpty) {
      return false;
    }

    final placeholders = List.filled(collectionIDs.length, '?').join(',');
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT 1 FROM $_reactionsTable
      WHERE file_id = ? AND user_id = ?
        AND collection_id IN ($placeholders)
        AND comment_id IS NULL AND is_deleted = 0
      LIMIT 1
      ''',
      [fileID, userID, ...collectionIDs],
    );
    return rows.isNotEmpty;
  }

  Future<List<Reaction>> getReactionsForFileInCollection(
    int fileID,
    int collectionID,
  ) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_reactionsTable
      WHERE file_id = ? AND collection_id = ?
        AND comment_id IS NULL AND is_deleted = 0
      ''',
      [fileID, collectionID],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Reaction>> getReactionsForComment(String commentID) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT * FROM $_reactionsTable WHERE comment_id = ? AND is_deleted = 0',
      [commentID],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Reaction>> getReactionsForCollection(int collectionID) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_reactionsTable
      WHERE collection_id = ? AND file_id IS NULL
        AND comment_id IS NULL AND is_deleted = 0
      ''',
      [collectionID],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<int> getCommentsSyncTime(int collectionID) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT comments_sync_time FROM $_syncTimeTable WHERE collection_id = ?',
      [collectionID],
    );
    if (rows.isEmpty) return 0;
    return rows.first['comments_sync_time'] as int? ?? 0;
  }

  Future<int> getReactionsSyncTime(int collectionID) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT reactions_sync_time FROM $_syncTimeTable WHERE collection_id = ?',
      [collectionID],
    );
    if (rows.isEmpty) return 0;
    return rows.first['reactions_sync_time'] as int? ?? 0;
  }

  Future<void> setCommentsSyncTime(int collectionID, int syncTime) async {
    final db = await database;
    await db.execute(
      '''
      INSERT INTO $_syncTimeTable (collection_id, comments_sync_time)
      VALUES (?, ?)
      ON CONFLICT(collection_id) DO UPDATE SET comments_sync_time = excluded.comments_sync_time
      ''',
      [collectionID, syncTime],
    );
  }

  Future<void> setReactionsSyncTime(int collectionID, int syncTime) async {
    final db = await database;
    await db.execute(
      '''
      INSERT INTO $_syncTimeTable (collection_id, reactions_sync_time)
      VALUES (?, ?)
      ON CONFLICT(collection_id) DO UPDATE SET reactions_sync_time = excluded.reactions_sync_time
      ''',
      [collectionID, syncTime],
    );
  }

  Future<void> clearSyncTime(int collectionID) async {
    final db = await database;
    await db.execute('DELETE FROM $_syncTimeTable WHERE collection_id = ?', [
      collectionID,
    ]);
  }

  Future<int> getAnonProfilesSyncTime(int collectionID) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT anon_profiles_sync_time FROM $_syncTimeTable WHERE collection_id = ?',
      [collectionID],
    );
    if (rows.isEmpty) return 0;
    return rows.first['anon_profiles_sync_time'] as int? ?? 0;
  }

  Future<void> setAnonProfilesSyncTime(int collectionID, int syncTime) async {
    final db = await database;
    await db.execute(
      '''
      INSERT INTO $_syncTimeTable (collection_id, anon_profiles_sync_time)
      VALUES (?, ?)
      ON CONFLICT(collection_id) DO UPDATE SET anon_profiles_sync_time = excluded.anon_profiles_sync_time
      ''',
      [collectionID, syncTime],
    );
  }

  Future<void> upsertComments(List<Comment> comments) async {
    if (comments.isEmpty) return;
    final db = await database;
    await db.executeBatch(_upsertCommentSql, [
      for (final comment in comments) _commentToParameters(comment),
    ]);
  }

  Future<void> resolveParentCommentUserIDs(int collectionID) async {
    final db = await database;
    await db.execute(
      '''
      UPDATE $_commentsTable SET parent_comment_user_id = (
        SELECT c2.user_id FROM $_commentsTable c2
        WHERE c2.id = $_commentsTable.parent_comment_id
      )
      WHERE collection_id = ?
        AND parent_comment_id IS NOT NULL
        AND parent_comment_user_id IS NULL
      ''',
      [collectionID],
    );
  }

  Future<void> upsertReactions(List<Reaction> reactions) async {
    if (reactions.isEmpty) return;
    final db = await database;
    await db.executeBatch(_upsertReactionSql, [
      for (final reaction in reactions) _reactionToParameters(reaction),
    ]);
  }

  Future<void> upsertAnonProfiles(List<AnonProfile> profiles) async {
    if (profiles.isEmpty) return;
    final db = await database;
    await db.executeBatch(_upsertAnonProfileSql, [
      for (final profile in profiles) _anonProfileToParameters(profile),
    ]);
  }

  Future<List<AnonProfile>> getAnonProfilesForCollection(
    int collectionID,
  ) async {
    final db = await database;
    final rows = await db.getAll(
      'SELECT * FROM $_anonProfilesTable WHERE collection_id = ?',
      [collectionID],
    );
    return rows.map(_rowToAnonProfile).toList();
  }

  Future<AnonProfile?> getAnonProfile(
    String anonUserID,
    int collectionID,
  ) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_anonProfilesTable
      WHERE anon_user_id = ? AND collection_id = ?
      ''',
      [anonUserID, collectionID],
    );
    if (rows.isEmpty) return null;
    return _rowToAnonProfile(rows.first);
  }

  Future<List<Reaction>> getReactionsOnFiles({
    required int excludeUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_reactionsTable
      WHERE file_id IS NOT NULL AND comment_id IS NULL
        AND is_deleted = 0 AND user_id != ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [excludeUserID, limit, offset],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Comment>> getCommentsOnFiles({
    required int excludeUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE file_id IS NOT NULL AND parent_comment_id IS NULL
        AND is_deleted = 0 AND user_id != ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [excludeUserID, limit, offset],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Comment>> getReplies({
    required int excludeUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE parent_comment_id IS NOT NULL AND is_deleted = 0 AND user_id != ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [excludeUserID, limit, offset],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Reaction>> getReactionsOnUserComments({
    required int targetUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT r.* FROM $_reactionsTable r
      INNER JOIN $_commentsTable c ON r.comment_id = c.id
      WHERE r.comment_id IS NOT NULL AND r.is_deleted = 0 AND r.user_id != ?
        AND c.is_deleted = 0 AND c.parent_comment_id IS NULL
      ORDER BY r.created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [targetUserID, limit, offset],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Reaction>> getReactionsOnUserReplies({
    required int targetUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT r.* FROM $_reactionsTable r
      INNER JOIN $_commentsTable c ON r.comment_id = c.id
      WHERE r.comment_id IS NOT NULL AND r.is_deleted = 0 AND r.user_id != ?
        AND c.is_deleted = 0 AND c.parent_comment_id IS NOT NULL
      ORDER BY r.created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [targetUserID, limit, offset],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Reaction>> getReactionsOnFilesSince({
    required int excludeUserID,
    required int sinceTime,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_reactionsTable
      WHERE file_id IS NOT NULL AND comment_id IS NULL
        AND is_deleted = 0 AND user_id != ? AND created_at > ?
      ORDER BY created_at DESC
      ''',
      [excludeUserID, sinceTime],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Comment>> getCommentsOnFilesSince({
    required int excludeUserID,
    required int sinceTime,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE file_id IS NOT NULL AND parent_comment_id IS NULL
        AND is_deleted = 0 AND user_id != ? AND created_at > ?
      ORDER BY created_at DESC
      ''',
      [excludeUserID, sinceTime],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Comment>> getRepliesSince({
    required int excludeUserID,
    required int sinceTime,
  }) async {
    final db = await database;
    final rows = await db.getAll(
      '''
      SELECT * FROM $_commentsTable
      WHERE parent_comment_id IS NOT NULL AND is_deleted = 0
        AND user_id != ? AND created_at > ?
      ORDER BY created_at DESC
      ''',
      [excludeUserID, sinceTime],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<void> deleteCollectionData(int collectionID) async {
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $_commentsTable WHERE collection_id = ?', [
        collectionID,
      ]);
      await tx.execute('DELETE FROM $_reactionsTable WHERE collection_id = ?', [
        collectionID,
      ]);
      await tx.execute(
        'DELETE FROM $_anonProfilesTable WHERE collection_id = ?',
        [collectionID],
      );
      await tx.execute('DELETE FROM $_syncTimeTable WHERE collection_id = ?', [
        collectionID,
      ]);
    });
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $_commentsTable');
      await tx.execute('DELETE FROM $_reactionsTable');
      await tx.execute('DELETE FROM $_anonProfilesTable');
      await tx.execute('DELETE FROM $_syncTimeTable');
    });
  }

  Future<int> deleteAllComments() async {
    final db = await database;
    return db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $_commentsTable');
      final row = await tx.get('SELECT changes() AS count');
      return row['count'] as int;
    });
  }

  Future<int> deleteAllReactions() async {
    final db = await database;
    return db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM $_reactionsTable');
      final row = await tx.get('SELECT changes() AS count');
      return row['count'] as int;
    });
  }

  Future<void> seedExampleData() async {}

  List<Object?> _commentToParameters(Comment comment) => [
    comment.id,
    comment.collectionID,
    comment.fileID,
    comment.data,
    comment.parentCommentID,
    comment.parentCommentUserID,
    comment.isDeleted ? 1 : 0,
    comment.userID,
    comment.anonUserID,
    comment.createdAt,
    comment.updatedAt,
  ];

  Comment _rowToComment(Map<String, dynamic> row) {
    return Comment(
      id: row['id'] as String,
      collectionID: row['collection_id'] as int,
      fileID: row['file_id'] as int?,
      data: row['data'] as String,
      parentCommentID: row['parent_comment_id'] as String?,
      parentCommentUserID: row['parent_comment_user_id'] as int?,
      isDeleted: row['is_deleted'] == 1,
      userID: row['user_id'] as int,
      anonUserID: row['anon_user_id'] as String?,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }

  List<Object?> _reactionToParameters(Reaction reaction) => [
    reaction.id,
    reaction.collectionID,
    reaction.fileID,
    reaction.commentID,
    reaction.data,
    reaction.isDeleted ? 1 : 0,
    reaction.userID,
    reaction.anonUserID,
    reaction.createdAt,
    reaction.updatedAt,
  ];

  Reaction _rowToReaction(Map<String, dynamic> row) {
    return Reaction(
      id: row['id'] as String,
      collectionID: row['collection_id'] as int,
      fileID: row['file_id'] as int?,
      commentID: row['comment_id'] as String?,
      data: row['data'] as String,
      isDeleted: row['is_deleted'] == 1,
      userID: row['user_id'] as int,
      anonUserID: row['anon_user_id'] as String?,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }

  List<Object?> _anonProfileToParameters(AnonProfile profile) => [
    profile.anonUserID,
    profile.collectionID,
    profile.data,
    profile.createdAt,
    profile.updatedAt,
  ];

  AnonProfile _rowToAnonProfile(Map<String, dynamic> row) {
    return AnonProfile(
      anonUserID: row['anon_user_id'] as String,
      collectionID: row['collection_id'] as int,
      data: row['data'] as String,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}
