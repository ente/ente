import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/social_db.dart';
import 'package:photos/events/social_data_updated_event.dart';
import 'package:photos/models/social/anon_profile.dart';
import 'package:photos/models/social/api_responses.dart';
import 'package:photos/models/social/comment.dart';
import 'package:photos/models/social/reaction.dart';
import 'package:photos/services/social_service.dart';

/// Service for syncing social data (comments and reactions) with the server.
///
/// Handles diff-based sync, encryption/decryption, and local storage.
class SocialSyncService {
  SocialSyncService._();
  static final instance = SocialSyncService._();

  final _logger = Logger('SocialSyncService');
  final _db = SocialDB.instance;
  final _api = SocialService.instance;
  final Map<int, int> _commentsEqualSeenCache = {};
  final Map<int, int> _reactionsEqualSeenCache = {};
  final Map<int, int> _commentsEqualSyncedCache = {};
  final Map<int, int> _reactionsEqualSyncedCache = {};

  bool _isSyncing = false;

  /// Syncs social data for a single collection.
  ///
  /// Uses diff-based sync with separate sinceTime for comments and reactions.
  Future<void> syncCollection(int collectionID) async {
    int normalizeSinceTime(int syncTime) => syncTime > 0 ? syncTime - 1 : 0;
    int commentsSinceTime = normalizeSinceTime(
      await _db.getCommentsSyncTime(collectionID),
    );
    int reactionsSinceTime = normalizeSinceTime(
      await _db.getReactionsSyncTime(collectionID),
    );

    int maxCommentsUpdatedAt = commentsSinceTime;
    int maxReactionsUpdatedAt = reactionsSinceTime;

    try {
      bool hasMoreComments = true;
      bool hasMoreReactions = true;

      // Sync using unified endpoint with separate since times
      while (hasMoreComments || hasMoreReactions) {
        final response = await _api.fetchSocialDiff(
          collectionID: collectionID,
          commentsSinceTime: commentsSinceTime,
          reactionsSinceTime: reactionsSinceTime,
        );

        // Process comments
        if (response.comments.isNotEmpty) {
          final comments = _decryptComments(response.comments, collectionID);
          await _db.upsertComments(comments);

          for (final comment in response.comments) {
            if (comment.updatedAt > maxCommentsUpdatedAt) {
              maxCommentsUpdatedAt = comment.updatedAt;
            }
          }
        }

        // Process reactions
        if (response.reactions.isNotEmpty) {
          final reactions = _decryptReactions(response.reactions, collectionID);
          await _db.upsertReactions(reactions);

          for (final reaction in response.reactions) {
            if (reaction.updatedAt > maxReactionsUpdatedAt) {
              maxReactionsUpdatedAt = reaction.updatedAt;
            }
          }
        }

        hasMoreComments = response.hasMoreComments;
        hasMoreReactions = response.hasMoreReactions;

        if (!hasMoreComments && !hasMoreReactions) {
          break;
        }

        // Update since times for pagination
        commentsSinceTime = maxCommentsUpdatedAt;
        reactionsSinceTime = maxReactionsUpdatedAt;
      }

      // Update sync times
      if (maxCommentsUpdatedAt > await _db.getCommentsSyncTime(collectionID)) {
        await _db.setCommentsSyncTime(collectionID, maxCommentsUpdatedAt);
      }
      if (maxReactionsUpdatedAt >
          await _db.getReactionsSyncTime(collectionID)) {
        await _db.setReactionsSyncTime(collectionID, maxReactionsUpdatedAt);
      }

      await _db.resolveParentCommentUserIDs(collectionID);
    } catch (e) {
      _logger.severe('Failed to sync collection $collectionID', e);
      rethrow;
    }
  }

  /// Syncs reactions for a specific file in a collection.
  ///
  /// Useful for on-demand sync when viewing a file.
  Future<void> syncFileReactions(int collectionID, int fileID) async {
    try {
      final response = await _api.fetchReactionsDiff(
        collectionID: collectionID,
        fileID: fileID,
        sinceTime: 0, // Always get all reactions for the file
      );

      if (response.reactions.isNotEmpty) {
        final reactions = _decryptReactions(response.reactions, collectionID);
        await _db.upsertReactions(reactions);
      }
    } catch (e) {
      _logger.warning('Failed to sync reactions for file $fileID', e);
      // Don't rethrow - this is a non-critical operation
    }
  }

