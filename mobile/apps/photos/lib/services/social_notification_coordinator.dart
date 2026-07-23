import 'dart:math';

import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/db/social_db.dart';
import 'package:photos/extensions/user_extension.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/extensions/file_props.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/social/comment.dart';
import 'package:photos/models/social/feed_item.dart';
import 'package:photos/models/social/reaction.dart';
import 'package:photos/models/social/social_data_provider.dart';
import 'package:photos/services/app_lifecycle_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/language_service.dart';
import 'package:photos/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SocialNotificationTrigger { remoteSync, feedRefresh }

class SocialNotificationCoordinator {
  static const String kLastSocialActivityNotificationTime =
      'last_social_activity_notification_time';
  static const String kLastSocialSeenTime = 'last_social_seen_time';
  static const String kIsFirstRemoteSyncDoneKey = 'isFirstRemoteSyncDone';
  static const _kSharedPhotoSessionGapMicros = 1000 * 1000 * 60 * 10;
  static const _kSharedPhotoFetchPageSize = 200;
  static const _kSharedPhotoFetchMaxPages = 5;
  static const _kSharedPhotoFetchMaxRows =
      _kSharedPhotoFetchPageSize * _kSharedPhotoFetchMaxPages;

  static final SocialNotificationCoordinator instance =
      SocialNotificationCoordinator._privateConstructor();

  SocialNotificationCoordinator._privateConstructor();

  final _logger = Logger('SocialNotificationCoordinator');
  late final FilesDB _filesDb = FilesDB.instance;
  late final CollectionsService _collectionsService =
      CollectionsService.instance;

  SharedPreferences? _prefs;
  bool _isNotifying = false;

  void init(SharedPreferences preferences) {
    _prefs = preferences;
  }

  Future<void> markSocialSeen({int? timestampMicros}) async {
    final prefs = await _ensurePrefs();
    final now = timestampMicros ?? DateTime.now().microsecondsSinceEpoch;
    final lastSeen = prefs.getInt(kLastSocialSeenTime) ?? 0;
    if (now > lastSeen) {
      await prefs.setInt(kLastSocialSeenTime, now);
    }
  }

  Future<void> notifyAfterSocialSync({
    required SocialNotificationTrigger trigger,
  }) async {
    if (_isNotifying) {
      _logger.info('Social notification already in progress; skipping');
      return;
    }
    _isNotifying = true;
    try {
      _logger.info('Evaluating social notifications after ${trigger.name}');
      await _notifyNewSocialActivity();
    } finally {
      _isNotifying = false;
    }
  }

