import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/social_db.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/models/social/reaction.dart";
import "package:photos/services/social_service.dart";
import "package:photos/services/social_sync_service.dart";

/// Provider for social data (comments and reactions).
///
/// Orchestrates between local database and remote API.
/// Query methods read from local DB, mutation methods call API then update DB.
class SocialDataProvider {
  SocialDataProvider._();
  static final instance = SocialDataProvider._();

  final _logger = Logger('SocialDataProvider');
  final _db = SocialDB.instance;
  final _api = SocialService.instance;

  // ============ Query methods (read from local DB) ============

  Future<List<Comment>> getCommentsForFile(int fileID) {
    return _db.getCommentsForFile(fileID);
  }

  /// [candidateCollectionIDs] narrows the indexed lookup to collections the
  /// caller already knows are eligible.
  Future<Comment?> getLatestCommentForFile(
    int fileID, {
    required List<int> candidateCollectionIDs,
  }) {
    return _db.getLatestCommentForFile(
      fileID,
      candidateCollectionIDs: candidateCollectionIDs,
    );
  }

  Future<int> getCommentCountForFileInCollections(
    int fileID,
    List<int> collectionIDs,
  ) {
    return _db.getCommentCountForFileInCollections(fileID, collectionIDs);
  }

  Future<int> getCommentCountForFileInCollection(int fileID, int collectionID) {
    return _db.getCommentCountForFileInCollection(fileID, collectionID);
  }

  Future<List<Reaction>> getReactionsForFile(int fileID) {
    return _db.getReactionsForFile(fileID);
  }

  Future<bool> hasUserReactedToFileInCollections(
    int fileID,
    int userID,
    List<int> collectionIDs,
  ) {
    return _db.hasUserReactedToFileInCollections(fileID, userID, collectionIDs);
  }

  Future<List<Reaction>> getReactionsForFileInCollection(
    int fileID,
    int collectionID,
  ) {
    return _db.getReactionsForFileInCollection(fileID, collectionID);
  }

  Future<List<Comment>> getRepliesForComment(String commentID) {
    return _db.getRepliesForComment(commentID);
  }

  Future<List<Reaction>> getReactionsForComment(String commentID) {
    return _db.getReactionsForComment(commentID);
  }

  Future<Comment?> getCommentById(String id) {
    return _db.getCommentById(id);
  }

