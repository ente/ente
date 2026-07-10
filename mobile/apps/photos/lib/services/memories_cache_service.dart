import "dart:async";
import "dart:io" show File;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/memories_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/events/memories_setting_changed.dart";
import "package:photos/events/memory_seen_event.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/smart_memory_constants.dart";
import "package:photos/models/memories/trip_memory.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/language_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/memories/photo_selector.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/services/smart_memories_service.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/home/memories/all_memories_page.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/people/people_page.dart";
import "package:photos/utils/cache_util.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class MemoriesCacheService {
  static const _lastMemoriesCacheUpdateTimeKey = "lastMemoriesCacheUpdateTime";
  static const _showAnyMemoryKey = "memories.enabled";
  static const _shouldUpdateCacheKey = "memories.shouldUpdateCache";
  static const _tripMemoryCarryForwardLimit = kTripSurfaceSlots;

  /// Delay is for cache update to be done not during app init, during which a
  /// lot of other things are happening.
  static const _kCacheUpdateDelay = Duration(seconds: 20);

  final SharedPreferences _prefs;
  static final Logger _logger = Logger("MemoriesCacheService");

  MemoriesDB get _memoriesDB => isLocalGalleryMode
      ? MemoriesDB.localGalleryInstance
      : MemoriesDB.instance;

  List<SmartMemory>? _cachedMemories;
  List<SmartMemory>? get currentMemoriesSync => _cachedMemories;
  bool _shouldUpdate = false;
  bool _pendingInitialOfflineCacheUpgrade = false;
  bool _isRunningDeferredInitialOfflineCacheUpgrade = false;

  bool _isUpdatingMemories = false;
  bool get isUpdatingMemories => _isUpdatingMemories;

  final _memoriesUpdateLock = Lock();
  final _memoriesGetLock = Lock();

  MemoriesCacheService(this._prefs) {
    _logger.info("MemoriesCacheService constructor");

    Future.delayed(_kCacheUpdateDelay, () {
      _checkIfTimeToUpdateCache();
      // Self-schedule cache updates independently of runAllML, so that users
      // with ML disabled still get their memories cache refreshed on the
      // configured cadence. Safe to call unconditionally: updateCache() is a
      // no-op when neither _shouldUpdate nor forced is true, and the lock
      // serialises against concurrent invocations from runAllML.
      unawaited(updateCache());
      _memoriesDB.clearMemoriesSeenBeforeTime(
        DateTime.now()
            .subtract(kMemoriesUpdateFrequency)
            .microsecondsSinceEpoch,
      );
    });

    Bus.instance
        .on<FilesUpdatedEvent>()
        .where((event) {
          return _shouldInvalidateForDeletedFiles(event.type);
        })
        .listen((event) async {
          await _invalidateDeletedFiles(event.updatedFiles);
        });

    Bus.instance.on<LocalPhotosUpdatedEvent>().listen((event) {
      if (_pendingInitialOfflineCacheUpgrade &&
          isLocalGalleryMode &&
          event.source == "offlineImportMetadata" &&
          LocalSyncService.instance.hasCompletedFirstImport()) {
        unawaited(
          _runDeferredInitialOfflineCacheUpgrade(
            trigger: "offlineImportMetadata",
          ),
        );
      }

      final shouldQueueUpdate =
          _cachedMemories == null || _cachedMemories!.isEmpty;
      if (!shouldQueueUpdate) {
        return;
      }
      queueUpdateCache();
    });

    Bus.instance.on<SyncStatusUpdate>().listen((event) {
      if (event.status != SyncStatus.completedFirstGalleryImport) {
        return;
      }
      unawaited(
        _runDeferredInitialOfflineCacheUpgrade(
          trigger: "completedFirstGalleryImport",
        ),
      );
    });
  }

  String get _lastCacheUpdateKey => isLocalGalleryMode
      ? "${_lastMemoriesCacheUpdateTimeKey}_offline"
      : _lastMemoriesCacheUpdateTimeKey;

  String get _shouldUpdateKey => isLocalGalleryMode
      ? "${_shouldUpdateCacheKey}_offline"
      : _shouldUpdateCacheKey;

  int get lastMemoriesCacheUpdateTime {
    return _prefs.getInt(_lastCacheUpdateKey) ?? 0;
  }

  bool get showAnyMemories {
    return _prefs.getBool(_showAnyMemoryKey) ?? true;
  }

  Future<void> setShowAnyMemories(bool value) async {
    await _prefs.setBool(_showAnyMemoryKey, value);
    Bus.instance.fire(MemoriesSettingChanged());
    if (!value) {
      await Future.wait([_clearAllScheduledOnThisDayNotifications()]);
    } else {
      queueUpdateCache();
    }
  }

  bool get enableSmartMemories => localSettings.isSmartMemoriesEnabled;

  bool get curatedMemoriesOption => showAnyMemories;

  bool get _mlEnabled =>
      hasGrantedMLConsent && localSettings.isMLLocalIndexingEnabled;

  Future<bool> _isMlReady() async {
    if (!_mlEnabled) return false;
    try {
      final mlDataDB = isLocalGalleryMode
          ? MLDataDB.localGalleryInstance
          : MLDataDB.instance;
      final clipIndexed = await mlDataDB.getClipIndexedFileCount();
      if (clipIndexed < SmartMemoriesService.minimumMemoryLength) {
        return false;
      }
      if (!await MLModelDownloadService.instance.canLoadClipTextModel()) {
        _logger.info(
          "ML not ready for smart memories because CLIP text model is not "
          "cached and high bandwidth connectivity is unavailable",
        );
        return false;
      }
      return true;
    } catch (e, s) {
      _logger.warning("Failed to determine ML readiness", e, s);
      return false;
    }
  }

  void _checkIfTimeToUpdateCache() {
    if (!enableSmartMemories) {
      return;
    }
    _shouldUpdate = _prefs.getBool(_shouldUpdateKey) ?? _shouldUpdate;
    if (_timeToUpdateCache()) {
      queueUpdateCache();
    }
  }

  bool _timeToUpdateCache() {
    return lastMemoriesCacheUpdateTime <
        DateTime.now()
            .subtract(kMemoriesUpdateFrequency)
            .microsecondsSinceEpoch;
  }

  bool _shouldInvalidateForDeletedFiles(EventType type) {
    if (type == EventType.deletedFromEverywhere) {
      return true;
    }

    if (isLocalGalleryMode) {
      return type == EventType.deletedFromDevice;
    }

    return type == EventType.deletedFromRemote;
  }

  Future markMemoryAsSeen(Memory memory, bool lastInList) async {
    memory.markSeen();
    int? seenTimeKey;
    if (isLocalGalleryMode) {
      final localId = memory.file.localID;
      if (localId != null && localId.isNotEmpty) {
        seenTimeKey = _localIdToIntIdCache[localId];
        if (seenTimeKey == null) {
          seenTimeKey = await OfflineFilesDB.instance.getOrCreateLocalIntId(
            localId,
          );
          _localIdToIntIdCache[localId] = seenTimeKey;
        }
      }
    }
    await _memoriesDB.markMemoryAsSeen(
      memory,
      DateTime.now().microsecondsSinceEpoch,
      seenTimeKey: seenTimeKey,
    );
    if (_cachedMemories != null) {
      if (isLocalGalleryMode) {
        final localId = memory.file.localID;
        if (localId != null && localId.isNotEmpty) {
          final localIntId =
              _localIdToIntIdCache[localId] ??
              await OfflineFilesDB.instance.getOrCreateLocalIntId(localId);
          _localIdToIntIdCache[localId] = localIntId;
          final cachedLocalIds = _cachedMemories!
              .expand((mem) => mem.memories)
              .map((mem) => mem.file.localID)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet();
          if (cachedLocalIds.isNotEmpty) {
            final cacheLocalIdToIntId = await OfflineFilesDB.instance
                .ensureLocalIntIds(cachedLocalIds);
            _localIdToIntIdCache.addAll(cacheLocalIdToIntId);
            for (final smartMemory in _cachedMemories!) {
              for (final mem in smartMemory.memories) {
                final memLocalId = mem.file.localID;
                final memLocalIntId = memLocalId != null
                    ? _localIdToIntIdCache[memLocalId]
                    : null;
                if (memLocalIntId == localIntId) {
                  mem.markSeen();
                }
              }
            }
          }
        }
      } else if (memory.file.generatedID != null) {
        final generatedID = memory.file.generatedID!;
        for (final smartMemory in _cachedMemories!) {
          for (final mem in smartMemory.memories) {
            if (mem.file.generatedID == generatedID) {
              mem.markSeen();
            }
          }
        }
      }
    }
    if (lastInList) Bus.instance.fire(MemorySeenEvent());
  }

  void queueUpdateCache() {
    _shouldUpdate = true;
    unawaited(_prefs.setBool(_shouldUpdateKey, true));
  }

  Future<void> _invalidateDeletedFiles(List<EnteFile> deletedFiles) async {
    final deletedMemoryFileIds = await _deletedMemoryFileIds(deletedFiles);
    if (deletedMemoryFileIds.isEmpty) {
      return;
    }

    await _memoriesUpdateLock.synchronized(() async {
      bool cacheChanged = false;

      if (_cachedMemories != null) {
        final filteredMemories = <SmartMemory>[];
        for (final memory in _cachedMemories!) {
          final memoryChanged = _removeDeletedFilesFromSmartMemory(
            memory,
            deletedMemoryFileIds,
          );
          if (memory.memories.isNotEmpty) {
            filteredMemories.add(memory);
          }
          cacheChanged = cacheChanged || memoryChanged;
        }
        if (filteredMemories.length != _cachedMemories!.length) {
          cacheChanged = true;
        }
        _cachedMemories = filteredMemories;
      }

      if (await _removeDeletedFilesFromDiskCache(deletedMemoryFileIds)) {
        cacheChanged = true;
      }

      if (!cacheChanged) {
        return;
      }

      queueUpdateCache();
      Bus.instance.fire(MemoriesChangedEvent());
    });
  }

  Future<Set<int>> _deletedMemoryFileIds(List<EnteFile> deletedFiles) async {
    if (isLocalGalleryMode) {
      final localIds = deletedFiles
          .map((file) => file.localID)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      if (localIds.isEmpty) {
        return {};
      }
      final localIdToIntId = await OfflineFilesDB.instance.ensureLocalIntIds(
        localIds,
      );
      _localIdToIntIdCache.addAll(localIdToIntId);
      return localIdToIntId.values.toSet();
    }

    return deletedFiles
        .map(
          (file) => PhotoSelector.memoryFileId(file, isLocalGalleryMode: false),
        )
        .whereType<int>()
        .toSet();
  }

  bool _removeDeletedFilesFromSmartMemory(
    SmartMemory memory,
    Set<int> deletedMemoryFileIds,
  ) {
    final originalLength = memory.memories.length;
    memory.memories.removeWhere((mem) {
      if (isLocalGalleryMode) {
        final localId = mem.file.localID;
        if (localId == null || localId.isEmpty) {
          return false;
        }
        final localIntId = _localIdToIntIdCache[localId];
        return localIntId != null && deletedMemoryFileIds.contains(localIntId);
      }

      final uploadedFileId = PhotoSelector.memoryFileIdFromMemory(
        mem,
        isLocalGalleryMode: false,
      );
      return uploadedFileId != null &&
          deletedMemoryFileIds.contains(uploadedFileId);
    });
    return memory.memories.length != originalLength;
  }

  Future<bool> _removeDeletedFilesFromDiskCache(
    Set<int> deletedMemoryFileIds,
  ) async {
    final cache = await _readCacheFromDisk();
    if (cache == null) {
      return false;
    }

    bool cacheChanged = false;
    final filteredToShowMemories = <ToShowMemory>[];
    for (final memory in cache.toShowMemories) {
      final memoryChanged = _removeDeletedFilesFromCacheMemory(
        memory,
        deletedMemoryFileIds,
      );
      if (_cacheMemoryHasFiles(memory)) {
        filteredToShowMemories.add(memory);
      }
      cacheChanged = cacheChanged || memoryChanged;
    }

    if (filteredToShowMemories.length != cache.toShowMemories.length) {
      cacheChanged = true;
    }
    if (!cacheChanged) {
      return false;
    }

    cache.toShowMemories
      ..clear()
      ..addAll(filteredToShowMemories);
    await writeToJsonFile<MemoriesCache>(
      await _getCachePath(),
      cache,
      MemoriesCache.encodeToJsonString,
    );
    return true;
  }

  bool _removeDeletedFilesFromCacheMemory(
    ToShowMemory memory,
    Set<int> deletedMemoryFileIds,
  ) {
    if (isLocalGalleryMode && memory.fileLocalIntIDs != null) {
      final originalLength = memory.fileLocalIntIDs!.length;
      memory.fileLocalIntIDs!.removeWhere(deletedMemoryFileIds.contains);
      return memory.fileLocalIntIDs!.length != originalLength;
    }

    final originalLength = memory.fileUploadedIDs.length;
    memory.fileUploadedIDs.removeWhere(deletedMemoryFileIds.contains);
    return memory.fileUploadedIDs.length != originalLength;
  }

  bool _cacheMemoryHasFiles(ToShowMemory memory) {
    if (isLocalGalleryMode && memory.fileLocalIntIDs != null) {
      return memory.fileLocalIntIDs!.isNotEmpty;
    }
    return memory.fileUploadedIDs.isNotEmpty;
  }

  bool _shouldDeferInitialOfflineCacheUpgrade() {
    return isLocalGalleryMode &&
        !LocalSyncService.instance.hasCompletedFirstImport();
  }

  Future<void> _runDeferredInitialOfflineCacheUpgrade({
    required String trigger,
  }) async {
    if (!_pendingInitialOfflineCacheUpgrade ||
        _isRunningDeferredInitialOfflineCacheUpgrade ||
        !isLocalGalleryMode) {
      return;
    }

    _isRunningDeferredInitialOfflineCacheUpgrade = true;
    try {
      _logger.info(
        "Running deferred initial offline memories cache upgrade after $trigger",
      );
      await updateCache(forced: true);
      final persistedMemories = await _getMemoriesFromCache();
      if (persistedMemories != null && persistedMemories.isNotEmpty) {
        _pendingInitialOfflineCacheUpgrade = false;
        _logger.info(
          "Deferred initial offline memories cache upgrade after $trigger completed",
        );
      } else {
        _logger.warning(
          "Deferred initial offline memories cache upgrade after $trigger still produced an empty disk cache; waiting for the next import signal",
        );
      }
    } finally {
      _isRunningDeferredInitialOfflineCacheUpgrade = false;
      Bus.instance.fire(MemoriesChangedEvent());
    }
  }

  Future<void> purgeMlOnlyMemoriesFromCache() async {
    await _memoriesUpdateLock.synchronized(() async {
      bool cacheChanged = false;
      final removedPersonIDs = <String>{};

      if (_cachedMemories != null && _cachedMemories!.isNotEmpty) {
        final filtered = <SmartMemory>[];
        for (final memory in _cachedMemories!) {
          if (memory.type == MemoryType.people ||
              memory.type == MemoryType.clip) {
            if (memory is PeopleMemory) {
              removedPersonIDs.add(memory.personID);
            }
            continue;
          }
          filtered.add(memory);
        }
        if (filtered.length != _cachedMemories!.length) {
          _cachedMemories = filtered;
          cacheChanged = true;
        }
      }

      final cache = await _readCacheFromDisk();
      if (cache != null) {
        final originalToShowLength = cache.toShowMemories.length;
        final activeRemovedPeopleLogs = <PeopleShownLog>[];
        final activeRemovedClipLogs = <ClipShownLog>[];

        for (final memory in cache.toShowMemories) {
          if (memory.type == MemoryType.people) {
            if (memory.personID != null) {
              removedPersonIDs.add(memory.personID!);
            }
            if (memory.shouldShowNow()) {
              activeRemovedPeopleLogs.add(
                PeopleShownLog.fromOldCacheMemory(memory),
              );
            }
          } else if (memory.type == MemoryType.clip && memory.shouldShowNow()) {
            activeRemovedClipLogs.add(ClipShownLog.fromOldCacheMemory(memory));
          }
        }

        cache.toShowMemories.removeWhere(
          (memory) =>
              memory.type == MemoryType.people ||
              memory.type == MemoryType.clip,
        );
        if (cache.toShowMemories.length != originalToShowLength) {
          cache.peopleShownLogs.addAll(activeRemovedPeopleLogs);
          cache.clipShownLogs.addAll(activeRemovedClipLogs);
          await writeToJsonFile<MemoriesCache>(
            await _getCachePath(),
            cache,
            MemoriesCache.encodeToJsonString,
          );
          cacheChanged = true;
        }
      }

      for (final personID in removedPersonIDs) {
        await NotificationService.instance.clearAllScheduledNotifications(
          containingPayload: personID,
          logLines: false,
        );
      }

      if (cacheChanged) {
        Bus.instance.fire(MemoriesChangedEvent());
      }
    });
  }

  Future<void> purgePersonFromMemoriesCache(String personID) async {
    await _memoriesUpdateLock.synchronized(() async {
      final removedMemoryIDs = <String>{};
      bool cacheChanged = false;

      if (_cachedMemories != null && _cachedMemories!.isNotEmpty) {
        final filtered = <SmartMemory>[];
        for (final memory in _cachedMemories!) {
          if (memory is PeopleMemory && memory.personID == personID) {
            removedMemoryIDs.add(memory.id);
            continue;
          }
          filtered.add(memory);
        }
        if (filtered.length != _cachedMemories!.length) {
          _cachedMemories = filtered;
          cacheChanged = true;
        }
      }

      final cache = await _readCacheFromDisk();
      if (cache != null) {
        final originalToShowLength = cache.toShowMemories.length;
        final originalLogLength = cache.peopleShownLogs.length;
        for (final memory in cache.toShowMemories) {
          if (memory.type == MemoryType.people && memory.personID == personID) {
            removedMemoryIDs.add(memory.id);
          }
        }
        cache.toShowMemories.removeWhere(
          (memory) =>
              memory.type == MemoryType.people && memory.personID == personID,
        );
        cache.peopleShownLogs.removeWhere((log) => log.personID == personID);
        final shouldWriteCache =
            cache.toShowMemories.length != originalToShowLength ||
            cache.peopleShownLogs.length != originalLogLength;
        if (shouldWriteCache) {
          await writeToJsonFile<MemoriesCache>(
            await _getCachePath(),
            cache,
            MemoriesCache.encodeToJsonString,
          );
          cacheChanged = true;
        }
      }

      if (removedMemoryIDs.isNotEmpty) {
        await NotificationService.instance.clearAllScheduledNotifications(
          containingPayload: personID,
          logLines: false,
        );
      }

      if (cacheChanged) {
        Bus.instance.fire(MemoriesChangedEvent());
      }
    });
  }

  Future<List<SmartMemory>> getMemories({bool onlyUseCache = false}) async {
    _logger.info("getMemories called");
    if (!showAnyMemories) {
      _logger.info('Showing memories is disabled in settings, showing none');
      return [];
    }
    return _memoriesGetLock.synchronized(() async {
      if (_cachedMemories != null && _cachedMemories!.isNotEmpty) {
        final currentMemories = _cachedMemories!
            .where((memory) => memory.shouldShowNow())
            .toList();
        if (currentMemories.isNotEmpty) {
          _logger.info("Found memories in memory cache");
          return currentMemories;
        }
        _logger.info(
          "In-memory memories not valid for current window, refreshing cache",
        );
      } else if (onlyUseCache) {
        _logger.info("Only using cache, no memories found");
        return [];
      }
      try {
        if (!enableSmartMemories) {
          await _calculateRegularFillers();
          return _cachedMemories!;
        }
        final cacheFileExists = await _cacheFileExists();
        _cachedMemories = await _getMemoriesFromCache();
        if (_cachedMemories == null || _cachedMemories!.isEmpty) {
          final shouldRefreshEmptyCache =
              _cachedMemories == null ||
              _shouldUpdate ||
              _timeToUpdateCache() ||
              lastMemoriesCacheUpdateTime == 0;
          if (onlyUseCache) {
            _logger.info("Only using cache, no memories found");
            return [];
          }
          if (!shouldRefreshEmptyCache) {
            _logger.info("Found fresh empty memories cache");
            return [];
          }
          if (!cacheFileExists) {
            _logger.info(
              "No disk cache (fresh install): serving simple memories, "
              "smart memories will upgrade in background",
            );
            _cachedMemories = await smartMemoriesService.calcSimpleMemories();
            if (_shouldDeferInitialOfflineCacheUpgrade()) {
              _pendingInitialOfflineCacheUpgrade = true;
              _logger.info(
                "Deferring initial offline memories cache upgrade until first import metadata is ready",
              );
            } else {
              unawaited(
                updateCache(
                  forced: true,
                ).whenComplete(() => Bus.instance.fire(MemoriesChangedEvent())),
              );
            }
            return _cachedMemories!;
          }
          _logger.warning(
            "No memories found in cache, force updating cache. Possible severe caching issue",
          );
          await updateCache(forced: true);
        } else {
          _logger.info("Found memories in cache");
        }
        if (_cachedMemories == null || _cachedMemories!.isEmpty) {
          _logger.severe(
            "No memories found in (computed) cache, getting fillers",
          );
          await _calculateRegularFillers();
        }
        return _cachedMemories!;
      } catch (e, s) {
        _logger.severe("Error in getMemories", e, s);
        return [];
      }
    });
  }

  Future<void> _calculateRegularFillers() async {
    if (_cachedMemories == null) {
      _cachedMemories = await smartMemoriesService.calcSimpleMemories();
      Bus.instance.fire(MemoriesChangedEvent());
    }
    return;
  }

  Future<List<SmartMemory>?> _getMemoriesFromCache() async {
    final cache = await _readCacheFromDisk();
    if (cache == null) {
      return null;
    }
    final result = await fromCacheToMemories(cache);
    return result;
  }

  Future<MemoriesCache?> _readCacheFromDisk() async {
    _logger.info("Reading memories cache result from disk");
    final cache = decodeJsonFile<MemoriesCache>(
      await _getCachePath(),
      MemoriesCache.decodeFromJsonString,
    );
    return cache;
  }

  static Future<List<SmartMemory>> fromCacheToMemories(
    MemoriesCache cache,
  ) async {
    try {
      _logger.info('Processing disk cache memories to smart memories');
      final List<SmartMemory> memories = [];
      final List<(ToShowMemory, SmartMemory)> typedMemories = [];
      final seenTimes =
          await (isLocalGalleryMode
                  ? MemoriesDB.localGalleryInstance
                  : MemoriesDB.instance)
              .getSeenTimes();
      final minimalUploadedIDs = <int>{};
      final minimalLocalIntIds = <int>{};
      for (final ToShowMemory memory in cache.toShowMemories) {
        if (memory.shouldShowNow()) {
          if (memory.fileLocalIntIDs != null &&
              memory.fileLocalIntIDs!.isNotEmpty) {
            minimalLocalIntIds.addAll(memory.fileLocalIntIDs!);
          } else {
            minimalUploadedIDs.addAll(memory.fileUploadedIDs);
          }
        }
      }
      final minimalFilesFromUploaded = await FilesDB.instance.getFilesFromIDs(
        minimalUploadedIDs.toList(),
        collectionsToIgnore: SearchService.instance.ignoreCollections(),
      );
      final uploadedIdToFile = <int, EnteFile>{};
      for (final file in minimalFilesFromUploaded) {
        if (file.uploadedFileID != null) {
          uploadedIdToFile[file.uploadedFileID!] = file;
        }
      }
      final localIdToFile = <String, EnteFile>{};
      if (minimalLocalIntIds.isNotEmpty) {
        final localIdMap = await OfflineFilesDB.instance.getLocalIdsForIntIds(
          minimalLocalIntIds,
        );
        final allFiles = await SearchService.instance.getAllFilesForSearch();
        final neededLocalIds = localIdMap.values.toSet();
        for (final file in allFiles) {
          final localId = file.localID;
          if (localId != null && neededLocalIds.contains(localId)) {
            localIdToFile[localId] = file;
          }
        }
        _localIntIdToLocalId = localIdMap;
      }

      for (final ToShowMemory memory in cache.toShowMemories) {
        if (memory.shouldShowNow()) {
          final useLocalIntIds =
              memory.fileLocalIntIDs != null &&
              memory.fileLocalIntIDs!.isNotEmpty;
          final fileIds = useLocalIntIds
              ? memory.fileLocalIntIDs!
              : memory.fileUploadedIDs;
          final hydratedMemories = fileIds
              .where(
                (fileID) => useLocalIntIds
                    ? true
                    : uploadedIdToFile.containsKey(fileID),
              )
              .map((fileID) {
                final file = useLocalIntIds
                    ? _fileFromLocalIntId(fileID, localIdToFile)
                    : uploadedIdToFile[fileID];
                return file == null
                    ? null
                    : Memory.fromFile(
                        file,
                        seenTimes,
                        seenTimeKey: useLocalIntIds ? fileID : null,
                      );
              })
              .whereType<Memory>()
              .toList();
          final smartMemory = memory.toSmartMemory(hydratedMemories);
          if (smartMemory.memories.isNotEmpty) {
            memories.add(smartMemory);
            if (memory.hasTypedSpec) {
              typedMemories.add((memory, smartMemory));
            }
          }
        }
      }
      if (typedMemories.isNotEmpty) {
        final locale = await getLocale();
        final languageCode = locale?.languageCode ?? "en";
        final s = await LanguageService.locals;
        for (final typedMemory in typedMemories) {
          try {
            typedMemory.$2.title = typedMemory.$2.createTitle(s, languageCode);
          } catch (_) {
            typedMemory.$2.title = typedMemory.$1.title;
          }
        }
      }
      locationService.baseLocations = cache.baseLocations;
      _logger.info('Processing of disk cache memories done');
      return memories;
    } catch (e, s) {
      _logger.severe("Error converting cache to memories", e, s);
      return [];
    }
  }

  Future<void> updateCache({bool forced = false}) async {
    if (!showAnyMemories) {
      return;
    }
    if (!enableSmartMemories) {
      await _calculateRegularFillers();
      return;
    }
    _checkIfTimeToUpdateCache();

    return _memoriesUpdateLock.synchronized(() async {
      if ((!_shouldUpdate && !forced)) {
        _logger.info(
          "No update needed (shouldUpdate: $_shouldUpdate, forced: $forced)",
        );
        return;
      }
      _logger.info(
        "Updating memories cache (shouldUpdate: $_shouldUpdate, forced: $forced)",
      );
      _isUpdatingMemories = true;
      try {
        final EnteWatch? w = kDebugMode
            ? EnteWatch("MemoriesCacheService")
            : null;
        w?.start();
        final oldCache = await _readCacheFromDisk();
        w?.log("gotten old cache");
        final MemoriesCache newCache = _processOldCache(oldCache);
        w?.log("processed old cache");
        // calculate memories for this period and for the next period
        final now = DateTime.now();
        final next = now.add(kMemoriesUpdateFrequency);
        final mlReady = await _isMlReady();
        final nowResult = await smartMemoriesService.calcSmartMemories(
          now,
          newCache,
          mlEnabled: mlReady,
        );
        if (nowResult.failed) {
          _logger.warning(
            "Skipping memories cache update because current calculation failed",
          );
          return;
        }
        final carriedForwardTripEntries = List<ToShowMemory>.from(
          newCache.toShowMemories,
        );
        newCache.toShowMemories.addAll(
          nowResult.memories.whereType<TripMemory>().map(
            (memory) => ToShowMemory.fromSmartMemory(memory, now),
          ),
        );
        final nextResult = await smartMemoriesService.calcSmartMemories(
          next,
          newCache,
          mlEnabled: mlReady,
        );
        if (nextResult.failed) {
          _logger.warning(
            "Skipping memories cache update because next calculation failed",
          );
          return;
        }
        w?.log("calculated new memories");
        final localIdToIntId = isLocalGalleryMode
            ? await _buildLocalIntIdMapForMemories([
                ...nowResult.memories,
                ...nextResult.memories,
              ])
            : <String, int>{};
        final nowEntries = nowResult.memories
            .map((memory) => _toCacheMemory(memory, now, localIdToIntId))
            .toList();
        // Splice carried-forward trip entries into the natural trip slot so
        // the UI keeps showing trips in their usual position (after
        // onThisDay/people) instead of jumping to the front of the row.
        int tripInsertIdx = nowEntries.indexWhere(
          (e) => e.type == MemoryType.trips,
        );
        if (tripInsertIdx < 0) {
          tripInsertIdx = nowEntries.indexWhere(
            (e) =>
                e.type != MemoryType.onThisDay && e.type != MemoryType.people,
          );
          if (tripInsertIdx < 0) {
            tripInsertIdx = nowEntries.length;
          }
        }
        newCache.toShowMemories
          ..clear()
          ..addAll(nowEntries.sublist(0, tripInsertIdx))
          ..addAll(carriedForwardTripEntries)
          ..addAll(nowEntries.sublist(tripInsertIdx));
        for (final nextMemory in nextResult.memories) {
          newCache.toShowMemories.add(
            _toCacheMemory(nextMemory, next, localIdToIntId),
          );
        }
        final nowMicros = now.microsecondsSinceEpoch;
        final dedupedMemories = _dedupeTripCacheEntriesInOrder(
          List<ToShowMemory>.from(newCache.toShowMemories),
          nowMicros: nowMicros,
        );
        newCache.toShowMemories
          ..clear()
          ..addAll(dedupedMemories);
        newCache.baseLocations.addAll(nowResult.baseLocations);
        w?.log("added memories to cache");
        _cachedMemories = await fromCacheToMemories(newCache);
        await _scheduleMemoryNotifications([
          ...nowResult.memories,
          ...nextResult.memories,
        ]);
        locationService.baseLocations = newCache.baseLocations;
        await writeToJsonFile<MemoriesCache>(
          await _getCachePath(),
          newCache,
          MemoriesCache.encodeToJsonString,
        );
        w?.log("cacheWritten");
        await _cacheUpdated();
        w?.logAndReset('_cacheUpdated method done');
      } catch (e, s) {
        _logger.severe("Error updating memories cache", e, s);
      } finally {
        _isUpdatingMemories = false;
      }
    });
  }

  Future<void> refreshCache() async {
    if (!showAnyMemories) {
      return;
    }
    if (!enableSmartMemories) {
      return;
    }

    return _memoriesUpdateLock.synchronized(() async {
      try {
        _cachedMemories = await _getMemoriesFromCache();
        Bus.instance.fire(MemoriesChangedEvent());
      } catch (e, s) {
        _logger.info("Error refreshing memories cache", e, s);
      }
    });
  }

  static Map<int, String> _localIntIdToLocalId = {};
  static final Map<String, int> _localIdToIntIdCache = {};

  static EnteFile? _fileFromLocalIntId(
    int localIntId,
    Map<String, EnteFile> localIdToFile,
  ) {
    final localId = _localIntIdToLocalId[localIntId];
    if (localId == null) return null;
    return localIdToFile[localId];
  }

  static Future<Map<String, int>> _buildLocalIntIdMapForMemories(
    List<SmartMemory> memories,
  ) async {
    final localIds = <String>{};
    for (final memory in memories) {
      for (final mem in memory.memories) {
        final localId = mem.file.localID;
        if (localId != null && localId.isNotEmpty) {
          localIds.add(localId);
        }
      }
    }
    if (localIds.isEmpty) return {};
    final mapping = await OfflineFilesDB.instance.ensureLocalIntIds(localIds);
    _localIdToIntIdCache.addAll(mapping);
    return mapping;
  }

  static ToShowMemory _toCacheMemory(
    SmartMemory memory,
    DateTime calcTime,
    Map<String, int> localIdToIntId,
  ) {
    final localIntIds = memory.memories
        .map((m) => m.file.localID)
        .whereType<String>()
        .map((localId) => localIdToIntId[localId])
        .whereType<int>()
        .toList();
    return ToShowMemory.fromSmartMemory(
      memory,
      calcTime,
      fileLocalIntIDs: localIntIds.isNotEmpty ? localIntIds : null,
    );
  }

  static bool _shouldPreferTripCacheEntry(
    ToShowMemory candidate,
    ToShowMemory existing, {
    required int nowMicros,
  }) {
    final candidateActive = candidate.isRelevantAt(nowMicros);
    final existingActive = existing.isRelevantAt(nowMicros);
    if (candidateActive != existingActive) {
      return candidateActive;
    }
    if (candidate.firstTimeToShow != existing.firstTimeToShow) {
      return candidate.firstTimeToShow < existing.firstTimeToShow;
    }
    if (candidate.lastTimeToShow != existing.lastTimeToShow) {
      return candidate.lastTimeToShow > existing.lastTimeToShow;
    }
    return candidate.calculationTime > existing.calculationTime;
  }

  static List<ToShowMemory> _dedupeTripCacheEntriesInOrder(
    List<ToShowMemory> memories, {
    required int nowMicros,
  }) {
    final preferredEntries = <String, ToShowMemory>{};
    for (final memory in memories) {
      if (memory.type != MemoryType.trips) continue;
      final identityKey = memory.tripIdentityKey;
      final existing = preferredEntries[identityKey];
      if (existing == null ||
          _shouldPreferTripCacheEntry(memory, existing, nowMicros: nowMicros)) {
        preferredEntries[identityKey] = memory;
      }
    }

    final emittedKeys = <String>{};
    final result = <ToShowMemory>[];
    for (final memory in memories) {
      if (memory.type != MemoryType.trips) {
        result.add(memory);
        continue;
      }
      final identityKey = memory.tripIdentityKey;
      if (emittedKeys.contains(identityKey)) {
        continue;
      }
      if (preferredEntries[identityKey] == memory) {
        result.add(memory);
        emittedKeys.add(identityKey);
      }
    }
    return result;
  }

  static List<ToShowMemory> _activeTripEntriesForTime(
    Iterable<ToShowMemory> memories, {
    required int timestamp,
  }) {
    final activeTrips = memories
        .where(
          (memory) =>
              _shouldCarryForwardTripEntry(memory) &&
              memory.isRelevantAt(timestamp),
        )
        .toList();
    final dedupedActiveTrips = _dedupeTripCacheEntriesInOrder(
      activeTrips,
      nowMicros: timestamp,
    );
    dedupedActiveTrips.sort((a, b) {
      final firstCompare = a.firstTimeToShow.compareTo(b.firstTimeToShow);
      if (firstCompare != 0) {
        return firstCompare;
      }
      return a.lastTimeToShow.compareTo(b.lastTimeToShow);
    });
    return dedupedActiveTrips
        .take(_tripMemoryCarryForwardLimit)
        .toList(growable: false);
  }

  static bool _shouldCarryForwardTripEntry(ToShowMemory memory) {
    if (memory.type != MemoryType.trips) {
      return false;
    }
    // Drop legacy keyless trips during migration so they cannot coexist with
    // newly recomputed keyed trips for the same trip.
    final tripKey = memory.tripKey;
    return tripKey != null && tripKey.isNotEmpty;
  }

  Future<String> _getCachePath() async {
    final suffix = isLocalGalleryMode ? "_offline" : "";
    return (await getApplicationSupportDirectory()).path +
        "/cache/memories_cache$suffix";
  }

  Future<bool> _cacheFileExists() async {
    return File(await _getCachePath()).existsSync();
  }

  Future<void> _cacheUpdated() async {
    _shouldUpdate = false;
    unawaited(_prefs.setBool(_shouldUpdateKey, false));
    await _prefs.setInt(
      _lastCacheUpdateKey,
      DateTime.now().microsecondsSinceEpoch,
    );
    Bus.instance.fire(MemoriesChangedEvent());
  }

  /// WARNING: Use for testing only, TODO: lau: remove later
  Future<MemoriesCache> debugCacheForTesting() async {
    final oldCache = await _readCacheFromDisk();
    final MemoriesCache newCache = _processOldCache(oldCache);
    return newCache;
  }

  /// WARNING: Use for testing only.
  ///
  /// Computes the full smart memories set with debug surfacing enabled without
  /// mutating the persisted memories cache.
  Future<List<SmartMemory>> debugGetAllMemories({DateTime? calcTime}) async {
    return _memoriesUpdateLock.synchronized(() async {
      final mlReady = await _isMlReady();
      final result = await smartMemoriesService.calcSmartMemories(
        calcTime ?? DateTime.now(),
        MemoriesCache(
          toShowMemories: [],
          peopleShownLogs: [],
          clipShownLogs: [],
          tripsShownLogs: [],
          baseLocations: [],
        ),
        debugSurfaceAll: true,
        mlEnabled: mlReady,
      );
      locationService.baseLocations = result.baseLocations;
      return result.memories;
    });
  }

  MemoriesCache _processOldCache(MemoriesCache? oldCache) {
    final List<PeopleShownLog> peopleShownLogs = [];
    final List<ClipShownLog> clipShownLogs = [];
    final List<TripsShownLog> tripsShownLogs = [];
    final List<ToShowMemory> toShowMemories = [];
    if (oldCache != null) {
      final now = DateTime.now();
      final nowMicros = now.microsecondsSinceEpoch;
      for (final peopleLog in oldCache.peopleShownLogs) {
        if (now.difference(
              DateTime.fromMicrosecondsSinceEpoch(peopleLog.lastTimeShown),
            ) <
            maxShowTimeout) {
          peopleShownLogs.add(peopleLog);
        }
      }
      for (final tripsLog in oldCache.tripsShownLogs) {
        if (now.difference(
              DateTime.fromMicrosecondsSinceEpoch(tripsLog.lastTimeShown),
            ) <
            maxShowTimeout) {
          tripsShownLogs.add(tripsLog);
        }
      }
      for (final clipLog in oldCache.clipShownLogs) {
        if (now.difference(
              DateTime.fromMicrosecondsSinceEpoch(clipLog.lastTimeShown),
            ) <
            maxShowTimeout) {
          clipShownLogs.add(clipLog);
        }
      }
      toShowMemories.addAll(
        _activeTripEntriesForTime(
          oldCache.toShowMemories,
          timestamp: nowMicros,
        ),
      );
      for (final oldMemory in oldCache.toShowMemories) {
        if (oldMemory.isOld) {
          if (oldMemory.type == MemoryType.people) {
            peopleShownLogs.add(PeopleShownLog.fromOldCacheMemory(oldMemory));
          } else if (oldMemory.type == MemoryType.clip) {
            clipShownLogs.add(ClipShownLog.fromOldCacheMemory(oldMemory));
          } else if (oldMemory.type == MemoryType.trips) {
            tripsShownLogs.add(TripsShownLog.fromOldCacheMemory(oldMemory));
          }
        }
      }
    }
    return MemoriesCache(
      toShowMemories: toShowMemories,
      peopleShownLogs: peopleShownLogs,
      clipShownLogs: clipShownLogs,
      tripsShownLogs: tripsShownLogs,
      baseLocations: [],
    );
  }

  Future<void> clearMemoriesCache({bool fromDisk = true}) async {
    if (fromDisk) {
      final file = File(await _getCachePath());
      if (file.existsSync()) {
        await file.delete();
      }
    }
    _cachedMemories = null;
  }

  Future<List<SmartMemory>> getMemoriesForWidget({
    required bool onThisDay,
    required bool pastYears,
    required bool smart,
    required bool hasAnyWidgets,
  }) async {
    if (!onThisDay && !pastYears && !smart) {
      _logger.info('No memories requested, returning empty list');
      return [];
    }
    final allMemories = await getMemories(onlyUseCache: !hasAnyWidgets);
    if (onThisDay && pastYears && smart) {
      return allMemories;
    }
    final filteredMemories = <SmartMemory>[];
    for (final memory in allMemories) {
      if (!memory.shouldShowNow()) continue;
      if (memory.type == MemoryType.onThisDay) {
        if (!onThisDay) continue;
      } else if (memory.type == MemoryType.filler) {
        if (!pastYears) continue;
      } else {
        if (!smart) continue;
      }
      filteredMemories.add(memory);
    }
    return filteredMemories;
  }

  Future<void> goToMemoryFromGeneratedFileID(
    int generatedFileID, {
    BuildContext? context,
  }) async {
    final allMemories = await getMemories();
    if (allMemories.isEmpty) return;
    int memoryIdx = 0;
    int fileIdx = 0;
    bool found = false;
    memoryLoop:
    for (final memory in _cachedMemories!) {
      for (final mem in memory.memories) {
        if (mem.file.generatedID == generatedFileID) {
          found = true;
          break memoryLoop;
        }
        fileIdx++;
      }
      memoryIdx++;
      fileIdx = 0;
    }
    if (!found) {
      _logger.warning(
        "Could not find memory with generatedFileID: $generatedFileID",
      );
      final file = await FilesDB.instance.getFile(generatedFileID);
      if (file == null) {
        _logger.warning(
          "Could not find file with generatedFileID fallback: $generatedFileID",
        );
        return;
      }
      if (context != null && !context.mounted) return;
      await _routeToPage(
        DetailPage(DetailPageConfiguration([file], 0, "memorywidget-fallback")),
        context: context,
        useFadeTransition: true,
      );
      return;
    }
    if (context != null && !context.mounted) return;
    await _routeToPage(
      AllMemoriesPage(
        allMemories: _cachedMemories!,
        initialPageIndex: memoryIdx,
        inititalFileIndex: fileIdx,
        isFromWidgetOrNotifications: true,
      ),
      context: context,
      useFadeTransition: true,
    );
  }

  Future<void> goToOnThisDayMemory({BuildContext? context}) async {
    final allMemories = await getMemories();
    if (allMemories.isEmpty) return;
    int memoryIdx = 0;
    bool found = false;
    memoryLoop:
    for (final memory in allMemories) {
      if (memory.type == MemoryType.onThisDay) {
        found = true;
        break memoryLoop;
      }
      memoryIdx++;
    }
    if (!found) {
      _logger.warning("Could not find onThisDay memory");
      return;
    }
    if (context != null && !context.mounted) return;
    await _routeToPage(
      AllMemoriesPage(
        allMemories: allMemories,
        initialPageIndex: memoryIdx,
        inititalFileIndex: 0,
        isFromWidgetOrNotifications: true,
      ),
      context: context,
      useFadeTransition: true,
    );
  }

  Future<void> goToPersonMemory(
    String personID, {
    BuildContext? context,
  }) async {
    final allMemories = await getMemories();
    if (allMemories.isEmpty) return;
    final personMemories = <PeopleMemory>[];
    for (final memory in allMemories) {
      if (memory is PeopleMemory &&
          (memory.isBirthday ?? false) &&
          memory.personID == personID) {
        personMemories.add(memory);
      }
    }
    if (personMemories.isEmpty) {
      _logger.severe("No person memories found");
    }
    PeopleMemory? personMemory;
    for (final memory in personMemories) {
      if (memory.peopleMemoryType == PeopleMemoryType.youAndThem) {
        _logger.info("Found youAndThem person memory");
        personMemory = memory;
        break; // breaking to prefer youAndThem over spotlight
      }
      if (memory.peopleMemoryType == PeopleMemoryType.spotlight) {
        _logger.info("Found spotlight person memory");
        personMemory = memory;
      }
    }

    if (personMemory == null) {
      _logger.severe(
        "Could not find person memory, routing to person page instead",
      );
      final person = await PersonService.instance.getPerson(personID);
      if (person == null) {
        _logger.severe("Person with ID $personID not found");
        return;
      }
      if (context != null && !context.mounted) return;
      await _routeToPage(
        PeoplePage(person: person, searchResult: null),
        context: context,
        useFadeTransition: true,
      );
      return;
    }
    if (context != null && !context.mounted) return;
    await _routeToPage(
      FullScreenMemoryDataUpdater(
        initialIndex: 0,
        memories: personMemory.memories,
        child: Container(
          color: backgroundColorDark,
          width: double.infinity,
          height: double.infinity,
          child: FullScreenMemory(personMemory.title, 0),
        ),
      ),
      context: context,
      useFadeTransition: true,
    );
  }

  Future<void> _routeToPage(
    Widget page, {
    BuildContext? context,
    required bool useFadeTransition,
  }) async {
    if (context != null) {
      await routeToPage(context, page, useFadeTransition: useFadeTransition);
      return;
    }

    await AppNavigationService.instance.pushPage(
      page,
      useFadeTransition: useFadeTransition,
    );
  }

  Future<void> toggleOnThisDayNotifications() async {
    final oldValue = localSettings.isOnThisDayNotificationsEnabled;
    await localSettings.setOnThisDayNotificationsEnabled(!oldValue);
    _logger.info("Turning onThisDayNotifications ${oldValue ? "off" : "on"}");
    if (oldValue) {
      await _clearAllScheduledOnThisDayNotifications();
    } else {
      queueUpdateCache();
    }
  }

  Future<void> toggleBirthdayNotifications() async {
    final oldValue = localSettings.birthdayNotificationsEnabled;
    await localSettings.setBirthdayNotificationsEnabled(!oldValue);
    _logger.info("Turning birhtdayNotifications ${oldValue ? "off" : "on"}");
    if (oldValue) {
      await _clearAllScheduledBirthdayNotifications();
    } else {
      queueUpdateCache();
    }
  }

  Future<void> _scheduleMemoryNotifications(
    List<SmartMemory> allMemories,
  ) async {
    await _scheduleOnThisDayNotifications(allMemories);
    await _scheduleBirthdayNotifications(allMemories);
  }

  Future<void> _scheduleOnThisDayNotifications(
    List<SmartMemory> allMemories,
  ) async {
    if (!localSettings.isOnThisDayNotificationsEnabled) {
      _logger.info(
        "On this day notifications are disabled, skipping scheduling",
      );
      return;
    }
    await _clearAllScheduledOnThisDayNotifications();
    final scheduledDates = <DateTime>{};
    for (final memory in allMemories) {
      if (memory.type != MemoryType.onThisDay) {
        continue;
      }
      final numberOfMemories = memory.memories.length;
      if (numberOfMemories < 5) continue;
      final firstDateToShow = DateTime.fromMicrosecondsSinceEpoch(
        memory.firstDateToShow,
      );
      final scheduleTime = DateTime(
        firstDateToShow.year,
        firstDateToShow.month,
        firstDateToShow.day,
        8,
      );
      if (scheduleTime.isBefore(DateTime.now())) {
        _logger.info(
          "Skipping scheduling notification for memory ${memory.id} because the date is in the past (date: $scheduleTime)",
        );
        continue;
      }
      if (scheduledDates.contains(scheduleTime)) {
        _logger.info(
          "Skipping scheduling notification for memory ${memory.id} because the date is already scheduled (date: $scheduleTime)",
        );
        continue;
      }
      final s = await LanguageService.locals;
      await NotificationService.instance.scheduleNotification(
        s.onThisDay,
        message: s.lookBackOnYourMemories,
        id: memory.id.hashCode,
        channelID: "onThisDay",
        channelName: s.onThisDay,
        payload: memory.id,
        dateTime: scheduleTime,
        timeoutDurationAndroid: const Duration(hours: 16),
      );
      scheduledDates.add(scheduleTime);
      _logger.info(
        "Scheduled notification for memory ${memory.id} on date: $scheduleTime",
      );
    }
  }

  Future<void> _scheduleBirthdayNotifications(
    List<SmartMemory> allMemories,
  ) async {
    if (!localSettings.birthdayNotificationsEnabled) {
      _logger.info("birthday notifications are disabled, skipping scheduling");
      return;
    }
    await _clearAllScheduledBirthdayNotifications();
    final scheduledPersons = <String>{};
    final toSchedule = <PeopleMemory>[];
    final peopleToBirthdayMemories = <String, List<PeopleMemory>>{};
    for (final memory in allMemories) {
      if (memory is PeopleMemory && (memory.isBirthday ?? false)) {
        peopleToBirthdayMemories
            .putIfAbsent(memory.personID, () => [])
            .add(memory);
      }
    }
    personLoop:
    for (final personID in peopleToBirthdayMemories.keys) {
      final birthdayMemories = peopleToBirthdayMemories[personID]!;
      for (final memory in birthdayMemories) {
        if (memory.peopleMemoryType == PeopleMemoryType.youAndThem) {
          toSchedule.add(memory);
          continue personLoop;
        }
      }
      for (final memory in birthdayMemories) {
        if (memory.peopleMemoryType == PeopleMemoryType.spotlight) {
          toSchedule.add(memory);
          continue personLoop;
        }
      }
    }
    for (final memory in toSchedule) {
      final firstDateToShow = DateTime.fromMicrosecondsSinceEpoch(
        memory.firstDateToShow,
      );
      final scheduleTime = DateTime(
        firstDateToShow.year,
        firstDateToShow.month,
        firstDateToShow.day,
      );
      if (scheduleTime.isBefore(DateTime.now())) {
        _logger.info(
          "Skipping scheduling notification for memory ${memory.id} because the date is in the past",
        );
        continue;
      }
      if (scheduledPersons.contains(memory.personID)) {
        _logger.severe(
          "Skipping scheduling notification for memory ${memory.id} because the person's birthday is already scheduled",
        );
        continue;
      }
      final s = await LanguageService.locals;
      final hasNonEmptyName =
          memory.personName != null && memory.personName!.trim().isNotEmpty;
      await NotificationService.instance.scheduleNotification(
        hasNonEmptyName && !memory.isUnnamedCluster
            ? s.wishThemAHappyBirthday(name: memory.personName!)
            : s.happyBirthday,
        id: memory.id.hashCode,
        channelID: "birthday",
        channelName: s.birthdays,
        payload: "birthday_${memory.personID}",
        dateTime: scheduleTime,
        timeoutDurationAndroid: const Duration(hours: 24),
      );
      scheduledPersons.add(memory.personID);
      _logger.info(
        "Scheduled birthday notification for person ${memory.personID} on date: $scheduleTime",
      );
    }
  }

  Future<void> _clearAllScheduledOnThisDayNotifications() async {
    _logger.info('Clearing all scheduled On This Day notifications');
    await NotificationService.instance.clearAllScheduledNotifications(
      containingPayload: "onThisDay",
    );
  }

  Future<void> _clearAllScheduledBirthdayNotifications() async {
    _logger.info('Clearing all scheduled birthday notifications');
    await NotificationService.instance.clearAllScheduledNotifications(
      containingPayload: "birthday",
    );
  }
}