  Future<SharedPreferences> _ensurePrefs() async {
    if (_prefs != null) {
      return _prefs!;
    }
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  bool _shouldEvaluateFeedNotifications(
    SharedPreferences prefs, {
    required bool socialNotificationsEnabled,
    required bool sharedPhotosAndAlbumsNotificationsEnabled,
  }) {
    return prefs.containsKey(kIsFirstRemoteSyncDoneKey) &&
        (socialNotificationsEnabled ||
            sharedPhotosAndAlbumsNotificationsEnabled);
  }

  int _getCutoffTime(SharedPreferences prefs) {
    final lastNotified = prefs.getInt(kLastSocialActivityNotificationTime) ?? 0;
    final hasSeenKey = prefs.containsKey(kLastSocialSeenTime);
    final lastSeen = hasSeenKey ? (prefs.getInt(kLastSocialSeenTime) ?? 0) : 0;
    final lastAppOpen =
        prefs.getInt(AppLifecycleService.keyLastAppOpenTime) ?? 0;
    final fallback = hasSeenKey ? lastSeen : lastAppOpen;
    final cutoff = max(lastNotified, fallback);
    if (cutoff == 0) {
      return DateTime.now().microsecondsSinceEpoch;
    }
    return cutoff;
  }

  Future<void> _notifyNewSocialActivity() async {
    final prefs = await _ensurePrefs();
    final socialNotificationsEnabled = NotificationService.instance
        .shouldShowSocialNotifications();
    final sharedPhotosAndAlbumsNotificationsEnabled = NotificationService
        .instance
        .shouldShowNotificationsForSharedPhotosAndAlbums();
    if (!_shouldEvaluateFeedNotifications(
      prefs,
      socialNotificationsEnabled: socialNotificationsEnabled,
      sharedPhotosAndAlbumsNotificationsEnabled:
          sharedPhotosAndAlbumsNotificationsEnabled,
    )) {
      return;
    }
    final userID = Configuration.instance.getUserID();
    if (userID == null) {
      return;
    }

    final cutoffTime = _getCutoffTime(prefs);

    final hiddenCollectionIds = _collectionsService.getHiddenCollectionIds();
    final latestByKey = <String, _SocialActivityCandidate>{};

    void considerCandidate(_SocialActivityCandidate candidate) {
      if (!_isFeedNotificationEnabledForType(
        candidate.type,
        socialNotificationsEnabled: socialNotificationsEnabled,
        sharedPhotosAndAlbumsNotificationsEnabled:
            sharedPhotosAndAlbumsNotificationsEnabled,
      )) {
        return;
      }
      if (candidate.createdAt <= cutoffTime) {
        return;
      }
      if (hiddenCollectionIds.contains(candidate.collectionID)) {
        return;
      }
      if (candidate.fileID == null &&
          candidate.type != FeedItemType.sharedCollection) {
        return;
      }
      final group = _notificationGroupForType(candidate.type);
      final fileIDKey = candidate.fileID ?? 0;
      final key =
          '${candidate.collectionID}_${candidate.type.index}_${fileIDKey}_${group.index}';
      final existing = latestByKey[key];
      if (existing == null || candidate.createdAt > existing.createdAt) {
        latestByKey[key] = candidate;
      }
    }

    final db = SocialDB.instance;

    final List<Comment> fileComments = await db.getCommentsOnFilesSince(
      excludeUserID: userID,
      sinceTime: cutoffTime,
    );
    for (final comment in fileComments) {
      considerCandidate(
        _SocialActivityCandidate(
          type: FeedItemType.comment,
          collectionID: comment.collectionID,
          fileID: comment.fileID,
          commentID: comment.id,
          createdAt: comment.createdAt,
          actorUserID: comment.userID,
          actorAnonID: comment.anonUserID,
        ),
      );
    }

    final List<Comment> replies = await db.getRepliesSince(
      excludeUserID: userID,
      sinceTime: cutoffTime,
    );
    final List<Reaction> photoLikes = await db.getReactionsOnFilesSince(
      excludeUserID: userID,
      sinceTime: cutoffTime,
    );

    for (final reply in replies) {
      considerCandidate(
        _SocialActivityCandidate(
          type: FeedItemType.reply,
          collectionID: reply.collectionID,
          fileID: reply.fileID,
          commentID: reply.id,
          createdAt: reply.createdAt,
          actorUserID: reply.userID,
          actorAnonID: reply.anonUserID,
          parentCommentUserID: reply.parentCommentUserID,
        ),
      );
    }

    final allFileIDs = <int>{};
    for (final reaction in photoLikes) {
      if (reaction.fileID != null) allFileIDs.add(reaction.fileID!);
    }
    for (final comment in fileComments) {
      if (comment.fileID != null) allFileIDs.add(comment.fileID!);
    }

    final filesByID = await _filesDb.getFileIDToFileFromIDs(
      allFileIDs.toList(),
    );

    bool isOwnedByUser(int? fileID) {
      if (fileID == null) {
        return false;
      }
      final file = filesByID[fileID];
      return file != null && file.ownerID == userID;
    }

    for (final reaction in photoLikes) {
      if (!isOwnedByUser(reaction.fileID)) {
        continue;
      }
      considerCandidate(
        _SocialActivityCandidate(
          type: FeedItemType.photoLike,
          collectionID: reaction.collectionID,
          fileID: reaction.fileID,
          createdAt: reaction.createdAt,
          actorUserID: reaction.userID,
          actorAnonID: reaction.anonUserID,
        ),
      );
    }

    final sharedCandidates = await _getSharedFeedCandidates(
      userID: userID,
      cutoffTime: cutoffTime,
      hiddenCollectionIds: hiddenCollectionIds,
    );
    for (final candidate in sharedCandidates) {
      considerCandidate(candidate);
    }

    if (latestByKey.isEmpty) {
      return;
    }

    final candidates = latestByKey.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final s = await LanguageService.locals;

    int? latestSentNotificationTime;
    for (final candidate in candidates) {
      try {
        final fileID = candidate.fileID;
        final fileType = filesByID[fileID]?.fileType;
        final isOwn = switch (candidate.type) {
          FeedItemType.photoLike => isOwnedByUser(fileID),
          FeedItemType.comment => isOwnedByUser(fileID),
          FeedItemType.reply => candidate.parentCommentUserID == userID,
          FeedItemType.commentLike => false,
          FeedItemType.replyLike => false,
          FeedItemType.sharedPhoto => false,
          FeedItemType.sharedCollection => false,
        };
        final title = await _getSocialNotificationTitle(candidate);
        await NotificationService.instance.showNotification(
          title,
          _getSocialNotificationBody(candidate, s, fileType, isOwn),
          channelID: 'social_activity',
          channelName: 'Ente Feed',
          payload: _buildSocialNotificationPayload(candidate),
          id: _buildSocialNotificationId(
            candidate.collectionID,
            fileID,
            candidate.type,
            _notificationGroupForType(candidate.type),
          ),
        );
        latestSentNotificationTime ??= candidate.createdAt;
      } catch (e, stackTrace) {
        _logger.severe('Failed to prepare social notification', e, stackTrace);
      }
    }

    if (latestSentNotificationTime != null) {
      await prefs.setInt(
        kLastSocialActivityNotificationTime,
        latestSentNotificationTime,
      );
    }
  }

  bool _isFeedNotificationEnabledForType(
    FeedItemType type, {
    required bool socialNotificationsEnabled,
    required bool sharedPhotosAndAlbumsNotificationsEnabled,
  }) {
    switch (type) {
      case FeedItemType.comment:
      case FeedItemType.reply:
      case FeedItemType.photoLike:
        return socialNotificationsEnabled;
      case FeedItemType.sharedPhoto:
      case FeedItemType.sharedCollection:
        return sharedPhotosAndAlbumsNotificationsEnabled;
      case FeedItemType.commentLike:
      case FeedItemType.replyLike:
        return false;
    }
  }

  _SocialNotificationGroup _notificationGroupForType(FeedItemType type) {
    switch (type) {
      case FeedItemType.comment:
      case FeedItemType.reply:
        return _SocialNotificationGroup.comment;
      case FeedItemType.photoLike:
      case FeedItemType.commentLike:
      case FeedItemType.replyLike:
        return _SocialNotificationGroup.like;
      case FeedItemType.sharedPhoto:
        return _SocialNotificationGroup.sharedPhoto;
      case FeedItemType.sharedCollection:
        return _SocialNotificationGroup.sharedCollection;
    }
  }

  int _buildSocialNotificationId(
    int collectionID,
    int? fileID,
    FeedItemType type,
    _SocialNotificationGroup group,
  ) {
    const int base = 0x10000000;
    int hash = collectionID & 0x7fffffff;
    hash = ((hash * 31) ^ (fileID ?? 0)) & 0x7fffffff;
    hash = ((hash * 31) ^ type.index) & 0x7fffffff;
    hash = ((hash * 31) ^ group.index) & 0x7fffffff;
    return base | (hash & 0x0fffffff);
  }

  Future<String> _getSocialNotificationTitle(
    _SocialActivityCandidate candidate,
  ) async {
    final userID = candidate.actorUserID;
    final anonID = candidate.actorAnonID;
    if (userID <= 0 && anonID != null) {
      return SocialDataProvider.instance.getAnonDisplayName(
        anonID,
        candidate.collectionID,
        fallback: anonID,
      );
    }
    final user = _collectionsService.getFileOwner(
      userID,
      candidate.collectionID,
    );
    return user.nameOrEmail;
  }

  String _getSocialNotificationBody(
    _SocialActivityCandidate candidate,
    AppLocalizations s,
    FileType? fileType,
    bool isOwn,
  ) {
    return _getSocialNotificationDetail(candidate, s, fileType, isOwn);
  }

  String _getSocialNotificationDetail(
    _SocialActivityCandidate candidate,
    AppLocalizations s,
    FileType? fileType,
    bool isOwn,
  ) {
    final isVideo = fileType == FileType.video;
    switch (candidate.type) {
      case FeedItemType.photoLike:
        return isVideo ? s.likedYourVideo : s.likedYourPhoto;
      case FeedItemType.comment:
        if (isOwn) {
          return isVideo ? s.commentedOnYourVideo : s.commentedOnYourPhoto;
        }
        return isVideo ? s.commentedOnAVideo : s.commentedOnAPhoto;
      case FeedItemType.reply:
        return isOwn ? s.repliedToYourComment : s.repliedToAComment;
      case FeedItemType.commentLike:
        return s.likedYourComment;
      case FeedItemType.replyLike:
        return s.likedYourReply;
      case FeedItemType.sharedPhoto:
        final count = candidate.sharedFileCount;
        final albumName = candidate.collectionName ?? s.albums;
        if (count <= 1) {
          return s.addedAMemoryTo(albumName: albumName);
        }
        return s.addedNMemoriesTo(count: count, albumName: albumName);
      case FeedItemType.sharedCollection:
        final albumName = candidate.collectionName ?? s.albums;
        return s.sharedAlbumWithYou(albumName: albumName);
    }
  }

  Future<List<_SocialActivityCandidate>> _getSharedFeedCandidates({
    required int userID,
    required int cutoffTime,
    required Set<int> hiddenCollectionIds,
  }) async {
    final context = _SharedCollectionsContext.fromCollections(
      _collectionsService.getCollectionsForUI(
        includedShared: true,
        includeCollab: true,
      ),
      userID: userID,
    );

    final candidates = <_SocialActivityCandidate>[];
    for (final collection in context.incomingSharedCollections) {
      final sharedAt = collection.sharedAt;
      final ownerID = collection.owner.id;
      if (sharedAt == null ||
          sharedAt <= cutoffTime ||
          ownerID == null ||
          hiddenCollectionIds.contains(collection.id)) {
        continue;
      }
      candidates.add(
        _SocialActivityCandidate(
          type: FeedItemType.sharedCollection,
          collectionID: collection.id,
          createdAt: sharedAt,
          actorUserID: ownerID,
          collectionName: context.collectionNames[collection.id],
        ),
      );
    }

    final groupingState = _SharedPhotoGroupingState(
      sessionGapMicros: _kSharedPhotoSessionGapMicros,
    );
    var retainedRows = 0;

    for (var page = 0; page < _kSharedPhotoFetchMaxPages; page++) {
      final pageFiles = await _filesDb.getRecentlySharedFiles(
        currentUserID: userID,
        limit: _kSharedPhotoFetchPageSize,
        offset: page * _kSharedPhotoFetchPageSize,
        addedTimeAfterOrEqualTo: cutoffTime + 1,
      );
      if (pageFiles.isEmpty) {
        break;
      }

      for (final file in pageFiles) {
        final collectionID = file.collectionID;
        final addedTime = file.addedTime;
        if (collectionID == null ||
            addedTime == null ||
            hiddenCollectionIds.contains(collectionID) ||
            file.uploaderName != null) {
          continue;
        }
        final incomingSharedAt =
            context.incomingCollectionSharedAtByID[collectionID];
        if (incomingSharedAt != null && addedTime <= incomingSharedAt) {
          continue;
        }

        groupingState.addFile(file);
        retainedRows++;
        if (retainedRows >= _kSharedPhotoFetchMaxRows) {
          break;
        }
      }

      final reachedEnd =
          pageFiles.length < _kSharedPhotoFetchPageSize ||
          retainedRows >= _kSharedPhotoFetchMaxRows;
      if (reachedEnd) {
        break;
      }
    }

    final groupedPhotos = groupingState.buildSnapshotSorted();
    for (final group in groupedPhotos) {
      if (group.createdAt <= cutoffTime) {
        continue;
      }
      candidates.add(
        _SocialActivityCandidate(
          type: FeedItemType.sharedPhoto,
          collectionID: group.collectionID,
          fileID: group.sharedFileIDs.first,
          createdAt: group.createdAt,
          actorUserID: group.ownerID,
          sharedFileCount: group.sharedFileIDs.length,
          collectionName: context.collectionNames[group.collectionID],
        ),
      );
    }

    return candidates;
  }

  String _buildSocialNotificationPayload(_SocialActivityCandidate candidate) {
    final params = <String, String>{
      'type': candidate.type.name,
      'collectionID': candidate.collectionID.toString(),
    };
    if (candidate.fileID != null) {
      params['fileID'] = candidate.fileID.toString();
    }
    if (candidate.commentID != null) {
      params['commentID'] = candidate.commentID!;
    }
    return Uri(
      scheme: 'ente',
      host: 'feed',
      queryParameters: params,
    ).toString();
  }
}

class _SocialActivityCandidate {
  final FeedItemType type;
  final int collectionID;
  final int? fileID;
  final String? commentID;
  final int createdAt;
  final int actorUserID;
  final String? actorAnonID;
  final int? parentCommentUserID;
  final int sharedFileCount;
  final String? collectionName;

