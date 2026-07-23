import "dart:async";
import "dart:convert";

import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/smart_album_syncing_event.dart";
import "package:photos/gateways/entity/models/type.dart";
import "package:photos/models/collection/smart_album_config.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/service_locator.dart"
    show entityService, hasGrantedMLConsent;
import "package:photos/services/collections_service.dart";
import "package:photos/services/search_service.dart";

class SmartAlbumsService {
  final _logger = Logger((SmartAlbumsService).toString());

  int _lastCacheRefreshTime = 0;

  Future<Map<int, SmartAlbumConfig>>? _cachedConfigsFuture;

  (int, bool)? syncingCollection;

  void clearCache() {
    _cachedConfigsFuture = null;
    _lastCacheRefreshTime = 0;
  }

  int lastRemoteSyncTime() {
    return entityService.lastSyncTime(EntityType.smartAlbum);
  }

  Future<Map<int, SmartAlbumConfig>> getSmartConfigs() async {
    final lastRemoteSyncTimeValue = lastRemoteSyncTime();
    if (_lastCacheRefreshTime != lastRemoteSyncTimeValue) {
      _lastCacheRefreshTime = lastRemoteSyncTimeValue;
      _cachedConfigsFuture = null; // Invalidate cache
    }
    _cachedConfigsFuture ??= _fetchAndCacheSaConfigs();
    return _cachedConfigsFuture!;
  }

  Future<Map<int, SmartAlbumConfig>> _fetchAndCacheSaConfigs() async {
    _logger.finest("reading all smart configs from local db");

    final entities = await entityService.getEntities(EntityType.smartAlbum);

    final result = _decodeSaConfigEntities({"entity": entities});

    return result;
  }

  Map<int, SmartAlbumConfig> _decodeSaConfigEntities(
    Map<String, dynamic> param,
  ) {
    final entities = (param["entity"] as List<LocalEntityData>);

    final Map<int, SmartAlbumConfig> saConfigs = {};

    for (final entity in entities) {
      try {
        final config = SmartAlbumConfig.fromJson(
          json.decode(entity.data),
          entity.id,
          entity.updatedAt,
        );

        saConfigs[config.collectionId] = config;
      } catch (error, stackTrace) {
        _logger.severe(
          "Failed to decode smart album config",
          error,
          stackTrace,
        );
      }
    }

    return saConfigs;
  }

  Future<void> syncSmartAlbums() async {
    final isMLEnabled = hasGrantedMLConsent;
    if (!isMLEnabled) {
      _logger.warning("ML is not enabled, skipping smart album sync");
      return;
    }

    _logger.info("Syncing Smart Albums");
    final cachedConfigs = await getSmartConfigs();
    final userId = Configuration.instance.getUserID();
    if (userId == null) {
      _logger.warning("No user ID, skipping smart album sync");
      return;
    }

    for (final entry in cachedConfigs.entries) {
      final collectionId = entry.key;
      final config = entry.value;

      if (config.personIDs.isEmpty) {
        _logger.warning(
          "Skipping sync for collection ($collectionId) as it has no person IDs",
        );
        continue;
      }

      final collection = CollectionsService.instance.getCollectionByID(
        collectionId,
      );

      if (collection == null || !collection.canAutoAdd(userId)) {
        _logger.warning(
          "For config ($collectionId) user does not have permission",
        );
        if (collection?.isDeleted ?? false) {
          await _deleteEntry(userId: userId, collectionId: collectionId);
        }

        continue;
      }

      syncingCollection = (collectionId, false);
      Bus.instance.fire(
        SmartAlbumSyncingEvent(collectionId: collectionId, isSyncing: false),
      );

      final infoMap = config.infoMap;

      // Person Id key mapped to updatedAt value
      final updatedAtMap = await entityService.getUpdatedAts(
        EntityType.cgroup,
        config.personIDs.toList(),
      );

      Map<String, Set<int>> pendingSyncFiles = {};
      Set<EnteFile> pendingSyncFileSet = {};

      var newConfig = config;
      for (final personId in config.personIDs) {
        // compares current updateAt with last added file's updatedAt
        if (updatedAtMap[personId] == null ||
            infoMap[personId] != null &&
                (updatedAtMap[personId]! <= infoMap[personId]!.updatedAt)) {
          continue;
        }

        final fileIds =
            (await SearchService.instance.getFilesForPersonID(
              personId,
              sortOnTime: false,
            ))..removeWhere(
              (e) =>
                  e.uploadedFileID == null ||
                  config.infoMap[personId]!.addedFiles.contains(
                    e.uploadedFileID,
                  ) ||
                  e.ownerID != userId,
            );

        pendingSyncFiles = {
          ...pendingSyncFiles,
          personId: fileIds.map((e) => e.uploadedFileID!).toSet(),
        };
        pendingSyncFileSet = {...pendingSyncFileSet, ...fileIds};
      }

      syncingCollection = (collectionId, true);
      Bus.instance.fire(
        SmartAlbumSyncingEvent(collectionId: collectionId, isSyncing: true),
      );

      if (pendingSyncFiles.isNotEmpty) {
        try {
          await CollectionsService.instance.addOrCopyToCollection(
            collectionId,
            pendingSyncFileSet.toList(),
            toCopy: false,
          );
          newConfig = newConfig.addFiles(updatedAtMap, pendingSyncFiles);

          await saveConfig(newConfig);
        } catch (e, sT) {
          _logger.warning(e, sT);
        }
      }
    }
    syncingCollection = null;
    Bus.instance.fire(SmartAlbumSyncingEvent());
    _logger.fine("Smart Albums sync completed");
  }