  Future<List<Comment>> getCommentsForFilePaginated(
    int fileID, {
    required int collectionID,
    int limit = 20,
    int offset = 0,
  }) {
    return _db.getCommentsForFilePaginated(
      fileID,
      collectionID: collectionID,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Comment>> getCommentsForCollectionPaginated(
    int collectionID, {
    int limit = 20,
    int offset = 0,
  }) {
    return _db.getCommentsForCollectionPaginated(
      collectionID,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Comment>> getCommentsForCollection(int collectionID) {
    return _db.getCommentsForCollection(collectionID);
  }

  Future<List<Reaction>> getReactionsForCollection(int collectionID) {
    return _db.getReactionsForCollection(collectionID);
  }

  // ============ Sync methods ============

  /// Syncs reactions for a specific file.
  /// Call this before displaying reactions for a file to ensure data is fresh.
  Future<void> syncFileReactions(int collectionID, int fileID) {
    return SocialSyncService.instance.syncFileReactions(collectionID, fileID);
  }

  /// Syncs both comments and reactions for a specific file.
  /// Call this before displaying comments screen to ensure data is fresh.
  Future<void> syncFileSocialData(int collectionID, int fileID) {
    return SocialSyncService.instance.syncFileSocialData(collectionID, fileID);
  }

  /// Syncs anonymous profiles for a collection.
  Future<void> syncAnonProfiles(int collectionID) {
    return SocialSyncService.instance.syncAnonProfiles(collectionID);
  }

  // ============ Comment mutation methods ============

  /// Adds a comment via API, then stores locally.
  ///
  /// Returns the created Comment on success, throws on failure.
  Future<Comment?> addComment({
    required int collectionID,
    required String text,
    int? fileID,
    String? parentCommentID,
  }) async {
    try {
      // Encrypt the comment text
      final encrypted = _api.encryptComment(text, collectionID);

      // Call API
      final commentID = await _api.createComment(
        collectionID: collectionID,
        cipher: encrypted.cipher,
        nonce: encrypted.nonce,
        fileID: fileID,
        parentCommentID: parentCommentID,
      );

      // Create local comment object (timestamps in microseconds to match server)
      final now = DateTime.now().microsecondsSinceEpoch;
      final userID = Configuration.instance.getUserID() ?? 0;
      final comment = Comment(
        id: commentID,
        collectionID: collectionID,
        fileID: fileID,
        data: text,
        parentCommentID: parentCommentID,
        userID: userID,
        createdAt: now,
        updatedAt: now,
      );

      // Store locally
      await _db.addComment(comment);
      return comment;
    } catch (e) {
      _logger.severe('Failed to add comment', e);
      rethrow;
    }
  }

  /// Deletes a comment via API, then marks as deleted locally.
  ///
  /// Returns the deleted Comment on success, throws on failure.
  Future<Comment?> deleteComment(String id) async {
    try {
      // Call API
      await _api.deleteComment(id);

      // Mark as deleted locally
      return _db.deleteComment(id);
    } catch (e) {
      _logger.severe('Failed to delete comment $id', e);
      rethrow;
    }
  }

  // ============ Reaction mutation methods ============

  /// Toggles a reaction (like) on a file or comment.
  ///
  /// If the user hasn't reacted, creates a new reaction.
  /// If the user has already reacted, deletes the existing reaction.
  ///
  /// Returns the new reaction state (Reaction with isDeleted flag).
  Future<Reaction?> toggleReaction({
    required int userID,
    required int collectionID,
    int? fileID,
    String? commentID,
    String reactionType = 'green_heart',
  }) async {
    try {
      // Check if user already has a reaction
      final existingReaction = await _findExistingReaction(
        userID: userID,
        collectionID: collectionID,
        fileID: fileID,
        commentID: commentID,
      );

      if (existingReaction != null && !existingReaction.isDeleted) {
        // User has an active reaction - delete it
        await _api.deleteReaction(existingReaction.id);

        // Mark as deleted locally (timestamps in microseconds to match server)
        final now = DateTime.now().microsecondsSinceEpoch;
        final deletedReaction = existingReaction.copyWith(
          isDeleted: true,
          updatedAt: now,
        );
        await _db.upsertReactions([deletedReaction]);
        return deletedReaction;
      } else {
        // User doesn't have a reaction or it's deleted - create/upsert one
        final encrypted = _api.encryptReaction(reactionType, collectionID);

        final reactionID = await _api.upsertReaction(
          collectionID: collectionID,
          cipher: encrypted.cipher,
          nonce: encrypted.nonce,
          fileID: fileID,
          commentID: commentID,
        );

        // Create local reaction object (timestamps in microseconds to match server)
        final now = DateTime.now().microsecondsSinceEpoch;
        final reaction = Reaction(
          id: reactionID,
          collectionID: collectionID,
          fileID: fileID,
          commentID: commentID,
          data: reactionType,
          isDeleted: false,
          userID: userID,
          createdAt: existingReaction?.createdAt ?? now,
          updatedAt: now,
        );

        // Store locally
        await _db.upsertReactions([reaction]);
        return reaction;
      }
    } catch (e) {
      _logger.severe('Failed to toggle reaction', e);
      rethrow;
    }
  }

  /// Finds an existing reaction for the user on the given target.
  Future<Reaction?> _findExistingReaction({
    required int userID,
    required int collectionID,
    int? fileID,
    String? commentID,
  }) async {
    if (commentID != null) {
      final reactions = await _db.getReactionsForComment(commentID);
      for (final r in reactions) {
        if (r.userID == userID) return r;
      }
    } else if (fileID != null) {
      final reactions = await _db.getReactionsForFileInCollection(
        fileID,
        collectionID,
      );
      for (final r in reactions) {
        if (r.userID == userID) return r;
      }
    } else {
      final reactions = await _db.getReactionsForCollection(collectionID);
      for (final r in reactions) {
        if (r.userID == userID) return r;
      }
    }
    return null;
  }

  /// Checks if the current user has liked a file in a collection.
  Future<bool> hasUserLikedFile(int fileID, int collectionID) async {
    final userID = Configuration.instance.getUserID();
    if (userID == null) return false;

    final reactions = await _db.getReactionsForFileInCollection(
      fileID,
      collectionID,
    );
    return reactions.any((r) => r.userID == userID && !r.isDeleted);
  }

  /// Gets the current user's reaction on a file in a collection (if any).
  Future<Reaction?> getUserReactionForFile(int fileID, int collectionID) async {
    final userID = Configuration.instance.getUserID();
    if (userID == null) return null;

    final reactions = await _db.getReactionsForFileInCollection(
      fileID,
      collectionID,
    );
    for (final r in reactions) {
      if (r.userID == userID && !r.isDeleted) return r;
    }
    return null;
  }

  // ============ Anon Profile methods ============

  /// Gets the decrypted display name for an anonymous user.
  ///
  /// Returns the display name from the synced AnonProfile if available,
  /// otherwise returns [fallback] (typically the raw anonUserID).
  Future<String> getAnonDisplayName(
    String anonUserID,
    int collectionID, {
    String? fallback,
  }) async {
    final profile = await _db.getAnonProfile(anonUserID, collectionID);
    return profile?.displayName ?? fallback ?? anonUserID;
  }

  /// Gets all anon profiles for a collection as a map of anonUserID -> displayName.
  ///
  /// Only includes profiles where displayName could be extracted from the data.
  Future<Map<String, String>> getAnonDisplayNamesForCollection(
    int collectionID,
  ) async {
    final profiles = await _db.getAnonProfilesForCollection(collectionID);
    final result = <String, String>{};
    for (final p in profiles) {
      final name = p.displayName;
      if (name != null) {
        result[p.anonUserID] = name;
      }
    }
    return result;
  }
}