  _SocialActivityCandidate({
    required this.type,
    required this.collectionID,
    required this.createdAt,
    required this.actorUserID,
    this.fileID,
    this.commentID,
    this.actorAnonID,
    this.parentCommentUserID,
    this.sharedFileCount = 0,
    this.collectionName,
  });
}

enum _SocialNotificationGroup { comment, like, sharedPhoto, sharedCollection }

class _SharedCollectionsContext {
  final Map<int, String> collectionNames;
  final List<Collection> incomingSharedCollections;
  final Map<int, int> incomingCollectionSharedAtByID;

  const _SharedCollectionsContext({
    required this.collectionNames,
    required this.incomingSharedCollections,
    required this.incomingCollectionSharedAtByID,
  });

  factory _SharedCollectionsContext.fromCollections(
    List<Collection> collections, {
    required int userID,
  }) {
    final collectionNames = <int, String>{};
    final incomingSharedCollections = <Collection>[];
    final incomingCollectionSharedAtByID = <int, int>{};

    for (final collection in collections) {
      collectionNames[collection.id] = collection.displayName;
      if (collection.isDeleted || collection.isOwner(userID)) {
        continue;
      }
      incomingSharedCollections.add(collection);
      final sharedAt = collection.sharedAt;
      if (sharedAt != null && sharedAt > 0) {
        incomingCollectionSharedAtByID[collection.id] = sharedAt;
      }
    }

    return _SharedCollectionsContext(
      collectionNames: collectionNames,
      incomingSharedCollections: incomingSharedCollections,
      incomingCollectionSharedAtByID: incomingCollectionSharedAtByID,
    );
  }
}

class _SharedPhotoGroup {
  final int collectionID;
  final int ownerID;
  final int createdAt;
  final int oldestAddedTime;
  final List<int> sharedFileIDs;