  Future<SmartAlbumConfig> addPeopleToSmartAlbum(
    int collectionId,
    List<String> personIDs,
  ) async {
    final cachedConfigs = await getSmartConfigs();

    late SmartAlbumConfig newConfig;

    final config = cachedConfigs[collectionId];
    final infoMap = Map<String, PersonInfo>.from(config?.infoMap ?? {});

    for (final personId in personIDs) {
      // skip if personId already exists in infoMap
      // only relevant when config exists before
      if (infoMap.containsKey(personId)) continue;
      infoMap[personId] = (updatedAt: 0, addedFiles: {});
    }

    newConfig = SmartAlbumConfig(
      id: config?.id,
      collectionId: collectionId,
      personIDs: {...?config?.personIDs, ...personIDs},
      infoMap: infoMap,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await saveConfig(newConfig);
    return newConfig;
  }

  Future<void> saveConfig(SmartAlbumConfig config) async {
    final userId = Configuration.instance.getUserID()!;

    await _addOrUpdateEntity(
      EntityType.smartAlbum,
      config.toJson(),
      collectionId: config.collectionId,
      addWithCustomID: config.id == null,
      userId: userId,
    );
  }

  Future<SmartAlbumConfig?> getConfig(int collectionId) async {
    final cachedConfigs = await getSmartConfigs();
    return cachedConfigs[collectionId];
  }

  String getId({required int collectionId, required int userId}) =>
      "sa_${userId}_$collectionId";

  /// Wrapper method for entityService.addOrUpdate that handles cache refresh
  Future<LocalEntityData> _addOrUpdateEntity(
    EntityType type,
    Map<String, dynamic> jsonMap, {
    required int collectionId,
    bool addWithCustomID = false,
    required int userId,
  }) async {
    _logger.fine("Adding or updating entity for collection ($collectionId)");
    final id = getId(collectionId: collectionId, userId: userId);
    final result = await entityService.addOrUpdate(
      type,
      jsonMap,
      id: id,
      addWithCustomID: addWithCustomID,
    );

    _lastCacheRefreshTime = 0; // Invalidate cache
    return result;
  }

  Future<void> _deleteEntry({
    required int userId,
    required int collectionId,
  }) async {
    _logger.fine("Deleting entry for collection ($collectionId)");
    final id = getId(collectionId: collectionId, userId: userId);
    await entityService.deleteEntry(id);
    _lastCacheRefreshTime = 0; // Invalidate cache
  }
}