  /// Syncs both comments and reactions for a specific file in a collection.
  ///
  /// Useful for on-demand sync when opening comments screen.
  Future<void> syncFileSocialData(int collectionID, int fileID) async {
    try {
      final response = await _api.fetchSocialDiff(
        collectionID: collectionID,
        fileID: fileID,
        // Always get all data for the file (no sinceTime = fetch all)
      );

      if (response.comments.isNotEmpty) {
        final comments = _decryptComments(response.comments, collectionID);
        await _db.upsertComments(comments);
      }

      if (response.reactions.isNotEmpty) {
        final reactions = _decryptReactions(response.reactions, collectionID);
        await _db.upsertReactions(reactions);
      }

      await _db.resolveParentCommentUserIDs(collectionID);
    } catch (e) {
      _logger.warning('Failed to sync social data for file $fileID', e);
      // Don't rethrow - this is a non-critical operation
    }
  }

  /// Syncs social data for all collections that have new updates.
  ///
  /// Called during background sync to keep social data up to date.
  /// Uses the /comments-reactions/updated-at endpoint to determine which
  /// collections actually need syncing, avoiding unnecessary API calls.
  Future<bool> syncAllSharedCollections() async {
    if (_isSyncing) {
      _logger.info('Sync already in progress, skipping');
      return false;
    }

    _isSyncing = true;
    try {
      final userID = Configuration.instance.getUserID();
      if (userID == null) {
        _logger.info('User not logged in, skipping social sync');
        return false;
      }

      // Get latest update timestamps from server
      final latestUpdates = await _api.fetchLatestUpdates();

      if (latestUpdates.updates.isEmpty) {
        _logger.info('No collections have social activity');
        return false;
      }

      _logger.info(
        'Checking ${latestUpdates.updates.length} collections for social updates',
      );

      int syncedCount = 0;
      bool hasNewComments = false;
      bool hasNewReactions = false;

      for (final update in latestUpdates.updates) {
        try {
          final localCommentsSyncTime = await _db.getCommentsSyncTime(
            update.collectionID,
          );
          final localReactionsSyncTime = await _db.getReactionsSyncTime(
            update.collectionID,
          );

          final forceCommentsEqualSync = _shouldForceEqualSync(
            _commentsEqualSeenCache,
            _commentsEqualSyncedCache,
            update.collectionID,
            update.commentsUpdatedAt,
            localCommentsSyncTime,
          );
          final forceReactionsEqualSync = _shouldForceEqualSync(
            _reactionsEqualSeenCache,
            _reactionsEqualSyncedCache,
            update.collectionID,
            update.reactionsUpdatedAt,
            localReactionsSyncTime,
          );

          final needsCommentsSync =
              update.commentsUpdatedAt != null &&
              (update.commentsUpdatedAt! > localCommentsSyncTime ||
                  forceCommentsEqualSync);
          final needsReactionsSync =
              update.reactionsUpdatedAt != null &&
              (update.reactionsUpdatedAt! > localReactionsSyncTime ||
                  forceReactionsEqualSync);

          if (needsCommentsSync || needsReactionsSync) {
            await syncCollection(update.collectionID);
            syncedCount++;
            hasNewComments = hasNewComments || needsCommentsSync;
            hasNewReactions = hasNewReactions || needsReactionsSync;
          }

          // Sync anon profiles if needed
          if (update.anonProfilesUpdatedAt != null) {
            final localAnonSyncTime = await _db.getAnonProfilesSyncTime(
              update.collectionID,
            );
            if (update.anonProfilesUpdatedAt! > localAnonSyncTime) {
              await syncAnonProfiles(update.collectionID);
            }
          }
        } catch (e) {
          _logger.warning(
            'Failed to sync collection ${update.collectionID}, continuing',
            e,
          );
        }
      }

      _logger.info('Synced $syncedCount collections with new updates');

      // Fire event if any data was synced
      if (syncedCount > 0) {
        Bus.instance.fire(
          SocialDataUpdatedEvent(
            hasNewComments: hasNewComments,
            hasNewReactions: hasNewReactions,
          ),
        );
      }
      return syncedCount > 0;
    } catch (e) {
      _logger.severe('Failed to fetch latest updates', e);
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  bool _shouldForceEqualSync(
    Map<int, int> seenCache,
    Map<int, int> syncedCache,
    int collectionID,
    int? remoteUpdatedAt,
    int localSyncTime,
  ) {
    if (remoteUpdatedAt == null || remoteUpdatedAt <= 0) {
      return false;
    }
    if (remoteUpdatedAt != localSyncTime) {
      seenCache.remove(collectionID);
      syncedCache.remove(collectionID);
      return false;
    }
    if (syncedCache[collectionID] == remoteUpdatedAt) {
      return false;
    }
    if (seenCache[collectionID] == remoteUpdatedAt) {
      syncedCache[collectionID] = remoteUpdatedAt;
      return true;
    }
    seenCache[collectionID] = remoteUpdatedAt;
    return false;
  }

  /// Syncs anonymous profiles for a collection.
  Future<void> syncAnonProfiles(int collectionID) async {
    try {
      final response = await _api.fetchAnonProfiles(collectionID);

      if (response.profiles.isEmpty) {
        return;
      }

      int maxUpdatedAt = 0;
      final profiles = <AnonProfile>[];

      for (final apiProfile in response.profiles) {
        final data = _api.decryptAnonProfile(
          apiProfile.cipher,
          apiProfile.nonce,
          collectionID,
        );

        profiles.add(
          AnonProfile(
            anonUserID: apiProfile.anonUserID,
            collectionID: apiProfile.collectionID,
            data: data,
            createdAt: apiProfile.createdAt,
            updatedAt: apiProfile.updatedAt,
          ),
        );

        if (apiProfile.updatedAt > maxUpdatedAt) {
          maxUpdatedAt = apiProfile.updatedAt;
        }
      }

      await _db.upsertAnonProfiles(profiles);

      if (maxUpdatedAt > 0) {
        await _db.setAnonProfilesSyncTime(collectionID, maxUpdatedAt);
      }

      _logger.info(
        'Synced ${profiles.length} anon profiles for collection $collectionID',
      );
    } catch (e) {
      _logger.warning(
        'Failed to sync anon profiles for collection $collectionID',
        e,
      );
    }
  }

  /// Decrypts API comment responses to local Comment models.
  List<Comment> _decryptComments(
    List<CommentApiResponse> apiComments,
    int collectionID,
  ) {
    final comments = <Comment>[];
    for (final apiComment in apiComments) {
      final decryptedText = apiComment.isDeleted
          ? ''
          : _api.decryptComment(
              apiComment.cipher,
              apiComment.nonce,
              collectionID,
            );

      comments.add(
        Comment(
          id: apiComment.id,
          collectionID: apiComment.collectionID,
          fileID: apiComment.fileID,
          data: decryptedText,
          parentCommentID: apiComment.parentCommentID,
          parentCommentUserID: apiComment.parentCommentUserID,
          isDeleted: apiComment.isDeleted,
          userID: apiComment.userID,
          anonUserID: apiComment.anonUserID,
          createdAt: apiComment.createdAt,
          updatedAt: apiComment.updatedAt,
        ),
      );
    }
    return comments;
  }

  /// Decrypts API reaction responses to local Reaction models.
  List<Reaction> _decryptReactions(
    List<ReactionApiResponse> apiReactions,
    int collectionID,
  ) {
    final reactions = <Reaction>[];
    for (final apiReaction in apiReactions) {
      final decryptedType = apiReaction.isDeleted
          ? ''
          : _api.decryptReaction(
              apiReaction.cipher,
              apiReaction.nonce,
              collectionID,
            );

      reactions.add(
        Reaction(
          id: apiReaction.id,
          collectionID: apiReaction.collectionID,
          fileID: apiReaction.fileID,
          commentID: apiReaction.commentID,
          data: decryptedType,
          isDeleted: apiReaction.isDeleted,
          userID: apiReaction.userID,
          anonUserID: apiReaction.anonUserID,
          createdAt: apiReaction.createdAt,
          updatedAt: apiReaction.updatedAt,
        ),
      );
    }
    return reactions;
  }
}