  const _SharedPhotoGroup({
    required this.collectionID,
    required this.ownerID,
    required this.createdAt,
    required this.oldestAddedTime,
    required this.sharedFileIDs,
  });
}

class _SharedPhotoGroupBuilder {
  final int collectionID;
  final int ownerID;
  final int createdAt;
  int oldestAddedTime;
  final List<int> sharedFileIDs;

  _SharedPhotoGroupBuilder({
    required this.collectionID,
    required this.ownerID,
    required this.createdAt,
    required int firstFileID,
  }) : oldestAddedTime = createdAt,
       sharedFileIDs = [firstFileID];

  void add(int fileID, int addedTime) {
    sharedFileIDs.add(fileID);
    oldestAddedTime = addedTime;
  }

  _SharedPhotoGroup build() {
    return _SharedPhotoGroup(
      collectionID: collectionID,
      ownerID: ownerID,
      createdAt: createdAt,
      oldestAddedTime: oldestAddedTime,
      sharedFileIDs: List<int>.from(sharedFileIDs),
    );
  }
}

class _SharedPhotoGroupingState {
  final int sessionGapMicros;
  final Map<String, _SharedPhotoGroupBuilder> _activeGroups = {};
  final List<_SharedPhotoGroup> _closedGroups = [];

  _SharedPhotoGroupingState({required this.sessionGapMicros});

