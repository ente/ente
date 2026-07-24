import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/models/social/anon_profile.dart';
import 'package:photos/models/social/comment.dart';
import 'package:photos/models/social/reaction.dart';
import 'package:sqflite/sqflite.dart';

class SocialDB {
  static final Logger _logger = Logger("SocialDB");
  static const _databaseName = "ente.social.db";
  static const _databaseVersion = 1;

  static const _commentsTable = 'comments';
  static const _reactionsTable = 'reactions';
  static const _syncTimeTable = 'sync_time';
  static const _anonProfilesTable = 'anon_profiles';

  SocialDB._();
  static final SocialDB instance = SocialDB._();

  static Future<Database>? _dbFuture;

  Future<Database> get database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    _logger.info("DB path: $path");
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
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
      )
    ''');

    await db.execute('''
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
      )
    ''');

    await db.execute('''
      CREATE TABLE $_syncTimeTable (
        collection_id INTEGER PRIMARY KEY NOT NULL,
        comments_sync_time INTEGER NOT NULL DEFAULT 0,
        reactions_sync_time INTEGER NOT NULL DEFAULT 0,
        anon_profiles_sync_time INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $_anonProfilesTable (
        anon_user_id TEXT NOT NULL,
        collection_id INTEGER NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (anon_user_id, collection_id)
      )
    ''');

    // Create indexes for common queries
    await db.execute(
      'CREATE INDEX idx_comments_file_collection ON $_commentsTable(file_id, collection_id)',
    );
    await db.execute(
      'CREATE INDEX idx_reactions_file_collection ON $_reactionsTable(file_id, collection_id)',
    );
  }

  // ============ Comment Methods ============

  Future<void> addComment(Comment comment) async {
    final db = await database;
    await db.insert(
      _commentsTable,
      _commentToRow(comment),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Comment?> deleteComment(String id) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (rows.isEmpty) {
      debugPrint('deleteComment: Comment $id does not exist');
      return null;
    }

    final updatedAt = DateTime.now().microsecondsSinceEpoch;
    await db.update(
      _commentsTable,
      {'is_deleted': 1, 'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [id],
    );

    final updatedRows = await db.query(
      _commentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return _rowToComment(updatedRows.first);
  }

  Future<List<Comment>> getCommentsForFile(int fileID) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'file_id = ? AND is_deleted = 0',
      whereArgs: [fileID],
    );
    return rows.map(_rowToComment).toList();
  }

  /// Restricts the lookup to [candidateCollectionIDs] so the composite
  /// file/collection index can narrow the rows considered for the latest item.
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
    final rows = await db.query(
      _commentsTable,
      where:
          'file_id = ? AND is_deleted = 0 '
          'AND collection_id IN ($placeholders)',
      whereArgs: [fileID, ...candidateCollectionIDs],
      orderBy: 'created_at DESC',
      limit: 1,
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
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_commentsTable '
      'WHERE file_id = ? AND collection_id IN ($placeholders) '
      'AND is_deleted = 0',
      [fileID, ...collectionIDs],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getCommentCountForFileInCollection(
    int fileID,
    int collectionID,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_commentsTable '
      'WHERE file_id = ? AND collection_id = ? AND is_deleted = 0',
      [fileID, collectionID],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Comment>> getCommentsForCollection(int collectionID) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'collection_id = ? AND file_id IS NULL AND is_deleted = 0',
      whereArgs: [collectionID],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Comment>> getRepliesForComment(String commentID) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'parent_comment_id = ? AND is_deleted = 0',
      whereArgs: [commentID],
    );
    return rows.map(_rowToComment).toList();
  }

  Future<Comment?> getCommentById(String id) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _rowToComment(rows.first);
  }

  Future<Map<String, Comment>> getCommentsByIds(Iterable<String> ids) async {
    final idList = ids.toList();
    if (idList.isEmpty) return {};

    final placeholders = List.filled(idList.length, '?').join(',');
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'id IN ($placeholders) AND is_deleted = 0',
      whereArgs: idList,
    );

    return {for (final row in rows) (row['id'] as String): _rowToComment(row)};
  }

  Future<List<Comment>> getCommentsForFilePaginated(
    int fileID, {
    required int collectionID,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'file_id = ? AND collection_id = ? AND is_deleted = 0',
      whereArgs: [fileID, collectionID],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_rowToComment).toList();
  }

  Future<List<Comment>> getCommentsForCollectionPaginated(
    int collectionID, {
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where: 'collection_id = ? AND file_id IS NULL AND is_deleted = 0',
      whereArgs: [collectionID],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_rowToComment).toList();
  }

  // ============ Reaction Methods ============

  Future<List<Reaction>> getReactionsForFile(int fileID) async {
    final db = await database;
    final rows = await db.query(
      _reactionsTable,
      where: 'file_id = ? AND comment_id IS NULL AND is_deleted = 0',
      whereArgs: [fileID],
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
    final rows = await db.rawQuery(
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
    final rows = await db.query(
      _reactionsTable,
      where:
          'file_id = ? AND collection_id = ? AND comment_id IS NULL AND is_deleted = 0',
      whereArgs: [fileID, collectionID],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Reaction>> getReactionsForComment(String commentID) async {
    final db = await database;
    final rows = await db.query(
      _reactionsTable,
      where: 'comment_id = ? AND is_deleted = 0',
      whereArgs: [commentID],
    );
    return rows.map(_rowToReaction).toList();
  }

  Future<List<Reaction>> getReactionsForCollection(int collectionID) async {
    final db = await database;
    final rows = await db.query(
      _reactionsTable,
      where:
          'collection_id = ? AND file_id IS NULL AND comment_id IS NULL AND is_deleted = 0',
      whereArgs: [collectionID],
    );
    return rows.map(_rowToReaction).toList();
  }

  // ============ Sync Time Methods ============

  Future<int> getCommentsSyncTime(int collectionID) async {
    final db = await database;
    final rows = await db.query(
      _syncTimeTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    if (rows.isEmpty) return 0;
    return rows.first['comments_sync_time'] as int? ?? 0;
  }

  Future<int> getReactionsSyncTime(int collectionID) async {
    final db = await database;
    final rows = await db.query(
      _syncTimeTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    if (rows.isEmpty) return 0;
    return rows.first['reactions_sync_time'] as int? ?? 0;
  }

  Future<void> setCommentsSyncTime(int collectionID, int syncTime) async {
    final db = await database;
    await db.insert(_syncTimeTable, {
      'collection_id': collectionID,
      'comments_sync_time': syncTime,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setReactionsSyncTime(int collectionID, int syncTime) async {
    final db = await database;
    await db.insert(_syncTimeTable, {
      'collection_id': collectionID,
      'reactions_sync_time': syncTime,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearSyncTime(int collectionID) async {
    final db = await database;
    await db.delete(
      _syncTimeTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
  }

  Future<int> getAnonProfilesSyncTime(int collectionID) async {
    final db = await database;
    final rows = await db.query(
      _syncTimeTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    if (rows.isEmpty) return 0;
    return rows.first['anon_profiles_sync_time'] as int? ?? 0;
  }

  Future<void> setAnonProfilesSyncTime(int collectionID, int syncTime) async {
    final db = await database;
    // First check if the row exists
    final rows = await db.query(
      _syncTimeTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    if (rows.isEmpty) {
      await db.insert(_syncTimeTable, {
        'collection_id': collectionID,
        'anon_profiles_sync_time': syncTime,
      });
    } else {
      await db.update(
        _syncTimeTable,
        {'anon_profiles_sync_time': syncTime},
        where: 'collection_id = ?',
        whereArgs: [collectionID],
      );
    }
  }

  // ============ Bulk Upsert Methods ============

  Future<void> upsertComments(List<Comment> comments) async {
    if (comments.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final comment in comments) {
      batch.insert(
        _commentsTable,
        _commentToRow(comment),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Resolves `parent_comment_user_id` for reply comments by looking up the
  /// parent comment's `user_id`. Only processes rows where the field is still
  /// NULL, making it idempotent.
  Future<void> resolveParentCommentUserIDs(int collectionID) async {
    final db = await database;
    await db.rawUpdate(
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
    final batch = db.batch();
    for (final reaction in reactions) {
      batch.insert(
        _reactionsTable,
        _reactionToRow(reaction),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ============ Anon Profile Methods ============

  Future<void> upsertAnonProfiles(List<AnonProfile> profiles) async {
    if (profiles.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final profile in profiles) {
      batch.insert(
        _anonProfilesTable,
        _anonProfileToRow(profile),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<AnonProfile>> getAnonProfilesForCollection(
    int collectionID,
  ) async {
    final db = await database;
    final rows = await db.query(
      _anonProfilesTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    return rows.map(_rowToAnonProfile).toList();
  }

  Future<AnonProfile?> getAnonProfile(
    String anonUserID,
    int collectionID,
  ) async {
    final db = await database;
    final rows = await db.query(
      _anonProfilesTable,
      where: 'anon_user_id = ? AND collection_id = ?',
      whereArgs: [anonUserID, collectionID],
    );
    if (rows.isEmpty) return null;
    return _rowToAnonProfile(rows.first);
  }

  // ============ Feed Query Methods ============

  /// Gets all reactions on files (photo likes) excluding the current user's reactions.
  /// Returns reactions sorted by created_at DESC.
  Future<List<Reaction>> getReactionsOnFiles({
    required int excludeUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      _reactionsTable,
      where:
          'file_id IS NOT NULL AND comment_id IS NULL AND is_deleted = 0 AND user_id != ?',
      whereArgs: [excludeUserID],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_rowToReaction).toList();
  }

  /// Gets all comments on files excluding the current user's comments.
  /// Returns comments sorted by created_at DESC.
  Future<List<Comment>> getCommentsOnFiles({
    required int excludeUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where:
          'file_id IS NOT NULL AND parent_comment_id IS NULL AND is_deleted = 0 AND user_id != ?',
      whereArgs: [excludeUserID],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_rowToComment).toList();
  }

  /// Gets all replies to comments, excluding the current user's own replies.
  /// Returns replies sorted by created_at DESC.
  Future<List<Comment>> getReplies({
    required int excludeUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    // Get all replies excluding the current user's own replies
    final rows = await db.query(
      _commentsTable,
      where:
          'parent_comment_id IS NOT NULL AND is_deleted = 0 AND user_id != ?',
      whereArgs: [excludeUserID],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_rowToComment).toList();
  }

  /// Gets all reactions on top-level comments, excluding the current user's reactions.
  /// Returns reactions sorted by created_at DESC.
  Future<List<Reaction>> getReactionsOnUserComments({
    required int targetUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    // Get all reactions on comments (not on files) excluding current user's
    // Join to ensure we only get reactions on top-level comments (not replies)
    final rows = await db.rawQuery(
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

  /// Gets all reactions on replies, excluding the current user's reactions.
  /// Returns reactions sorted by created_at DESC.
  Future<List<Reaction>> getReactionsOnUserReplies({
    required int targetUserID,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    // Get all reactions on replies excluding current user's
    final rows = await db.rawQuery(
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

  /// Gets all reactions on files after [sinceTime], excluding the current user.
  /// Returns reactions sorted by created_at DESC.
  Future<List<Reaction>> getReactionsOnFilesSince({
    required int excludeUserID,
    required int sinceTime,
  }) async {
    final db = await database;
    final rows = await db.query(
      _reactionsTable,
      where:
          'file_id IS NOT NULL AND comment_id IS NULL '
          'AND is_deleted = 0 AND user_id != ? AND created_at > ?',
      whereArgs: [excludeUserID, sinceTime],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToReaction).toList();
  }

  /// Gets all comments on files after [sinceTime], excluding the current user.
  /// Returns comments sorted by created_at DESC.
  Future<List<Comment>> getCommentsOnFilesSince({
    required int excludeUserID,
    required int sinceTime,
  }) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where:
          'file_id IS NOT NULL AND parent_comment_id IS NULL '
          'AND is_deleted = 0 AND user_id != ? AND created_at > ?',
      whereArgs: [excludeUserID, sinceTime],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToComment).toList();
  }

  /// Gets all replies after [sinceTime], excluding the current user.
  /// Returns replies sorted by created_at DESC.
  Future<List<Comment>> getRepliesSince({
    required int excludeUserID,
    required int sinceTime,
  }) async {
    final db = await database;
    final rows = await db.query(
      _commentsTable,
      where:
          'parent_comment_id IS NOT NULL AND is_deleted = 0 '
          'AND user_id != ? AND created_at > ?',
      whereArgs: [excludeUserID, sinceTime],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToComment).toList();
  }

  // ============ Cleanup Methods ============

  Future<void> deleteCollectionData(int collectionID) async {
    final db = await database;
    await db.delete(
      _commentsTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    await db.delete(
      _reactionsTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    await db.delete(
      _anonProfilesTable,
      where: 'collection_id = ?',
      whereArgs: [collectionID],
    );
    await clearSyncTime(collectionID);
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete(_commentsTable);
    await db.delete(_reactionsTable);
    await db.delete(_anonProfilesTable);
    await db.delete(_syncTimeTable);
  }

  Future<int> deleteAllComments() async {
    final db = await database;
    return await db.delete(_commentsTable);
  }

  Future<int> deleteAllReactions() async {
    final db = await database;
    return await db.delete(_reactionsTable);
  }

  // ============ Debug Methods ============

  Future<void> seedExampleData() async {}

  // ============ Row Mappers ============

  Map<String, dynamic> _commentToRow(Comment comment) {
    return {
      'id': comment.id,
      'collection_id': comment.collectionID,
      'file_id': comment.fileID,
      'data': comment.data,
      'parent_comment_id': comment.parentCommentID,
      'parent_comment_user_id': comment.parentCommentUserID,
      'is_deleted': comment.isDeleted ? 1 : 0,
      'user_id': comment.userID,
      'anon_user_id': comment.anonUserID,
      'created_at': comment.createdAt,
      'updated_at': comment.updatedAt,
    };
  }

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

  Map<String, dynamic> _reactionToRow(Reaction reaction) {
    return {
      'id': reaction.id,
      'collection_id': reaction.collectionID,
      'file_id': reaction.fileID,
      'comment_id': reaction.commentID,
      'data': reaction.data,
      'is_deleted': reaction.isDeleted ? 1 : 0,
      'user_id': reaction.userID,
      'anon_user_id': reaction.anonUserID,
      'created_at': reaction.createdAt,
      'updated_at': reaction.updatedAt,
    };
  }

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

  Map<String, dynamic> _anonProfileToRow(AnonProfile profile) {
    return {
      'anon_user_id': profile.anonUserID,
      'collection_id': profile.collectionID,
      'data': profile.data,
      'created_at': profile.createdAt,
      'updated_at': profile.updatedAt,
    };
  }

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
