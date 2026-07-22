import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:fast_base58/fast_base58.dart";
import 'package:flutter/foundation.dart';
import "package:flutter/material.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/collections_db.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/db/social_db.dart';
import 'package:photos/db/trash_db.dart';
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_home_gallery_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import "package:photos/gateways/collections/collection_share_gateway.dart";
import 'package:photos/gateways/collections/models/collection_file_item.dart';
import 'package:photos/gateways/collections/models/create_request.dart';
import "package:photos/gateways/collections/models/metadata.dart";
import "package:photos/gateways/collections/models/public_url.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/collection/action.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/files_split.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/app_lifecycle_service.dart';
import "package:photos/services/favorites_service.dart";
import "package:photos/services/hidden_service.dart";
import 'package:photos/services/memory_share_service.dart';
import 'package:photos/services/sync/local_sync_service.dart';
import 'package:photos/services/sync/remote_sync_service.dart';
import "package:photos/settings/local_settings.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/file_key.dart";
import 'package:shared_preferences/shared_preferences.dart';

String? _resolvePublicAlbumAccessToken(Uri uri) {
  final tokenFromQuery = uri.queryParameters["t"];
  if (tokenFromQuery != null && tokenFromQuery.isNotEmpty) {
    return tokenFromQuery;
  }
  return uri.pathSegments.firstWhereOrNull((segment) => segment.isNotEmpty);
}

class CollectionsService {
  static const _collectionSyncTimeKeyPrefix = "collection_sync_time_";
  static const _collectionsSyncTimeKey = "collections_sync_time_x";

  static const int kMaximumWriteAttempts = 5;
  static const int _maxSocialCleanupRetries = 3;
  static const int _collectionKeyLength = 32;

  final _logger = Logger("CollectionsService");

  late CollectionsDB _db;
  late FilesDB _filesDB;
  late Configuration _config;
  late SharedPreferences _prefs;
  StreamSubscription<CollectionUpdatedEvent>? _collectionUpdatedSubscription;

  final _localPathToCollectionID = <String, int>{};
  final _collectionIDToCollections = <int, Collection>{};
  final _cachedKeys = <int, Uint8List>{};
  final _cachedUserIdToUser = <int, User>{};
  Collection? cachedDefaultHiddenCollection;
  Future<Map<int, int>>? _collectionIDToNewestFileTime;
  Collection? cachedUncategorizedCollection;
  final Map<String, EnteFile> _coverCache = <String, EnteFile>{};
  final Map<int, int> _countCache = <int, int>{};

  //Used for links-in-app
  final _cachedPublicAlbumToken = <int, String>{};
  final _cachedPublicAlbumJWT = <int, String>{};
  final _cachedPublicCollectionID = <int>[];
  final _cachedPublicAlbumKey = <int, String>{};
  final _cachedPublicCollectionKeys = <int, Uint8List>{};

  // In-memory list of recently used collection IDs for add/move actions
  // Most recently used is at the front
  static const int _maxRecentlyUsedCollections = 3;
  final _recentlyUsedCollectionIDs = <int>[];

  CollectionsService._privateConstructor() {
    _db = CollectionsDB.instance;
    _filesDB = FilesDB.instance;
    _config = Configuration.instance;
  }

  static final CollectionsService instance =
      CollectionsService._privateConstructor();

  Future<void> init(SharedPreferences preferences) async {
    _prefs = preferences;
    final collections = await _db.getAllCollections();

    for (final collection in collections) {
      // using deprecated method because the path is stored in encrypted
      // format in the DB
      // ignore: deprecated_member_use_from_same_package
      _cacheCollectionAttributes(collection);
    }
    if (_collectionUpdatedSubscription != null) {
      await _collectionUpdatedSubscription!.cancel();
    }
    _collectionUpdatedSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen((event) {
          _collectionIDToNewestFileTime = null;
          if (event.collectionID != null) {
            _coverCache.removeWhere(
              (key, value) => key.startsWith(event.collectionID!.toString()),
            );
            _countCache.remove(event.collectionID);
          }
        });
  }

  Configuration get config => _config;

  Map<int, Collection> get collectionIDToCollections =>
      _collectionIDToCollections;

  FilesDB get filesDB => _filesDB;