  void addFile(EnteFile file) {
    final addedTime = file.addedTime;
    final ownerID = file.ownerID;
    final collectionID = file.collectionID;
    final uploadedFileID = file.uploadedFileID;
    if (addedTime == null ||
        ownerID == null ||
        collectionID == null ||
        uploadedFileID == null) {
      return;
    }

    final key = '${collectionID}_$ownerID';
    final currentGroup = _activeGroups[key];
    if (currentGroup == null) {
      _activeGroups[key] = _SharedPhotoGroupBuilder(
        collectionID: collectionID,
        ownerID: ownerID,
        createdAt: addedTime,
        firstFileID: uploadedFileID,
      );
      return;
    }

    final gapFromCurrentGroup = currentGroup.oldestAddedTime - addedTime;
    if (gapFromCurrentGroup <= sessionGapMicros) {
      currentGroup.add(uploadedFileID, addedTime);
      return;
    }

    _closedGroups.add(currentGroup.build());
    _activeGroups[key] = _SharedPhotoGroupBuilder(
      collectionID: collectionID,
      ownerID: ownerID,
      createdAt: addedTime,
      firstFileID: uploadedFileID,
    );
  }

  List<_SharedPhotoGroup> buildSnapshotSorted() {
    final groups = <_SharedPhotoGroup>[
      ..._closedGroups,
      ..._activeGroups.values.map((g) => g.build()),
    ];
    groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return groups;
  }
}