  // sync method fetches just sync the collections, not the individual files
  // within the collection.
  Future<void> sync() async {
    _logger.info("Syncing collections");
    final EnteWatch watch = EnteWatch("syncCollection")..start();
    final lastCollectionUpdationTime =
        _prefs.getInt(_collectionsSyncTimeKey) ?? 0;

    _logger.info("[COLLECTIONS] Starting sync");

    // Might not have synced the collection fully
    final fetchedCollections = await _fetchCollections(
      lastCollectionUpdationTime,
    );
    _logger.info(
      "[COLLECTIONS] Fetched ${fetchedCollections.length} collections from API",
    );
    watch.log("remote fetch collections ${fetchedCollections.length}");

    if (fetchedCollections.isEmpty) {
      return;
    }
    final updatedCollections = <Collection>[];
    int maxUpdationTime = lastCollectionUpdationTime;
    final ownerID = _config.getUserID();
    bool shouldFireDeleteEvent = false;
    for (final collection in fetchedCollections) {
      if (collection.isDeleted) {
        await _filesDB.deleteCollection(collection.id);
        await _cleanupSocialData(collection.id);
        await setCollectionSyncTime(collection.id, null);
        if (_collectionIDToCollections.containsKey(collection.id)) {
          shouldFireDeleteEvent = true;
        }
      }
      // remove reference for incoming collections when unshared/deleted
      if (collection.isDeleted && ownerID != collection.owner.id) {
        await _db.deleteCollection(collection.id);
      } else {
        // keep entry for deletedCollection as collectionKey may be used during
        // trash file decryption
        updatedCollections.add(collection);
      }
      maxUpdationTime = collection.updationTime > maxUpdationTime
          ? collection.updationTime
          : maxUpdationTime;
    }

    if (shouldFireDeleteEvent) {
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          List<EnteFile>.empty(),
          source: "syncCollectionDeleted",
        ),
      );
    }

    await _updateDB(updatedCollections);
    await _prefs.setInt(_collectionsSyncTimeKey, maxUpdationTime);
    watch.logAndReset("till DB insertion ${updatedCollections.length}");
    _logger.info("[COLLECTIONS] Updated ${updatedCollections.length} in DB");

    for (final collection in fetchedCollections) {
      _cacheLocalPathAndCollection(collection);
    }

    _logger.info("Collections synced");
    watch.log("${fetchedCollections.length} collection cached refreshed ");

    if (fetchedCollections.isNotEmpty) {
      Bus.instance.fire(
        CollectionUpdatedEvent(
          null,
          List<EnteFile>.empty(),
          "collections_updated",
        ),
      );
    }
  }

  void clearCache() {
    _localPathToCollectionID.clear();
    _collectionIDToCollections.clear();
    cachedDefaultHiddenCollection = null;
    cachedUncategorizedCollection = null;
    _cachedPublicAlbumToken.clear();
    _cachedPublicAlbumJWT.clear();
    _cachedPublicCollectionID.clear();
    _cachedKeys.clear();
    _cachedPublicAlbumKey.clear();
    _cachedPublicCollectionKeys.clear();
  }

  Future<Map<int, int>> getCollectionIDsToBeSynced() async {
    final idsToRemoveUpdateTimeMap = await _db
        .getActiveIDsAndRemoteUpdateTime();
    final result = <int, int>{};
    for (final MapEntry<int, int> e in idsToRemoveUpdateTimeMap.entries) {
      final int cid = e.key;
      final int remoteUpdateTime = e.value;
      if (remoteUpdateTime > getCollectionSyncTime(cid)) {
        result[cid] = remoteUpdateTime;
      }
    }
    return result;
  }

  bool allowUpload(int collectionID) {
    final Collection? c = _collectionIDToCollections[collectionID];
    if (c == null) {
      _logger.info('discardUpload: collectionMissing $collectionID');
      return false;
    }
    if (c.isDeleted) {
      _logger.info('discardUpload: collectionDeleted $collectionID');
      return false;
    }
    if (!c.isOwner(_config.getUserID()!)) {
      _logger.info('discardUpload: notOwner $collectionID');
      return false;
    }
    return true;
  }

  /// Returns true if the file exists in any shared collection.
  ///
  /// A collection is considered "shared" if it has sharees, has a public link,
  /// or is owned by someone else (incoming share).
  Future<bool> isFileInSharedCollection(int uploadedFileID) async {
    final Set<int> collectionIDs = await _filesDB.getAllCollectionIDsOfFile(
      uploadedFileID,
    );

    if (collectionIDs.isEmpty) {
      return false;
    }

    final int? currentUserID = _config.getUserID();
    if (currentUserID == null) {
      return false;
    }

    for (final int collectionID in collectionIDs) {
      final Collection? collection = _collectionIDToCollections[collectionID];

      if (collection == null || collection.isDeleted) {
        continue;
      }

      if (collection.hasSharees ||
          collection.hasLink ||
          !collection.isOwner(currentUserID)) {
        return true;
      }
    }

    return false;
  }

  /// Returns the shared collections containing [uploadedFileID].
  ///
  /// A collection is considered shared if it has sharees, has a public link,
  /// or is owned by someone else (incoming share).
  Future<List<Collection>> getSharedCollectionsForFile(
    int uploadedFileID, {
    bool includeHidden = false,
  }) async {
    final Set<int> collectionIDs = await _filesDB.getAllCollectionIDsOfFile(
      uploadedFileID,
    );
    final int? currentUserID = _config.getUserID();
    if (collectionIDs.isEmpty || currentUserID == null) {
      return [];
    }

    final sharedCollections = <Collection>[];
    for (final collectionID in collectionIDs) {
      final collection = _collectionIDToCollections[collectionID];
      if (_isEligibleSharedCollection(
        collection,
        currentUserID,
        includeHidden: includeHidden,
      )) {
        sharedCollections.add(collection!);
      }
    }
    return sharedCollections;
  }

  /// Returns IDs of shared collections containing [uploadedFileID].
  ///
  /// Use this to scope social content on the view path without constructing a
  /// list of collection objects.
  Future<List<int>> getSharedCollectionIDsForFile(
    int uploadedFileID, {
    bool includeHidden = false,
  }) async {
    final collectionIDs = await _filesDB.getAllCollectionIDsOfFile(
      uploadedFileID,
    );
    final currentUserID = _config.getUserID();
    if (collectionIDs.isEmpty || currentUserID == null) {
      return [];
    }

    final sharedCollectionIDs = <int>[];
    for (final collectionID in collectionIDs) {
      if (_isEligibleSharedCollection(
        _collectionIDToCollections[collectionID],
        currentUserID,
        includeHidden: includeHidden,
      )) {
        sharedCollectionIDs.add(collectionID);
      }
    }
    return sharedCollectionIDs;
  }

  bool _isEligibleSharedCollection(
    Collection? collection,
    int currentUserID, {
    required bool includeHidden,
  }) {
    return collection != null &&
        !collection.isDeleted &&
        (includeHidden || !collection.isHidden()) &&
        (collection.hasSharees ||
            collection.hasLink ||
            !collection.isOwner(currentUserID));
  }

  Future<List<Collection>> getArchivedCollection() async {
    final allCollections = getCollectionsForUI();
    return allCollections
        .where((c) => c.isArchived() && !c.isHidden())
        .toList();
  }

  List<Collection> getHiddenCollections({bool includeDefaultHidden = true}) {
    if (includeDefaultHidden) {
      return _collectionIDToCollections.values
          .where((c) => c.isHidden())
          .toList();
    } else {
      return _collectionIDToCollections.values
          .where(
            (c) => c.isHidden() && c.id != cachedDefaultHiddenCollection?.id,
          )
          .toList();
    }
  }

  Set<int> getHiddenCollectionIds() {
    return _collectionIDToCollections.values
        .where((c) => c.isHidden())
        .map((e) => e.id)
        .toSet();
  }

  Set<int> archivedOrHiddenCollectionIds() {
    return _collectionIDToCollections.values
        .where((c) => c.isArchived() || c.isHidden())
        .map((e) => e.id)
        .toSet();
  }

  int getCollectionSyncTime(int collectionID) {
    return _prefs.getInt(
          _collectionSyncTimeKeyPrefix + collectionID.toString(),
        ) ??
        0;
  }

  Future<Map<int, int>> getCollectionIDToNewestFileTime() {
    _collectionIDToNewestFileTime ??= _filesDB
        .getCollectionIDToMaxCreationTime();
    return _collectionIDToNewestFileTime!;
  }

  Future<EnteFile?> getCover(Collection c) async {
    final int localSyncTime = getCollectionSyncTime(c.id);
    final String coverKey = '${c.id}_${localSyncTime}_${c.updationTime}';
    if (_coverCache.containsKey(coverKey)) {
      return Future.value(_coverCache[coverKey]!);
    }
    if (kDebugMode) {
      debugPrint("getCover for collection ${c.id} ${c.displayName}");
    }
    if (c.hasCover) {
      final coverID = c.pubMagicMetadata.coverID ?? 0;
      final EnteFile? cover = await filesDB.getUploadedFile(coverID, c.id);
      if (cover != null) {
        _coverCache[coverKey] = cover;
        return Future.value(cover);
      }
    }
    final coverFile = await filesDB.getCollectionFileFirstOrLast(
      c.id,
      c.pubMagicMetadata.asc ?? false,
    );
    if (coverFile != null) {
      _coverCache[coverKey] = coverFile;
      return Future.value(coverFile);
    }
    return null;
  }

  EnteFile? getCoverCache(Collection c) {
    final int localSyncTime = getCollectionSyncTime(c.id);
    final String coverKey = '${c.id}_${localSyncTime}_${c.updationTime}';
    return _coverCache[coverKey];
  }

  Future<int> getFileCount(Collection c, {bool useCache = true}) async {
    if (_countCache.containsKey(c.id) && useCache) {
      return _countCache[c.id]!;
    } else {
      final count = await _filesDB.collectionFileCount(c.id);
      _countCache[c.id] = count;
      return count;
    }
  }

  int? getCachedFileCount(Collection c) {
    return _countCache[c.id];
  }

  Future<bool> setCollectionSyncTime(int collectionID, int? time) async {
    final key = _collectionSyncTimeKeyPrefix + collectionID.toString();
    if (time == null) {
      return _prefs.remove(key);
    }
    return _prefs.setInt(key, time);
  }

  // getActiveCollections returns list of collections which are not deleted yet
  List<Collection> getActiveCollections() {
    return _collectionIDToCollections.values
        .toList()
        .where((element) => !element.isDeleted)
        .toList();
  }

  // getActiveCollections returns list of collections which are not deleted yet
  Set<int> nonHiddenOwnedCollections() {
    final int ownerID = _config.getUserID()!;
    return _collectionIDToCollections.values
        .toList()
        .where(
          (element) =>
              !element.isDeleted &&
              !element.isHidden() &&
              element.isOwner(ownerID),
        )
        .map((e) => e.id)
        .toSet();
  }

  // returns collections after removing deleted,uncategorized, and hidden
  // collections
  List<Collection> getCollectionsForUI({
    bool includedShared = false,
    bool includeCollab = false,
    bool includeUncategorized = false,
  }) {
    final Set<CollectionParticipantRole> allowedRoles = {
      CollectionParticipantRole.owner,
    };
    if (includedShared) {
      allowedRoles.add(CollectionParticipantRole.viewer);
    }
    if (includedShared || includeCollab) {
      allowedRoles.add(CollectionParticipantRole.collaborator);
      allowedRoles.add(CollectionParticipantRole.admin);
    }
    final int? userID = _config.getUserID();
    if (userID == null) {
      _logger.info(
        "Skipping collections for UI because user ID is unavailable",
      );
      return <Collection>[];
    }
    return _collectionIDToCollections.values
        .where(
          (c) =>
              !c.isDeleted &&
              (includeUncategorized ||
                  c.type != CollectionType.uncategorized) &&
              !c.isHidden() &&
              allowedRoles.contains(c.getRole(userID)),
        )
        .toList();
  }

  /// Records a collection as recently used for add/move actions.
  /// Most recently used collection is moved to front.
  void recordCollectionUsage(int collectionID) {
    _recentlyUsedCollectionIDs.remove(collectionID);
    _recentlyUsedCollectionIDs.insert(0, collectionID);
    if (_recentlyUsedCollectionIDs.length > _maxRecentlyUsedCollections) {
      _recentlyUsedCollectionIDs.removeLast();
    }
  }

  /// Returns a list of recently used collections for add/move actions.
  /// Filters out collections that no longer exist or are hidden.
  List<Collection> getRecentlyUsedCollections() {
    final List<Collection> result = [];
    for (final id in _recentlyUsedCollectionIDs) {
      final collection = _collectionIDToCollections[id];
      if (collection != null &&
          !collection.isDeleted &&
          !collection.isHidden()) {
        result.add(collection);
      }
    }
    return result;
  }

  bool canRemoveFilesFromAllParticipants(Collection collection) {
    final int? userID = _config.getUserID();
    if (userID == null) {
      return false;
    }
    if (collection.isOwner(userID)) {
      return true;
    }
    return collection.isAdmin(userID);
  }

  List<int> getAllOwnedCollectionIDs() {
    final int userID = _config.getUserID()!;
    return _collectionIDToCollections.values
        .where((c) => !c.isDeleted && c.isOwner(userID))
        .map((e) => e.id)
        .toList();
  }

  Future<SharedCollections> getSharedCollections() async {
    final AlbumSortKey sortKey = localSettings.albumSortKey();
    final AlbumSortDirection sortDirection = localSettings.albumSortDirection();

    final List<Collection> outgoing = [];
    final List<Collection> incoming = [];
    final List<Collection> quickLinks = [];
    final List<Collection> collections = getCollectionsForUI(
      includedShared: true,
    );
    for (final c in collections) {
      if (c.owner.id == Configuration.instance.getUserID()) {
        if (c.hasSharees || c.hasLink && !c.isQuickLinkCollection()) {
          outgoing.add(c);
        } else if (c.isQuickLinkCollection()) {
          quickLinks.add(c);
        }
      } else {
        incoming.add(c);
      }
    }

    late Map<int, int> collectionIDToNewestPhotoTime;
    if (sortKey == AlbumSortKey.newestPhoto) {
      collectionIDToNewestPhotoTime = await CollectionsService.instance
          .getCollectionIDToNewestFileTime();
    }

    // Sort incoming collections, then separate pinned from rest
    incoming.sort((first, second) {
      // Sharee-pinned collections should come first
      final firstPinned = first.hasShareePinned();
      final secondPinned = second.hasShareePinned();
      if (firstPinned && !secondPinned) return -1;
      if (!firstPinned && secondPinned) return 1;

      int comparison;
      if (sortKey == AlbumSortKey.albumName) {
        comparison = compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      } else if (sortKey == AlbumSortKey.newestPhoto) {
        comparison =
            (collectionIDToNewestPhotoTime[second.id] ?? -1 * intMaxValue)
                .compareTo(
                  collectionIDToNewestPhotoTime[first.id] ?? -1 * intMaxValue,
                );
      } else {
        comparison = second.updationTime.compareTo(first.updationTime);
      }
      return sortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });

    outgoing.sort((first, second) {
      int comparison;
      if (sortKey == AlbumSortKey.albumName) {
        comparison = compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      } else if (sortKey == AlbumSortKey.newestPhoto) {
        comparison =
            (collectionIDToNewestPhotoTime[second.id] ?? -1 * intMaxValue)
                .compareTo(
                  collectionIDToNewestPhotoTime[first.id] ?? -1 * intMaxValue,
                );
      } else {
        comparison = second.updationTime.compareTo(first.updationTime);
      }
      return sortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });

    return SharedCollections(outgoing, incoming, quickLinks);
  }

  Future<SharedCollectionsAndMemoryLinks>
  getSharedCollectionsAndMemoryLinks() async {
    final collections = await getSharedCollections();
    try {
      final memoryLinks = await MemoryShareService.instance.listMemoryShares();
      return SharedCollectionsAndMemoryLinks(collections, memoryLinks);
    } catch (e, s) {
      _logger.severe("failed to load memory links", e, s);
      final localMemoryLinks = await MemoryShareService.instance
          .getLocalMemoryShares();
      return SharedCollectionsAndMemoryLinks(collections, localMemoryLinks);
    }
  }

  Future<List<Collection>> getCollectionForOnEnteSection() async {
    final AlbumSortKey sortKey = localSettings.albumSortKey();
    final AlbumSortDirection sortDirection = localSettings.albumSortDirection();
    final List<Collection> collections = CollectionsService.instance
        .getCollectionsForUI();
    final bool hasFavorites = FavoritesService.instance.hasFavorites();
    late Map<int, int> collectionIDToNewestPhotoTime;
    if (sortKey == AlbumSortKey.newestPhoto) {
      collectionIDToNewestPhotoTime = await CollectionsService.instance
          .getCollectionIDToNewestFileTime();
    }
    collections.sort((first, second) {
      int comparison;
      if (sortKey == AlbumSortKey.albumName) {
        comparison = compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      } else if (sortKey == AlbumSortKey.newestPhoto) {
        comparison =
            (collectionIDToNewestPhotoTime[second.id] ?? -1 * intMaxValue)
                .compareTo(
                  collectionIDToNewestPhotoTime[first.id] ?? -1 * intMaxValue,
                );
      } else {
        comparison = second.updationTime.compareTo(first.updationTime);
      }
      return sortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });
    final List<Collection> favorites = [];
    final List<Collection> pinned = [];
    final List<Collection> rest = [];
    for (final collection in collections) {
      if (collection.type == CollectionType.uncategorized ||
          collection.isQuickLinkCollection() ||
          collection.isHidden() ||
          collection.isArchived()) {
        continue;
      }
      if (collection.type == CollectionType.favorites) {
        // Hide fav collection if it's empty
        if (hasFavorites) {
          favorites.add(collection);
        }
      } else if (collection.isPinned) {
        pinned.add(collection);
      } else {
        rest.add(collection);
      }
    }

    return favorites + pinned + rest;
  }

  Future<List<Collection>> getCollectionForWidgetSelection() async {
    final AlbumSortKey sortKey = localSettings.albumSortKey();
    final AlbumSortDirection sortDirection = localSettings.albumSortDirection();
    const bool includeShared = true;
    final List<Collection> collections = CollectionsService.instance
        .getCollectionsForUI(includedShared: includeShared);
    final bool hasFavorites = FavoritesService.instance.hasFavorites();
    late Map<int, int> collectionIDToNewestPhotoTime;
    if (sortKey == AlbumSortKey.newestPhoto) {
      collectionIDToNewestPhotoTime = await CollectionsService.instance
          .getCollectionIDToNewestFileTime();
    }
    collections.sort((first, second) {
      int comparison;
      if (sortKey == AlbumSortKey.albumName) {
        comparison = compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      } else if (sortKey == AlbumSortKey.newestPhoto) {
        comparison =
            (collectionIDToNewestPhotoTime[second.id] ?? -1 * intMaxValue)
                .compareTo(
                  collectionIDToNewestPhotoTime[first.id] ?? -1 * intMaxValue,
                );
      } else {
        comparison = second.updationTime.compareTo(first.updationTime);
      }
      return sortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });
    final List<Collection> favorites = [];
    final List<Collection> pinned = [];
    final List<Collection> rest = [];
    for (final collection in collections) {
      if (collection.type == CollectionType.uncategorized ||
          collection.isQuickLinkCollection() ||
          collection.isHidden() ||
          collection.isArchived()) {
        continue;
      }
      if (collection.type == CollectionType.favorites) {
        // Hide fav collection if it's empty
        if (hasFavorites) {
          favorites.add(collection);
        }
      } else if (collection.isPinned) {
        pinned.add(collection);
      } else {
        rest.add(collection);
      }
    }

    return favorites + pinned + rest;
  }

  Future<List<Collection>> getCollectionsForRituals() async {
    final AlbumSortKey sortKey = localSettings.albumSortKey();
    final AlbumSortDirection sortDirection = localSettings.albumSortDirection();
    final List<Collection> collections = CollectionsService.instance
        .getCollectionsForUI();
    final bool hasFavorites = FavoritesService.instance.hasFavorites();
    late Map<int, int> collectionIDToNewestPhotoTime;
    if (sortKey == AlbumSortKey.newestPhoto) {
      collectionIDToNewestPhotoTime = await CollectionsService.instance
          .getCollectionIDToNewestFileTime();
    }
    collections.sort((first, second) {
      int comparison;
      if (sortKey == AlbumSortKey.albumName) {
        comparison = compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      } else if (sortKey == AlbumSortKey.newestPhoto) {
        comparison =
            (collectionIDToNewestPhotoTime[second.id] ?? -1 * intMaxValue)
                .compareTo(
                  collectionIDToNewestPhotoTime[first.id] ?? -1 * intMaxValue,
                );
      } else {
        comparison = second.updationTime.compareTo(first.updationTime);
      }
      return sortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });
    final List<Collection> favorites = [];
    final List<Collection> pinned = [];
    final List<Collection> rest = [];
    final int? userId = Configuration.instance.getUserID();
    for (final collection in collections) {
      if (collection.type == CollectionType.uncategorized ||
          collection.isQuickLinkCollection() ||
          (collection.isHidden()) ||
          ((userId == null || !collection.canAutoAdd(userId)))) {
        continue;
      }
      if (collection.type == CollectionType.favorites) {
        // Hide fav collection if it's empty
        if (hasFavorites) {
          favorites.add(collection);
        }
      } else if (collection.isPinned) {
        pinned.add(collection);
      } else {
        rest.add(collection);
      }
    }

    return favorites + pinned + rest;
  }

  User getFileOwner(int userID, int? collectionID) {
    if (_cachedUserIdToUser.containsKey(userID)) {
      return _cachedUserIdToUser[userID]!;
    }
    if (collectionID != null) {
      final Collection? collection = getCollectionByID(collectionID);
      if (collection != null) {
        if (collection.owner.id == userID) {
          _cachedUserIdToUser[userID] = collection.owner;
        } else {
          final matchingUser = collection.getSharees().firstWhereOrNull(
            (u) => u.id == userID,
          );
          if (matchingUser != null) {
            _cachedUserIdToUser[userID] = matchingUser;
          }
        }
      }
    }
    return _cachedUserIdToUser[userID] ??
        User(id: userID, email: "unknown@unknown.com");
  }

  Future<List<User>> getSharees(int collectionID) async {
    final sharees = await collectionShareGateway.getSharees(collectionID);
    _logger.info(sharees.toString());
    return sharees;
  }

  String getCastData(
    String castToken,
    Collection collection,
    String publicKey,
  ) {
    final String payload = jsonEncode({
      "collectionID": collection.id,
      "castToken": castToken,
      "collectionKey": CryptoUtil.bin2base64(getCollectionKey(collection.id)),
    });
    final encPayload = CryptoUtil.sealSync(
      CryptoUtil.base642bin(base64Encode(payload.codeUnits)),
      CryptoUtil.base642bin(publicKey),
    );
    return CryptoUtil.bin2base64(encPayload);
  }

  Future<List<User>> share(
    int collectionID,
    String email,
    String publicKey,
    CollectionParticipantRole role,
  ) async {
    final encryptedKey = CryptoUtil.sealSync(
      getCollectionKey(collectionID),
      CryptoUtil.base642bin(publicKey),
    );
    try {
      final sharees = await collectionShareGateway.share(
        collectionID: collectionID,
        email: email,
        encryptedKey: CryptoUtil.bin2base64(encryptedKey),
        role: role.toStringVal(),
      );
      _collectionIDToCollections[collectionID] =
          _collectionIDToCollections[collectionID]!.copyWith(sharees: sharees);
      unawaited(_db.insert([_collectionIDToCollections[collectionID]!]));
      RemoteSyncService.instance.sync(silently: true).ignore();
      return sharees;
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw SharingNotPermittedForFreeAccountsError();
      }
      rethrow;
    }
  }

  Future<List<User>> unshare(int collectionID, String email) async {
    try {
      final sharees = await collectionShareGateway.unshare(
        collectionID: collectionID,
        email: email,
      );
      _collectionIDToCollections[collectionID] =
          _collectionIDToCollections[collectionID]!.copyWith(sharees: sharees);
      unawaited(_db.insert([_collectionIDToCollections[collectionID]!]));
      RemoteSyncService.instance.sync(silently: true).ignore();
      return sharees;
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<void> trashNonEmptyCollection(Collection collection) async {
    try {
      await _turnOffDeviceFolderSync(collection);
      await collectionsGateway.deleteCollection(
        collectionID: collection.id,
        keepFiles: false,
      );
      await _handleCollectionDeletion(collection);
    } catch (e) {
      _logger.severe('failed to trash collection', e);
      rethrow;
    }
  }

  Future<void> _turnOffDeviceFolderSync(Collection collection) async {
    final deviceCollections = await _filesDB.getDeviceCollections();
    final Map<String, bool> devicePathIDsToUnSync = Map.fromEntries(
      deviceCollections
          .where((e) => e.shouldBackup && e.collectionID == collection.id)
          .map((e) => MapEntry(e.id, false)),
    );

    if (devicePathIDsToUnSync.isNotEmpty) {
      _logger.info(
        'turning off backup status for folders $devicePathIDsToUnSync',
      );
      await RemoteSyncService.instance.updateDeviceFolderSyncStatus(
        devicePathIDsToUnSync,
      );
    }
  }

  Future<void> trashEmptyCollection(
    Collection collection, {
    //  during bulk deletion, this event is not fired to avoid quick refresh
    //  of the collection gallery
    bool isBulkDelete = false,
  }) async {
    try {
      if (!isBulkDelete) {
        await _turnOffDeviceFolderSync(collection);
      }
      // While trashing empty albums, we must pass keepFiles flag as True.
      // The server will verify that the collection is actually empty before
      // deleting the files. If keepFiles is set as False and the collection
      // is not empty, then the files in the collections will be moved to trash.
      await collectionsGateway.deleteCollection(
        collectionID: collection.id,
        keepFiles: true,
      );
      if (isBulkDelete) {
        final deletedCollection = collection.copyWith(isDeleted: true);
        _collectionIDToCollections[collection.id] = deletedCollection;
        unawaited(_db.insert([deletedCollection]));
        await _cleanupSocialData(collection.id);
      } else {
        await _handleCollectionDeletion(collection);
      }
    } on DioException catch (e) {
      if (e.response != null) {
        debugPrint("Error " + e.response!.toString());
      }
      rethrow;
    } catch (e) {
      _logger.severe('failed to trash empty collection', e);
      rethrow;
    }
  }

  Future<void> _handleCollectionDeletion(Collection collection) async {
    await _filesDB.deleteCollection(collection.id);
    await _cleanupSocialData(collection.id);
    final deletedCollection = collection.copyWith(isDeleted: true);
    unawaited(_db.insert([deletedCollection]));
    _collectionIDToCollections[collection.id] = deletedCollection;
    Bus.instance.fire(
      CollectionUpdatedEvent(
        collection.id,
        <EnteFile>[],
        "delete_collection",
        type: EventType.deletedFromRemote,
      ),
    );
    sync().ignore();
    // not required once remote & local world are separate
    LocalSyncService.instance.syncAll().ignore();
  }

  Future<void> _cleanupSocialData(int collectionID, {int attempt = 0}) async {
    try {
      await SocialDB.instance.deleteCollectionData(collectionID);
    } catch (e, s) {
      if (attempt < _maxSocialCleanupRetries) {
        final backoff = Duration(
          milliseconds: 100 * pow(2, attempt + 1).toInt(),
        );
        _logger.info(
          'Failed to cleanup social data for $collectionID (${e.runtimeType}), '
          'retrying (attempt ${attempt + 1}/$_maxSocialCleanupRetries) in ${backoff.inMilliseconds}ms',
        );
        await Future.delayed(backoff);
        return _cleanupSocialData(collectionID, attempt: attempt + 1);
      }
      _logger.severe(
        'Failed to cleanup social data for $collectionID after $_maxSocialCleanupRetries retries',
        e,
        s,
      );
    }
  }

  Uint8List getCollectionKey(int collectionID) {
    if (!_cachedKeys.containsKey(collectionID)) {
      final collection = _collectionIDToCollections[collectionID];
      if (collection == null) {
        // Async fetch for collection. A collection might be
        // missing from older clients when we used to delete the collection
        // from db. For trashed files, we need collection data for decryption.
        fetchCollectionByID(collectionID);
        throw AssertionError('collectionID $collectionID is not cached');
      }
      _cachedKeys[collectionID] = _getAndCacheDecryptedKey(
        collection,
        source: "getCollectionKey",
      );
    }
    return _cachedKeys[collectionID]!;
  }

  Uint8List getPublicCollectionKey(int collectionID) {
    final collectionKey = _cachedPublicCollectionKeys[collectionID];
    if (collectionKey == null) {
      throw StateError("public collection key $collectionID is not cached");
    }
    return collectionKey;
  }

  String getPublicUrl(Collection c) {
    final PublicURL url = c.publicURLs.firstOrNull!;
    Uri publicUrl = Uri.parse(url.url);

    final int? currentUserID = Configuration.instance.getUserID();
    final bool isOwner = currentUserID != null && currentUserID == c.owner.id;
    final String customDomain = flagService.customDomain;
    final bool applyCustomDomain = isOwner && customDomain.isNotEmpty;

    // Replace with custom domain if configured for the owner
    if (applyCustomDomain) {
      publicUrl = publicUrl.replace(
        host: customDomain,
        scheme: "https",
        port: 443,
      );
    }

    // Get the collection key for the URL fragment
    final String collectionKey = Base58Encode(
      CollectionsService.instance.getCollectionKey(c.id),
    );

    // Build the final URL
    String finalUrl = publicUrl.toString();

    // Handle IDN domains - if the host was percent-encoded by Uri.replace,
    // decode it for user-friendly display
    if (applyCustomDomain && publicUrl.host.contains('%')) {
      final decodedHost = Uri.decodeComponent(publicUrl.host);
      finalUrl = finalUrl.replaceFirst(publicUrl.host, decodedHost);
    }

    return "$finalUrl#$collectionKey";
  }

  String getEmbedHtml(Collection c) {
    final PublicURL url = c.publicURLs.firstOrNull!;
    Uri publicUrl = Uri.parse(url.url);

    // Replace with embed URL if configured
    final String embedUrl = flagService.embedUrl;
    if (embedUrl.isNotEmpty) {
      final Uri embedUri = Uri.parse(embedUrl);
      publicUrl = publicUrl.replace(
        host: embedUri.host,
        scheme: embedUri.scheme,
        port: embedUri.hasPort
            ? embedUri.port
            : (embedUri.scheme == 'https' ? 443 : 80),
      );
    }

    // Get the collection key for the URL fragment
    final String collectionKey = Base58Encode(
      CollectionsService.instance.getCollectionKey(c.id),
    );

    // Build the final URL
    String finalUrl = publicUrl.toString();

    // Handle IDN domains - if the host was percent-encoded by Uri.replace,
    // decode it for user-friendly display
    if (embedUrl.isNotEmpty && publicUrl.host.contains('%')) {
      final decodedHost = Uri.decodeComponent(publicUrl.host);
      finalUrl = finalUrl.replaceFirst(publicUrl.host, decodedHost);
    }

    final String embedHtmlUrl = "$finalUrl#$collectionKey";
    return '<iframe src="$embedHtmlUrl" width="800" height="600" frameborder="0" allowfullscreen></iframe>';
  }

  Uint8List _getAndCacheDecryptedKey(
    Collection collection, {
    String source = "",
  }) {
    if (_cachedKeys.containsKey(collection.id)) {
      return _cachedKeys[collection.id]!;
    }
    debugPrint(
      "Compute collection decryption key for ${collection.id} source"
      " $source",
    );
    final encryptedKey = CryptoUtil.base642bin(collection.encryptedKey);
    Uint8List? collectionKey;
    if (collection.owner.id == _config.getUserID()) {
      // If the collection is owned by the user, decrypt with the master key
      if (_config.getKey() == null) {
        // Possible during AppStore account migration, where SecureStorage
        // would become inaccessible to the new Developer Account
        throw Exception("key can not be null");
      }
      collectionKey = CryptoUtil.decryptSync(
        encryptedKey,
        _config.getKey()!,
        CryptoUtil.base642bin(collection.keyDecryptionNonce!),
      );
    } else {
      // If owned by a different user, decrypt with the public key
      collectionKey = CryptoUtil.openSealSync(
        encryptedKey,
        CryptoUtil.base642bin(_config.getKeyAttributes()!.publicKey),
        _config.getSecretKey()!,
      );
    }
    _cachedKeys[collection.id] = collectionKey;
    return collectionKey;
  }

  Future<void> rename(Collection collection, String newName) async {
    try {
      // Note: when collection created to sharing few files is renamed
      // convert that collection to a regular collection type.
      if (collection.isQuickLinkCollection()) {
        await updateMagicMetadata(collection, {"subType": 0});
      }
      final encryptedName = CryptoUtil.encryptSync(
        utf8.encode(newName),
        getCollectionKey(collection.id),
      );
      await collectionsGateway.renameCollection(
        collectionID: collection.id,
        encryptedName: CryptoUtil.bin2base64(encryptedName.encryptedData!),
        nameDecryptionNonce: CryptoUtil.bin2base64(encryptedName.nonce!),
      );
      collection.setName(newName);
      _collectionIDToCollections[collection.id] = collection;
      Bus.instance.fire(
        CollectionUpdatedEvent(
          collection.id,
          <EnteFile>[],
          "rename_collection",
        ),
      );
      sync().ignore();
    } catch (e, s) {
      _logger.warning("failed to rename collection", e, s);
      rethrow;
    }
  }

  Future<void> leaveAlbum(Collection collection) async {
    try {
      await collectionsGateway.leaveCollection(collection.id);
      await _handleCollectionDeletion(collection);
    } catch (e, s) {
      _logger.severe("failed to leave collection", e, s);
      rethrow;
    }
  }

  Future<void> updateMagicMetadata(
    Collection collection,
    Map<String, dynamic> newMetadataUpdate,
  ) async {
    final int ownerID = Configuration.instance.getUserID()!;
    try {
      if (collection.owner.id != ownerID) {
        throw AssertionError("cannot modify albums not owned by you");
      }
      // read the existing magic metadata and apply new updates to existing data
      // current update is simple replace. This will be enhanced in the future,
      // as required.
      final Map<String, dynamic> jsonToUpdate = jsonDecode(
        collection.mMdEncodedJson ?? '{}',
      );
      newMetadataUpdate.forEach((key, value) {
        jsonToUpdate[key] = value;
      });

      final key = getCollectionKey(collection.id);
      final encryptedMMd = await CryptoUtil.encryptChaCha(
        utf8.encode(jsonEncode(jsonToUpdate)),
        key,
      );
      // for required field, the json validator on golang doesn't treat 0 as valid
      // value. Instead of changing version to ptr, decided to start version with 1.
      final int currentVersion = max(collection.mMdVersion, 1);
      final params = UpdateMagicMetadataRequest(
        id: collection.id,
        magicMetadata: MetadataRequest(
          version: currentVersion,
          count: jsonToUpdate.length,
          data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
          header: CryptoUtil.bin2base64(encryptedMMd.header!),
        ),
      );
      await collectionsGateway.updateMagicMetadata(params);
      // update the local information so that it's reflected on UI
      collection.mMdEncodedJson = jsonEncode(jsonToUpdate);
      collection.magicMetadata = CollectionMagicMetadata.fromJson(jsonToUpdate);
      collection.mMdVersion = currentVersion + 1;
      _collectionIDToCollections[collection.id] = collection;

      // trigger sync to fetch the latest collection state from server
      sync().ignore();
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 409) {
        _logger.severe('collection magic data out of sync');
        sync().ignore();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to sync magic metadata", e, s);
      rethrow;
    }
  }

  Future<void> updatePublicMagicMetadata(
    Collection collection,
    Map<String, dynamic> newMetadataUpdate,
  ) async {
    final int ownerID = Configuration.instance.getUserID()!;
    try {
      if (collection.owner.id != ownerID) {
        throw AssertionError("cannot modify albums not owned by you");
      }
      // read the existing magic metadata and apply new updates to existing data
      // current update is simple replace. This will be enhanced in the future,
      // as required.
      final Map<String, dynamic> jsonToUpdate = jsonDecode(
        collection.mMdPubEncodedJson ?? '{}',
      );
      newMetadataUpdate.forEach((key, value) {
        jsonToUpdate[key] = value;
      });

      final key = getCollectionKey(collection.id);
      final encryptedMMd = await CryptoUtil.encryptChaCha(
        utf8.encode(jsonEncode(jsonToUpdate)),
        key,
      );
      // for required field, the json validator on golang doesn't treat 0 as valid
      // value. Instead of changing version to ptr, decided to start version with 1.
      final int currentVersion = max(collection.mMbPubVersion, 1);
      final params = UpdateMagicMetadataRequest(
        id: collection.id,
        magicMetadata: MetadataRequest(
          version: currentVersion,
          count: jsonToUpdate.length,
          data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
          header: CryptoUtil.bin2base64(encryptedMMd.header!),
        ),
      );
      await collectionsGateway.updatePublicMagicMetadata(params);
      // update the local information so that it's reflected on UI
      collection.mMdPubEncodedJson = jsonEncode(jsonToUpdate);
      collection.pubMagicMetadata = CollectionPubMagicMetadata.fromJson(
        jsonToUpdate,
      );
      collection.mMbPubVersion = currentVersion + 1;
      _cacheLocalPathAndCollection(collection);
      // trigger sync to fetch the latest collection state from server
      sync().ignore();
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 409) {
        _logger.severe('collection magic data out of sync');
        sync().ignore();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to sync magic metadata", e, s);
      rethrow;
    }
  }

  Future<void> updateShareeMagicMetadata(
    Collection collection,
    Map<String, dynamic> newMetadataUpdate,
  ) async {
    final int ownerID = Configuration.instance.getUserID()!;
    try {
      if (collection.owner.id == ownerID) {
        throw AssertionError(
          "cannot modify sharee settings for albums owned "
          "by you",
        );
      }
      // read the existing magic metadata and apply new updates to existing data
      // current update is simple replace. This will be enhanced in the future,
      // as required.
      final Map<String, dynamic> jsonToUpdate = jsonDecode(
        collection.sharedMmdJson ?? '{}',
      );
      newMetadataUpdate.forEach((key, value) {
        jsonToUpdate[key] = value;
      });

      final key = getCollectionKey(collection.id);
      final encryptedMMd = await CryptoUtil.encryptChaCha(
        utf8.encode(jsonEncode(jsonToUpdate)),
        key,
      );
      // for required field, the json validator on golang doesn't treat 0 as valid
      // value. Instead of changing version to ptr, decided to start version with 1.
      final int currentVersion = max(collection.sharedMmdVersion, 1);
      final params = UpdateMagicMetadataRequest(
        id: collection.id,
        magicMetadata: MetadataRequest(
          version: currentVersion,
          count: jsonToUpdate.length,
          data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
          header: CryptoUtil.bin2base64(encryptedMMd.header!),
        ),
      );
      await collectionsGateway.updateShareeMagicMetadata(params);
      // update the local information so that it's reflected on UI
      collection.sharedMmdJson = jsonEncode(jsonToUpdate);
      collection.sharedMagicMetadata = ShareeMagicMetadata.fromJson(
        jsonToUpdate,
      );
      collection.sharedMmdVersion = currentVersion + 1;
      _cacheLocalPathAndCollection(collection);
      // trigger sync to fetch the latest collection state from server
      sync().ignore();
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 409) {
        _logger.severe('collection magic data out of sync');
        sync().ignore();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to sync magic metadata", e, s);
      rethrow;
    }
  }

  Future<void> createShareUrl(
    Collection collection, {
    bool enableCollect = false,
    bool enableJoin = false,
  }) async {
    try {
      final publicUrl = await collectionShareGateway.createShareUrl(
        collectionID: collection.id,
        enableCollect: enableCollect,
        enableJoin: enableJoin,
      );
      collection.publicURLs.add(publicUrl);
      await _db.insert(List.from([collection]));
      _collectionIDToCollections[collection.id] = collection;
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, <EnteFile>[], "shareUrL"),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw SharingNotPermittedForFreeAccountsError();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to rename collection", e, s);
      rethrow;
    }
  }

  Future<void> updateShareUrl(
    Collection collection,
    Map<String, dynamic> prop,
  ) async {
    try {
      final publicUrl = await collectionShareGateway.updateShareUrl(
        collectionID: collection.id,
        props: prop,
      );
      // remove existing url information
      collection.publicURLs.clear();
      collection.publicURLs.add(publicUrl);
      await _db.insert(List.from([collection]));
      _collectionIDToCollections[collection.id] = collection;
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, <EnteFile>[], "updateUrl"),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw SharingNotPermittedForFreeAccountsError();
      }
      if (e.response?.statusCode == 403 &&
          e.response?.data?['code'] == 'LINK_EDIT_NOT_ALLOWED') {
        throw LinkEditNotAllowedError();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to update ShareUrl", e, s);
      rethrow;
    }
  }

  Future<void> disableShareUrl(Collection collection) async {
    try {
      await collectionShareGateway.deleteShareUrl(collection.id);
      collection.publicURLs.clear();
      await _db.insert(List.from([collection]));
      _collectionIDToCollections[collection.id] = collection;
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, <EnteFile>[], "disableShareUrl"),
      );
    } on DioException catch (e) {
      _logger.info(e);
      rethrow;
    }
  }

  Future<List<Collection>> _fetchCollections(int sinceTime) async {
    try {
      final response = await collectionsGateway.getAll(
        sinceTime: sinceTime,
        source: AppLifecycleService.instance.isForeground ? "fg" : "bg",
      );
      final List<Collection> collections = [];
      final c = response["collections"];
      for (final collectionData in c) {
        final Collection collection = await _fromRemoteCollection(
          collectionData,
        );
        collections.add(collection);
      }
      return collections;
    } catch (e, s) {
      _logger.warning("Failed to fetch collections", e, s);
      if (e is DioException && e.response?.statusCode == 401) {
        throw UnauthorizedError();
      }
      rethrow;
    }
  }

  Future<List<CollectionAction>> fetchPendingRemovalActions() async {
    try {
      final response = await collectionsGateway.fetchPendingRemovalActions();
      final List<dynamic> rawActions =
          (response["actions"] as List<dynamic>?) ?? const [];
      final actions = rawActions
          .map(
            (dynamic action) => CollectionAction.fromJson(
              Map<String, dynamic>.from(action as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false);
      _logger.info(
        "Fetched ${actions.length} pending collection removal actions",
      );
      return actions;
    } catch (e, s) {
      _logger.warning("Failed to fetch pending removal actions", e, s);
      rethrow;
    }
  }

  Future<List<int>> fetchDeleteSuggestionFileIDs() async {
    try {
      final response = await collectionsGateway.fetchDeleteSuggestions();
      final List<dynamic> rawActions =
          (response["actions"] as List<dynamic>?) ?? const [];
      final actions = rawActions
          .map(
            (dynamic action) => CollectionAction.fromJson(
              Map<String, dynamic>.from(action as Map<dynamic, dynamic>),
            ),
          )
          .toList(growable: false);
      final Set<int> uniqueFileIDs = <int>{};
      for (final action in actions) {
        if (action.fileID != null) {
          uniqueFileIDs.add(action.fileID!);
        }
      }
      _logger.info(
        "Fetched ${uniqueFileIDs.length} unique delete suggestion file IDs",
      );
      return uniqueFileIDs.toList();
    } catch (e, s) {
      _logger.warning("Failed to fetch delete suggestion actions", e, s);
      rethrow;
    }
  }

  Future<void> rejectDeleteSuggestions(List<int> fileIDs) async {
    if (fileIDs.isEmpty) {
      return;
    }
    try {
      await collectionsGateway.rejectDeleteSuggestions(fileIDs);
    } catch (e, s) {
      _logger.warning("Failed to reject delete suggestions", e, s);
      rethrow;
    }
  }

  Uint8List _decodePublicCollectionKey(String albumKey) {
    if (albumKey.isEmpty) {
      throw const FormatException("Missing public collection key");
    }
    final collectionKey = Uint8List.fromList(Base58Decode(albumKey));
    if (collectionKey.length != _collectionKeyLength) {
      throw const FormatException("Invalid public collection key length");
    }
    return collectionKey;
  }

  Future<void> _decryptPublicCollectionFields(
    Collection collection,
    Map<String, dynamic> collectionData,
    Uint8List collectionKey,
  ) async {
    collection.setName(
      _decryptCollectionNameWithKey(collection, collectionKey),
    );
    if (collectionData['pubMagicMetadata'] != null) {
      final utfEncodedMmd = await CryptoUtil.decryptChaCha(
        CryptoUtil.base642bin(collectionData['pubMagicMetadata']['data']),
        collectionKey,
        CryptoUtil.base642bin(collectionData['pubMagicMetadata']['header']),
      );
      collection.mMdPubEncodedJson = utf8.decode(utfEncodedMmd);
      collection.mMbPubVersion = collectionData['pubMagicMetadata']['version'];
      collection.pubMagicMetadata = CollectionPubMagicMetadata.fromEncodedJson(
        collection.mMdPubEncodedJson ?? '{}',
      );
    }
  }

  void _clearPublicCollectionState(int collectionID) {
    _cachedPublicAlbumToken.remove(collectionID);
    _cachedPublicAlbumJWT.remove(collectionID);
    _cachedPublicCollectionID.removeWhere((id) => id == collectionID);
    _cachedPublicAlbumKey.remove(collectionID);
    _cachedPublicCollectionKeys.remove(collectionID);
  }

  Future<Collection?> getCollectionFromPublicLink(
    BuildContext context,
    Uri uri,
  ) async {
    final String? authToken = _resolvePublicAlbumAccessToken(uri);
    final String albumKey = uri.fragment;
    try {
      final responseData = await collectionShareGateway.getPublicCollectionInfo(
        authToken!,
      );

      final collectionData = responseData["collection"];
      final Collection collection = Collection.fromMap(collectionData);
      final existingCollection = getCollectionByID(collection.id);
      final currentUserID = _config.getUserID() ?? -1;
      final shouldUseAuthenticatedKey =
          collection.isOwner(currentUserID) ||
          (existingCollection != null && !existingCollection.isDeleted);

      if (shouldUseAuthenticatedKey) {
        _clearPublicCollectionState(collection.id);
        final keySourceCollection =
            existingCollection != null && !existingCollection.isDeleted
            ? existingCollection
            : collection;
        final collectionKey = _getAndCacheDecryptedKey(
          keySourceCollection,
          source: "publicLinkExistingCollection",
        );
        await _decryptPublicCollectionFields(
          collection,
          collectionData,
          collectionKey,
        );
        return collection;
      }

      final collectionKey = _decodePublicCollectionKey(albumKey);
      await _decryptPublicCollectionFields(
        collection,
        collectionData,
        collectionKey,
      );
      _cachedPublicCollectionKeys[collection.id] = collectionKey;
      _cachedPublicAlbumToken[collection.id] = authToken;
      _cachedPublicCollectionID.removeWhere((id) => id == collection.id);
      _cachedPublicCollectionID.add(collection.id);
      _cachedPublicAlbumKey[collection.id] = albumKey;
      _cachedPublicAlbumJWT.remove(collection.id);
      return collection;
    } on PublicCollectionInfoExpiredException catch (e, s) {
      _logger.warning("Public collection link expired", e, s);
      if (!context.mounted) return null;
      await showInfoDialog(
        context,
        title: AppLocalizations.of(context).linkExpired,
        body: AppLocalizations.of(
          context,
        ).theLinkYouAreTryingToAccessHasExpired,
      );
      return null;
    } on PublicCollectionDeviceLimitExceededException catch (e, s) {
      _logger.warning("Public collection link device limit reached", e, s);
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).canNotOpenTitle,
        AppLocalizations.of(context).linkRequestLimitExceeded,
      );
      return null;
    } on PublicCollectionRateLimitedException catch (e, s) {
      _logger.warning("Public collection link request rate limited", e, s);
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).canNotOpenTitle,
        AppLocalizations.of(context).linkRequestLimitExceeded,
      );
      return null;
    } on PublicCollectionInfoUnauthorizedException catch (e, s) {
      _logger.warning("Public collection link is unauthorized", e, s);
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).canNotOpenTitle,
        AppLocalizations.of(context).canNotOpenBody,
      );
      return null;
    } catch (e, s) {
      _logger.warning("Failed to fetch public collection", e, s);
      _logger.severe("Failed to fetch public collection");
      if (context.mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
      rethrow;
    }
  }

  Future<bool> verifyPublicCollectionPassword(
    BuildContext context,
    String passwordHash,
    int collectionID,
  ) async {
    final authToken = getSharedPublicAlbumToken(collectionID);
    if (authToken == null) {
      _logger.warning("Auth token not found for collection $collectionID");
      return false;
    }
    try {
      final jwtToken = await collectionShareGateway.verifyPublicPassword(
        authToken: authToken,
        passwordHash: passwordHash,
      );
      await setPublicAlbumTokenJWT(collectionID, jwtToken);
      return true;
    } catch (e) {
      _logger.warning("Failed to verify public collection password $e");
      if (!context.mounted) return false;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).incorrectPasswordTitle,
        AppLocalizations.of(context).pleaseTryAgain,
      );
      return false;
    }
  }

  Future<void> joinPublicCollection(
    BuildContext context,
    int collectionID,
  ) async {
    final albumKey = getSharedPublicAlbumKey(collectionID);
    if (albumKey.isEmpty) {
      throw Exception("Collection key not found");
    }
    final collectionKey = getPublicCollectionKey(collectionID);
    final encryptedKey = CryptoUtil.sealSync(
      collectionKey,
      CryptoUtil.base642bin(
        Configuration.instance.getKeyAttributes()!.publicKey,
      ),
    );
    await collectionsGateway.joinViaLink(
      collectionID: collectionID,
      encryptedKey: CryptoUtil.bin2base64(encryptedKey),
      headers: publicCollectionHeaders(collectionID),
    );
  }

  String getSharedPublicAlbumKey(int collectionID) {
    if (_cachedPublicAlbumKey.containsKey(collectionID)) {
      return _cachedPublicAlbumKey[collectionID]!;
    }
    return "";
  }

  String? getSharedPublicAlbumToken(int collectionID) {
    return _cachedPublicAlbumToken[collectionID];
  }

  Map<String, String> publicCollectionHeaders(int collectionID) {
    final String? albumToken = _cachedPublicAlbumToken[collectionID];
    final String? albumJwtToken = _cachedPublicAlbumJWT[collectionID];
    return {
      "X-Auth-Access-Token": ?albumToken,
      "X-Auth-Access-Token-JWT": ?albumJwtToken,
    };
  }

  /// Is a public link opened in the app via deeplink
  bool isSharedPublicLink(int collectionID) {
    return _cachedPublicCollectionID.contains(collectionID);
  }

  Future<void> setPublicAlbumTokenJWT(int collectionID, String token) async {
    _cachedPublicAlbumJWT[collectionID] = token;
  }

  Future<Collection> _fromRemoteCollection(
    Map<String, dynamic> collectionData,
  ) async {
    final Collection collection = Collection.fromMap(collectionData);
    if (!collection.isDeleted) {
      final collectionKey = _getAndCacheDecryptedKey(
        collection,
        source: "fetchDecryptMeta",
      );
      if (collectionData['magicMetadata'] != null) {
        final utfEncodedMmd = await CryptoUtil.decryptChaCha(
          CryptoUtil.base642bin(collectionData['magicMetadata']['data']),
          collectionKey,
          CryptoUtil.base642bin(collectionData['magicMetadata']['header']),
        );
        collection.mMdEncodedJson = utf8.decode(utfEncodedMmd);
        collection.mMdVersion = collectionData['magicMetadata']['version'];
        collection.magicMetadata = CollectionMagicMetadata.fromEncodedJson(
          collection.mMdEncodedJson ?? '{}',
        );
      }

      if (collectionData['pubMagicMetadata'] != null) {
        final utfEncodedMmd = await CryptoUtil.decryptChaCha(
          CryptoUtil.base642bin(collectionData['pubMagicMetadata']['data']),
          collectionKey,
          CryptoUtil.base642bin(collectionData['pubMagicMetadata']['header']),
        );
        collection.mMdPubEncodedJson = utf8.decode(utfEncodedMmd);
        collection.mMbPubVersion =
            collectionData['pubMagicMetadata']['version'];
        collection.pubMagicMetadata =
            CollectionPubMagicMetadata.fromEncodedJson(
              collection.mMdPubEncodedJson ?? '{}',
            );
      }
      if (collectionData['sharedMagicMetadata'] != null) {
        final utfEncodedMmd = await CryptoUtil.decryptChaCha(
          CryptoUtil.base642bin(collectionData['sharedMagicMetadata']['data']),
          collectionKey,
          CryptoUtil.base642bin(
            collectionData['sharedMagicMetadata']['header'],
          ),
        );
        collection.sharedMmdJson = utf8.decode(utfEncodedMmd);
        collection.sharedMmdVersion =
            collectionData['sharedMagicMetadata']['version'];
        collection.sharedMagicMetadata = ShareeMagicMetadata.fromEncodedJson(
          collection.sharedMmdJson ?? '{}',
        );
      }
    }
    collection.setName(_getDecryptedCollectionName(collection));
    if (collection.canLinkToDevicePath(_config.getUserID()!)) {
      collection.decryptedPath = (_decryptCollectionPath(collection));
    }
    return collection;
  }

  Collection? getCollectionByID(int collectionID) {
    return _collectionIDToCollections[collectionID];
  }

  Future<Collection> createAlbum(String albumName) async {
    final collectionKey = CryptoUtil.generateKey();
    final encryptedKeyData = CryptoUtil.encryptSync(
      collectionKey,
      _config.getKey()!,
    );
    final encryptedName = CryptoUtil.encryptSync(
      utf8.encode(albumName),
      collectionKey,
    );
    final collection = await createAndCacheCollection(
      CreateRequest(
        encryptedKey: CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
        keyDecryptionNonce: CryptoUtil.bin2base64(encryptedKeyData.nonce!),
        encryptedName: CryptoUtil.bin2base64(encryptedName.encryptedData!),
        nameDecryptionNonce: CryptoUtil.bin2base64(encryptedName.nonce!),
        type: CollectionType.album,
        attributes: CollectionAttributes(),
      ),
    );
    return collection;
  }

  Future<Collection> fetchCollectionByID(int collectionID) async {
    try {
      _logger.info('fetching collectionByID $collectionID');
      final collectionData = await collectionsGateway.getCollection(
        collectionID,
      );
      final collection = await _fromRemoteCollection(collectionData);
      await _db.insert(List.from([collection]));
      _cacheLocalPathAndCollection(collection);
      return collection;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        throw UnauthorizedError();
      }
      _logger.severe('failed to fetch collection: $collectionID', e);
      rethrow;
    }
  }

  Future<Collection> getOrCreateForPath(String path) async {
    if (_localPathToCollectionID.containsKey(path)) {
      final Collection? cachedCollection =
          _collectionIDToCollections[_localPathToCollectionID[path]];
      if (cachedCollection != null &&
          cachedCollection.canLinkToDevicePath(_config.getUserID()!)) {
        return cachedCollection;
      }
    }
    final collectionKey = CryptoUtil.generateKey();
    final encryptedKeyData = CryptoUtil.encryptSync(
      collectionKey,
      _config.getKey()!,
    );
    final encryptedPath = CryptoUtil.encryptSync(
      utf8.encode(path),
      collectionKey,
    );
    final collection = await createAndCacheCollection(
      CreateRequest(
        encryptedKey: CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
        keyDecryptionNonce: CryptoUtil.bin2base64(encryptedKeyData.nonce!),
        encryptedName: CryptoUtil.bin2base64(encryptedPath.encryptedData!),
        nameDecryptionNonce: CryptoUtil.bin2base64(encryptedPath.nonce!),
        type: CollectionType.folder,
        attributes: CollectionAttributes(
          encryptedPath: CryptoUtil.bin2base64(encryptedPath.encryptedData!),
          pathDecryptionNonce: CryptoUtil.bin2base64(encryptedPath.nonce!),
          version: 1,
        ),
      ),
    );
    return collection;
  }

  Future<void> addOrCopyToCollection(
    int dstCollectionID,
    List<EnteFile> files, {
    bool toCopy = true,
  }) async {
    final splitResult = FilesSplit.split(files, _config.getUserID()!);
    if (splitResult.pendingUploads.isNotEmpty) {
      throw ArgumentError('File should be already uploaded');
    }
    if (splitResult.ownedByCurrentUser.isNotEmpty) {
      await _addToCollection(dstCollectionID, splitResult.ownedByCurrentUser);
    }
    if (splitResult.ownedByOtherUsers.isNotEmpty && toCopy) {
      final (filesToAdd, filesToCopy) = (await _splitFilesToAddAndCopy(
        splitResult.ownedByOtherUsers,
      ));

      if (filesToAdd.isNotEmpty) {
        _logger.info(
          "found existing ${filesToAdd.length} files with same hash, adding symlinks",
        );
        await _addToCollection(dstCollectionID, filesToAdd);
      }

      if (filesToCopy.isNotEmpty) {
        final dstCollection = _collectionIDToCollections[dstCollectionID];
        final currentUserID = _config.getUserID()!;
        final shouldCopyViaUncategorized =
            dstCollection != null &&
            !dstCollection.isOwner(currentUserID) &&
            dstCollection.canAdd(currentUserID);

        final int copyDestinationCollectionID;
        if (shouldCopyViaUncategorized) {
          final uncategorizedCollection = await CollectionsService.instance
              .getUncategorizedCollection();
          copyDestinationCollectionID = uncategorizedCollection.id;
        } else {
          copyDestinationCollectionID = dstCollectionID;
        }

        final copiedFiles = await _copyFilesToCollection(
          filesToCopy,
          dstCollectionID: copyDestinationCollectionID,
        );

        if (shouldCopyViaUncategorized) {
          await _addToCollection(dstCollectionID, copiedFiles);
        }
      }
    }
  }

  Future<List<EnteFile>> _copyFilesToCollection(
    List<EnteFile> filesToCopy, {
    required int dstCollectionID,
  }) async {
    final copiedFiles = <EnteFile>[];
    final filesByCollection = <int, List<EnteFile>>{};
    final fileSeenByCollection = <int, Set<int>>{};

    for (final file in filesToCopy) {
      fileSeenByCollection.putIfAbsent(file.collectionID!, () => <int>{});
      if (fileSeenByCollection[file.collectionID]!.contains(
        file.uploadedFileID,
      )) {
        _logger.warning(
          "skip copy, duplicate ID: ${file.uploadedFileID} in collection "
          "${file.collectionID}",
        );
        continue;
      }
      final copiedFile = file.copyWith();
      filesByCollection
          .putIfAbsent(file.collectionID!, () => [])
          .add(copiedFile);
      fileSeenByCollection[file.collectionID]!.add(file.uploadedFileID!);
      copiedFiles.add(copiedFile);
    }

    for (final entry in filesByCollection.entries) {
      final srcCollectionID = entry.key;
      final files = entry.value;
      await _copyToCollection(
        files,
        dstCollectionID: dstCollectionID,
        srcCollectionID: srcCollectionID,
      );
    }

    return copiedFiles;
  }

  Future<void> _addToCollection(int collectionID, List<EnteFile> files) async {
    final containsUploadedFile = files.any((e) => e.isUploaded);
    if (containsUploadedFile) {
      final existingFileIDsInCollection = await FilesDB.instance
          .getUploadedFileIDs(collectionID);
      files.removeWhere(
        (element) =>
            element.uploadedFileID != null &&
            existingFileIDsInCollection.contains(element.uploadedFileID),
      );
    }
    if (files.isEmpty || !containsUploadedFile) {
      _logger.info("nothing to add to the collection");
      return;
    }
    final anyFileOwnedByOther = files.any(
      (e) => e.ownerID != null && e.ownerID != _config.getUserID(),
    );
    if (anyFileOwnedByOther) {
      throw ArgumentError(
        'Cannot add files owned by other users, they should be copied',
      );
    }

    final batchedFiles = files.chunks(batchSize);
    for (final batch in batchedFiles) {
      final fileItems = <CollectionFileItem>[];
      for (final file in batch) {
        final fileKey = getFileKey(file);
        file.generatedID =
            null; // So that a new entry is created in the FilesDB
        file.collectionID = collectionID;
        final encryptedKeyData = CryptoUtil.encryptSync(
          fileKey,
          getCollectionKey(collectionID),
        );
        file.encryptedKey = CryptoUtil.bin2base64(
          encryptedKeyData.encryptedData!,
        );
        file.keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedKeyData.nonce!,
        );
        fileItems.add(
          CollectionFileItem(
            file.uploadedFileID!,
            file.encryptedKey!,
            file.keyDecryptionNonce!,
          ),
        );
      }

      try {
        await collectionFilesGateway.addFiles(collectionID, fileItems);
        await _filesDB.insertMultiple(batch);
        Bus.instance.fire(CollectionUpdatedEvent(collectionID, batch, "addTo"));
      } catch (e) {
        rethrow;
      }
    }
  }

  // This method is used to add files to a collection without firing any events.
  // Unlike `addToCollection`, this method does not update the `FilesDB` or modify
  // the `EnteFile` objects passed to it. This is only used during dedupe process
  // for adding files to a collection without firing any events.
  Future<void> addSilentlyToCollection(
    int collectionID,
    List<EnteFile> files,
  ) async {
    if (files.isEmpty) {
      return;
    }
    // as any non uploaded file
    final pendingUpload = files.any(
      (element) => element.uploadedFileID == null,
    );
    if (pendingUpload) {
      throw ArgumentError('Can only add uploaded files silently');
    }
    final existingFileIDsInCollection = await FilesDB.instance
        .getUploadedFileIDs(collectionID);
    files.removeWhere(
      (element) => existingFileIDsInCollection.contains(element.uploadedFileID),
    );
    if (files.isEmpty) {
      _logger.info("nothing to add to the collection");
      return;
    }
    final batchedFiles = files.chunks(batchSize);
    for (final batch in batchedFiles) {
      final fileItems = <CollectionFileItem>[];
      for (final file in batch) {
        final int uploadedFileID = file.uploadedFileID!;
        final fileKey = getFileKey(file);
        final encryptedKeyData = CryptoUtil.encryptSync(
          fileKey,
          getCollectionKey(collectionID),
        );
        final String encryptedKey = CryptoUtil.bin2base64(
          encryptedKeyData.encryptedData!,
        );
        final String keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedKeyData.nonce!,
        );
        fileItems.add(
          CollectionFileItem(uploadedFileID, encryptedKey, keyDecryptionNonce),
        );
      }
      try {
        await collectionFilesGateway.addFiles(collectionID, fileItems);
      } catch (e) {
        _logger.warning('failed to add files to collection', e);
        rethrow;
      }
    }
  }

  Future<void> _copyToCollection(
    List<EnteFile> files, {
    required int dstCollectionID,
    required int srcCollectionID,
  }) async {
    _validateCopyInput(dstCollectionID, srcCollectionID, files);
    final batchedFiles = files.chunks(batchSizeCopy);
    for (final batch in batchedFiles) {
      final fileItems = <CollectionFileItem>[];
      for (final batchFile in batch) {
        final fileKey = getFileKey(batchFile);
        final encryptedKeyData = CryptoUtil.encryptSync(
          fileKey,
          getCollectionKey(dstCollectionID),
        );
        batchFile.encryptedKey = CryptoUtil.bin2base64(
          encryptedKeyData.encryptedData!,
        );
        batchFile.keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedKeyData.nonce!,
        );
        fileItems.add(
          CollectionFileItem(
            batchFile.uploadedFileID!,
            batchFile.encryptedKey!,
            batchFile.keyDecryptionNonce!,
          ),
        );
      }

      try {
        final oldToCopiedFileIDMap = await collectionFilesGateway.copyFiles(
          dstCollectionID: dstCollectionID,
          srcCollectionID: srcCollectionID,
          files: fileItems,
        );
        for (final file in batch) {
          final int uploadIDForOriginalFIle = file.uploadedFileID!;
          if (oldToCopiedFileIDMap.containsKey(uploadIDForOriginalFIle)) {
            file.generatedID = null;
            file.collectionID = dstCollectionID;
            file.uploadedFileID = oldToCopiedFileIDMap[uploadIDForOriginalFIle];
            file.ownerID = _config.getUserID();
            oldToCopiedFileIDMap.remove(uploadIDForOriginalFIle);
          } else {
            throw Exception("Failed to copy file ${file.uploadedFileID}");
          }
        }
        if (oldToCopiedFileIDMap.isNotEmpty) {
          throw Exception(
            "Failed to map following uploadKey ${oldToCopiedFileIDMap.keys}",
          );
        }
        await _filesDB.insertMultiple(batch);
        Bus.instance.fire(
          CollectionUpdatedEvent(dstCollectionID, batch, "copiedTo"),
        );
      } catch (e) {
        rethrow;
      }
    }
  }

  Future<(List<EnteFile>, List<EnteFile>)> _splitFilesToAddAndCopy(
    List<EnteFile> othersFile,
  ) async {
    final hashToUserFile = await _filesDB
        .getUserOwnedFilesWithSameHashForGivenListOfFiles(
          othersFile,
          _config.getUserID()!,
        );
    final List<EnteFile> filesToCopy = [];
    final List<EnteFile> filesToAdd = [];
    final Set<int> seenForAdd = {};
    final Set<int> seenForCopy = {};

    for (final EnteFile file in othersFile) {
      final userFile = hashToUserFile[file.hash ?? ''];
      final bool shouldAdd =
          userFile != null && userFile.fileType == file.fileType;
      final targetList = shouldAdd ? filesToAdd : filesToCopy;
      final seenSet = shouldAdd ? seenForAdd : seenForCopy;
      final fileToProcess = shouldAdd ? userFile : file;
      final uploadID = fileToProcess.uploadedFileID;

      if (seenSet.contains(uploadID)) {
        final action = shouldAdd ? "adding" : "copying";
        _logger.warning(
          "skip $action file $uploadID as it is already ${action}ed",
        );
        continue;
      }
      targetList.add(fileToProcess);
      seenSet.add(uploadID!);
    }
    return (filesToAdd, filesToCopy);
  }

  void _validateCopyInput(
    int destCollectionID,
    int srcCollectionID,
    List<EnteFile> files,
  ) {
    final dstCollection = _collectionIDToCollections[destCollectionID];
    final srcCollection = _collectionIDToCollections[srcCollectionID];
    if (dstCollection == null || !dstCollection.isOwner(_config.getUserID()!)) {
      throw ArgumentError(
        'Destination collection not found ${dstCollection == null} or not owned by user ',
      );
    }
    if (srcCollection == null) {
      throw ArgumentError('Source collection not found');
    }
    // verify that all fileIds belong to srcCollection and isn't owned by current user
    for (final f in files) {
      if (f.collectionID != srcCollectionID ||
          f.ownerID == _config.getUserID()) {
        _logger.warning(
          'file $f does not belong to srcCollection $srcCollection or is owned by current user ${f.ownerID}',
        );
        throw ArgumentError('');
      }
    }
  }

  Future<EnteFile> linkLocalFileToExistingUploadedFileInAnotherCollection(
    int destCollectionID, {
    required EnteFile localFileToUpload,
    required EnteFile existingUploadedFile,
  }) async {
    final int uploadedFileID = existingUploadedFile.uploadedFileID!;

    // encrypt the fileKey with destination collection's key
    final fileKey = getFileKey(existingUploadedFile);
    final encryptedKeyData = CryptoUtil.encryptSync(
      fileKey,
      getCollectionKey(destCollectionID),
    );

    final encryptedKey = CryptoUtil.bin2base64(encryptedKeyData.encryptedData!);
    final keyDecryptionNonce = CryptoUtil.bin2base64(encryptedKeyData.nonce!);

    final fileItems = [
      CollectionFileItem(uploadedFileID, encryptedKey, keyDecryptionNonce),
    ];

    try {
      await collectionFilesGateway.addFiles(destCollectionID, fileItems);
      final linkedFile = existingUploadedFile.copyWith(
        uploadedFileID: uploadedFileID,
        collectionID: destCollectionID,
        encryptedKey: encryptedKey,
        keyDecryptionNonce: keyDecryptionNonce,
      );
      linkedFile.generatedID = localFileToUpload.generatedID;
      linkedFile.localID = localFileToUpload.localID;
      linkedFile.deviceFolder =
          localFileToUpload.deviceFolder ?? linkedFile.deviceFolder;
      linkedFile.addedTime = localFileToUpload.addedTime;
      await _filesDB.insertMultiple([linkedFile]);
      return linkedFile;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> restore(int toCollectionID, List<EnteFile> files) async {
    final toCollectionKey = getCollectionKey(toCollectionID);
    final int ownerID = Configuration.instance.getUserID()!;
    final Set<String> existingLocalIDS = await FilesDB.instance
        .getExistingLocalFileIDs(ownerID);
    final batchedFiles = files.chunks(batchSize);
    for (final batch in batchedFiles) {
      final fileItems = <CollectionFileItem>[];
      for (final file in batch) {
        final fileKey = getFileKey(file);
        file.generatedID =
            null; // So that a new entry is created in the FilesDB
        file.collectionID = toCollectionID;
        // During restore, if trash file local ID is not present in currently
        // imported files, treat the file as deleted from device
        if (file.localID != null && !existingLocalIDS.contains(file.localID)) {
          file.localID = null;
        }
        final encryptedKeyData = CryptoUtil.encryptSync(
          fileKey,
          toCollectionKey,
        );
        file.encryptedKey = CryptoUtil.bin2base64(
          encryptedKeyData.encryptedData!,
        );
        file.keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedKeyData.nonce!,
        );
        fileItems.add(
          CollectionFileItem(
            file.uploadedFileID!,
            file.encryptedKey!,
            file.keyDecryptionNonce!,
          ),
        );
      }
      try {
        await collectionFilesGateway.restoreFiles(toCollectionID, fileItems);
        await _filesDB.insertMultiple(batch);
        await TrashDB.instance.delete(
          batch.map((e) => e.uploadedFileID!).toList(),
        );
        Bus.instance.fire(
          CollectionUpdatedEvent(toCollectionID, batch, "restore"),
        );
        Bus.instance.fire(FilesUpdatedEvent(batch, source: "restore"));
        // Remove imported local files which are imported but not uploaded.
        // This handles the case where local file was trashed -> imported again
        // but not uploaded automatically as it was trashed.
        final localIDs = batch
            .where((e) => e.localID != null)
            .map((e) => e.localID!)
            .toSet()
            .toList();
        if (localIDs.isNotEmpty) {
          await _filesDB.deleteUnSyncedLocalFiles(localIDs);
        }
        // Force reload home gallery to pull in the restored files
        Bus.instance.fire(ForceReloadHomeGalleryEvent("restoredFromTrash"));
      } catch (e, s) {
        _logger.severe("failed to restore files", e, s);
        rethrow;
      }
    }
  }

  Future<void> move(
    List<EnteFile> files, {
    required int toCollectionID,
    required int fromCollectionID,
  }) async {
    _validateMoveRequest(toCollectionID, fromCollectionID, files);
    files.removeWhere((element) => element.uploadedFileID == null);
    if (files.isEmpty) {
      _logger.info("nothing to move to collection");
      return;
    }
    final batchedFiles = files.chunks(batchSize);
    for (final batch in batchedFiles) {
      final fileItems = <CollectionFileItem>[];
      for (final file in batch) {
        final fileKey = getFileKey(file);
        file.generatedID =
            null; // So that a new entry is created in the FilesDB
        file.collectionID = toCollectionID;
        final encryptedKeyData = CryptoUtil.encryptSync(
          fileKey,
          getCollectionKey(toCollectionID),
        );
        file.encryptedKey = CryptoUtil.bin2base64(
          encryptedKeyData.encryptedData!,
        );
        file.keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedKeyData.nonce!,
        );
        fileItems.add(
          CollectionFileItem(
            file.uploadedFileID!,
            file.encryptedKey!,
            file.keyDecryptionNonce!,
          ),
        );
      }
      await collectionFilesGateway.moveFiles(
        toCollectionID: toCollectionID,
        fromCollectionID: fromCollectionID,
        files: fileItems,
      );
    }

    // remove files from old collection
    await _filesDB.removeFromCollection(
      fromCollectionID,
      files.map((e) => e.uploadedFileID!).toList(),
    );
    Bus.instance.fire(
      CollectionUpdatedEvent(
        fromCollectionID,
        files,
        "moveFrom",
        type: EventType.deletedFromRemote,
      ),
    );
    // insert new files in the toCollection which are not part of the toCollection
    final existingUploadedIDs = await FilesDB.instance.getUploadedFileIDs(
      toCollectionID,
    );
    files.removeWhere(
      (element) => existingUploadedIDs.contains(element.uploadedFileID),
    );
    await _filesDB.insertMultiple(files);
    Bus.instance.fire(CollectionUpdatedEvent(toCollectionID, files, "moveTo"));
  }

  void _validateMoveRequest(
    int toCollectionID,
    int fromCollectionID,
    List<EnteFile> files,
  ) {
    final int userID = Configuration.instance.getUserID()!;
    if (toCollectionID == fromCollectionID) {
      throw AssertionError("Can't move to same album");
    }
    final Collection? toCollection = _collectionIDToCollections[toCollectionID];
    final Collection? fromCollection =
        _collectionIDToCollections[fromCollectionID];
    if (toCollection != null && !toCollection.isOwner(userID)) {
      throw AssertionError("Can't move to a collection you don't own");
    }
    if (fromCollection != null && !fromCollection.isOwner(userID)) {
      throw AssertionError("Can't move from a collection you don't own");
    }
    for (final file in files) {
      if (file.uploadedFileID == null) {
        throw AssertionError("Can only move uploaded memories");
      }
      if (file.collectionID != fromCollectionID) {
        throw AssertionError("All memories should belong to the same album");
      }
      if (file.ownerID != Configuration.instance.getUserID()) {
        throw AssertionError("Can only move memories uploaded by you");
      }
    }
  }

  Future<void> removeFromCollection(
    int collectionID,
    List<EnteFile> files,
  ) async {
    final batchedFiles = files.chunks(batchSize);
    for (final batch in batchedFiles) {
      final fileIDs = <int>[];
      for (final file in batch) {
        fileIDs.add(file.uploadedFileID!);
      }
      await collectionFilesGateway.removeFiles(collectionID, fileIDs);

      await _filesDB.removeFromCollection(collectionID, fileIDs);
      Bus.instance.fire(
        CollectionUpdatedEvent(
          collectionID,
          batch,
          "removeFrom",
          type: EventType.deletedFromRemote,
        ),
      );
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          batch,
          source: "removeFrom",
          type: EventType.deletedFromRemote,
        ),
      );
    }
    RemoteSyncService.instance.sync(silently: true).ignore();
  }

  Future<void> suggestDeleteFromCollection(
    int collectionID,
    List<EnteFile> files,
  ) async {
    final List<int> fileIDs = files
        .map((file) => file.uploadedFileID)
        .whereType<int>()
        .toList();
    if (fileIDs.isEmpty) {
      return;
    }
    await collectionFilesGateway.suggestDelete(collectionID, fileIDs);

    await _filesDB.removeFromCollection(collectionID, fileIDs);
    Bus.instance.fire(
      CollectionUpdatedEvent(
        collectionID,
        files,
        "suggestDelete",
        type: EventType.deletedFromRemote,
      ),
    );
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(
        files,
        source: "suggestDelete",
        type: EventType.deletedFromRemote,
      ),
    );
    RemoteSyncService.instance.sync(silently: true).ignore();
  }

  Future<Collection> createAndCacheCollection(
    CreateRequest createRequest,
  ) async {
    final collectionData = await collectionsGateway.createCollection(
      createRequest,
    );
    final collection = await _fromRemoteCollection(collectionData);
    final cachedCollection = _cacheLocalPathAndCollection(collection);
    Bus.instance.fire(
      CollectionUpdatedEvent(
        cachedCollection.id,
        List<EnteFile>.empty(),
        "createCollection",
      ),
    );
    return cachedCollection;
  }

  @Deprecated("Use _cacheLocalPathAndCollection instead")
  Collection _cacheCollectionAttributes(Collection collection) {
    final String decryptedName = _getDecryptedCollectionName(collection);
    collection.setName(decryptedName);
    if (collection.canLinkToDevicePath(_config.getUserID()!)) {
      _localPathToCollectionID[_decryptCollectionPath(collection)] =
          collection.id;
    }
    _collectionIDToCollections[collection.id] = collection;
    return collection;
  }

  Collection _cacheLocalPathAndCollection(Collection collection) {
    assert(
      collection.decryptedName != null,
      "decryptedName should be already set",
    );
    if (collection.canLinkToDevicePath(_config.getUserID()!) &&
        (collection.decryptedPath ?? '').isNotEmpty) {
      _localPathToCollectionID[collection.decryptedPath!] = collection.id;
    }
    _collectionIDToCollections[collection.id] = collection;
    return collection;
  }

  String _decryptCollectionPath(Collection collection) {
    if (collection.decryptedPath != null &&
        collection.decryptedPath!.isNotEmpty) {
      debugPrint("Using cached decrypted path for collection ${collection.id}");
      return collection.decryptedPath!;
    } else {
      debugPrint(
        "Decrypting path for collection ${collection.id} from "
        "encryptedPath",
      );
    }
    final key = collection.attributes.version! >= 1
        ? getCollectionKey(collection.id)
        : _config.getKey();
    return utf8.decode(
      CryptoUtil.decryptSync(
        CryptoUtil.base642bin(collection.attributes.encryptedPath!),
        key!,
        CryptoUtil.base642bin(collection.attributes.pathDecryptionNonce!),
      ),
    );
  }

  bool hasSyncedCollections() {
    return _prefs.containsKey(_collectionsSyncTimeKey);
  }

  String _decryptCollectionNameWithKey(
    Collection collection,
    Uint8List collectionKey,
  ) {
    if (collection.isDeleted) {
      return "Deleted Album";
    }
    if (collection.encryptedName != null &&
        collection.encryptedName!.isNotEmpty) {
      final result = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(collection.encryptedName!),
        collectionKey,
        CryptoUtil.base642bin(collection.nameDecryptionNonce!),
      );
      return utf8.decode(result);
    }
    return collection.displayName;
  }

  String _getDecryptedCollectionName(Collection collection) {
    if (collection.isDeleted) {
      return "Deleted Album";
    }
    if (collection.encryptedName != null &&
        collection.encryptedName!.isNotEmpty) {
      try {
        final collectionKey = _getAndCacheDecryptedKey(
          collection,
          source: "Name",
        );
        return _decryptCollectionNameWithKey(collection, collectionKey);
      } catch (e, s) {
        _logger.severe(
          "failed to decrypt collection name: ${collection.id}",
          e,
          s,
        );
      }
    }
    return collection.displayName;
  }

  Future _updateDB(List<Collection> collections, {int attempt = 1}) async {
    if (collections.isEmpty) {
      return;
    }
    try {
      await _db.insert(collections);
    } catch (e) {
      _logger.severe("Failed to update collections", e);
      if (attempt < kMaximumWriteAttempts) {
        return _updateDB(collections, attempt: ++attempt);
      } else {
        rethrow;
      }
    }
  }
}
