import "dart:async";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/errors.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/user_config.dart";
import "package:photos/db/common/conflict_algo.dart";
import "package:photos/db/device_files_db.dart";
import "package:photos/db/file_updation_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/backup_folders_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/permission_granted_event.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ignored_file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_lifecycle_service.dart";
import "package:photos/services/device_folder_confirmed_ente_move_queue.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/import/diff.dart";
import "package:photos/services/sync/import/local_assets.dart";
import "package:photos/services/sync/import/model.dart";
import "package:photos/services/sync/origin_fetch_tracker.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";
import "package:tuple/tuple.dart";

class LocalSyncService {
  final _logger = Logger("LocalSyncService");
  final _db = FilesDB.instance;
  late SharedPreferences _prefs;
  Completer<void>? _existingSync;
  late Debouncer _changeCallbackDebouncer;
  StreamSubscription<PermissionGrantedEvent>? _permissionGrantedSubscription;
  bool _isChangeCallbackRegistered = false;
  final Lock _lock = Lock();

  static const kDbUpdationTimeKey = "db_updation_time";
  static const kHasCompletedFirstImportKey = "has_completed_firstImport";

  LocalSyncService._privateConstructor();

  static final LocalSyncService instance =
      LocalSyncService._privateConstructor();

  Future<void> init(SharedPreferences preferences) async {
    _prefs = preferences;
    if (!AppLifecycleService.instance.isForeground) {
      await PhotoManager.setIgnorePermissionCheck(true);
    }
    if (permissionService.hasGrantedPermissions()) {
      _registerChangeCallback();
    } else {
      if (_permissionGrantedSubscription != null) {
        await _permissionGrantedSubscription!.cancel();
      }
      _permissionGrantedSubscription = Bus.instance
          .on<PermissionGrantedEvent>()
          .listen((event) async {
            if (!permissionService.hasGrantedPermissions()) {
              return;
            }
            _registerChangeCallback();
            if (isLocalGalleryMode) {
              // Local gallery onboarding grants permission without explicitly
              // invoking SyncService, so trigger local import right away.
              unawaited(checkAndSync());
            }
          });
    }
  }

  Future<void> sync() async {
    if (!permissionService.hasGrantedPermissions()) {
      _logger.info("Skipping local sync since permission has not been granted");
      return;
    }
    if (Platform.isAndroid && AppLifecycleService.instance.isForeground) {
      final permissionState = await permissionService
          .requestPhotoMangerPermissions();
      if (permissionState != PermissionState.authorized) {
        _logger.warning(
          "Skipping local sync because Android gallery permission is "
          "$permissionState",
        );
        return;
      }
    }
    _registerChangeCallback();
    if (_existingSync != null) {
      _logger.warning("Sync already in progress, skipping.");
      return _existingSync!.future;
    }
    _existingSync = Completer<void>();
    final int ownerID = Configuration.instance.getUserIDV2();

    // Local sync must not race downloads; that can create incorrect FilesDB
    // rows.
    await _lock.synchronized(() async {
      final existingLocalFileIDs = await _db.getExistingLocalFileIDs(ownerID);
      _logger.info("${existingLocalFileIDs.length} localIDs were discovered");

      final syncStartTime = DateTime.now().microsecondsSinceEpoch;
      final lastDBUpdationTime = _prefs.getInt(kDbUpdationTimeKey) ?? 0;
      final startTime = DateTime.now().microsecondsSinceEpoch;
      if (lastDBUpdationTime != 0) {
        await _loadAndStoreDiff(
          existingLocalFileIDs,
          fromTime: lastDBUpdationTime,
          toTime: syncStartTime,
        );
      } else {
        Bus.instance.fire(
          SyncStatusUpdate(SyncStatus.startedFirstGalleryImport),
        );
        var startTime = 0;
        var toYear = 2010;
        var toTime = DateTime(toYear).microsecondsSinceEpoch;
        while (toTime < syncStartTime) {
          await _loadAndStoreDiff(
            existingLocalFileIDs,
            fromTime: startTime,
            toTime: toTime,
          );
          startTime = toTime;
          toYear++;
          toTime = DateTime(toYear).microsecondsSinceEpoch;
        }
        await _loadAndStoreDiff(
          existingLocalFileIDs,
          fromTime: startTime,
          toTime: syncStartTime,
        );
      }
      final hasCompletedInitialImport = hasCompletedFirstImport();
      final shouldCompleteLocalGalleryHandoff =
          !isLocalGalleryMode && localSettings.isFromLocalGalleryToEnte;
      if (!hasCompletedInitialImport || shouldCompleteLocalGalleryHandoff) {
        await _prefs.setBool(kHasCompletedFirstImportKey, true);
        if (isLocalGalleryMode) {
          await localSettings.setIsFromLocalGalleryToEnte(true);
        } else if (shouldCompleteLocalGalleryHandoff) {
          await localSettings.setIsFromLocalGalleryToEnte(false);
        }
        if (backupPreferenceService.hasSkippedOnboardingPermission) {
          await backupPreferenceService.setOnboardingPermissionSkipped(false);
        }
        await _refreshDeviceFolderCountAndCover(isFirstSync: true);
        _logger.info("first gallery import finished");
        Bus.instance.fire(
          SyncStatusUpdate(SyncStatus.completedFirstGalleryImport),
        );
      }
      final endTime = DateTime.now().microsecondsSinceEpoch;
      final duration = Duration(microseconds: endTime - startTime);
      _logger.info("Load took " + duration.inMilliseconds.toString() + "ms");
    });

    _existingSync?.complete();
    _existingSync = null;
  }

  Future<bool> _refreshDeviceFolderCountAndCover({
    bool isFirstSync = false,
  }) async {
    final List<Tuple2<AssetPathEntity, String>> result =
        await getDeviceFolderWithCountAndCoverID();
    final bool hasUpdated = await _db.updateDeviceCoverWithCount(
      result,
      shouldBackup: backupPreferenceService.hasSelectedAllFoldersForBackup,
    );
    // Firing this during first sync skips the backup-folder screen.
    if (hasUpdated && !isFirstSync) {
      Bus.instance.fire(BackupFoldersUpdatedEvent());
    }
    return hasUpdated;
  }

  Future<bool> syncAll() => _lock.synchronized(_syncAll);

  Future<void> processPendingConfirmedDeviceFolderMoves() => _lock.synchronized(
    DeviceFolderConfirmedEnteMoveQueue.instance.processPendingMoves,
  );

  Future<void> refreshAfterDeviceFolderTransfer() => _lock.synchronized(
    () async {
      try {
        await _syncAll();
        await RemoteSyncService.instance.sync(silently: true);
        await DeviceFolderConfirmedEnteMoveQueue.instance.processPendingMoves();
      } catch (error, stackTrace) {
        _logger.warning(
          'Could not refresh local state after device-folder transfer',
          error,
          stackTrace,
        );
      }
    },
  );

  Future<bool> _syncAll() async {
    if (!Configuration.instance.isLoggedIn()) {
      if (!isLocalGalleryMode) {
        _logger.warning("syncAll called when user is not logged in");
        return false;
      }
    }
    final stopwatch = EnteWatch("localSyncAll")..start();

    final localAssets = await getAllLocalAssets(
      needsTitle: isLocalGalleryMode ? true : null,
    );
    final previousPathToLocalIDs = await _db.getDevicePathIDToLocalIDMap();
    _logger.info(
      "Loading allLocalAssets ${localAssets.length} took ${stopwatch.elapsedMilliseconds}ms ",
    );
    await _refreshDeviceFolderCountAndCover();
    _logger.info(
      "refreshDeviceFolderCountAndCover + allLocalAssets took ${stopwatch.elapsedMilliseconds}ms ",
    );
    final int ownerID = Configuration.instance.getUserIDV2();
    final existingLocalFileIDs = await _db.getExistingLocalFileIDs(ownerID);
    final localDiffResult = await getDiffFromExistingImport(
      localAssets,
      existingLocalFileIDs,
      previousPathToLocalIDs,
    );
    bool hasAnyMappingChanged = false;
    if (localDiffResult.newPathToLocalIDs?.isNotEmpty ?? false) {
      await _db.insertPathIDToLocalIDMapping(
        localDiffResult.newPathToLocalIDs!,
      );
      hasAnyMappingChanged = true;
    }
    if (localDiffResult.deletePathToLocalIDs?.isNotEmpty ?? false) {
      await _db.deletePathIDToLocalIDMapping(
        localDiffResult.deletePathToLocalIDs!,
      );
      hasAnyMappingChanged = true;
    }
    final bool hasUnsyncedFiles =
        localDiffResult.uniqueLocalFiles?.isNotEmpty ?? false;
    if (hasUnsyncedFiles) {
      await _db.insertMultiple(
        localDiffResult.uniqueLocalFiles!,
        conflictAlgorithm: SqliteAsyncConflictAlgorithm.ignore,
      );
      _logger.info(
        "Inserted ${localDiffResult.uniqueLocalFiles?.length} "
        "un-synced files",
      );
    }
    debugPrint(
      "syncAll: mappingChange : $hasAnyMappingChanged, "
      "unSyncedFiles: $hasUnsyncedFiles",
    );
    if (hasAnyMappingChanged || hasUnsyncedFiles) {
      final newlyDiscoveredFiles = localDiffResult.uniqueLocalFiles ?? [];
      final newlyDiscoveredLocalIDs = newlyDiscoveredFiles
          .map((file) => file.localID)
          .nonNulls
          .toSet();
      final newlyMappedLocalIDs =
          localDiffResult.newPathToLocalIDs?.values.expand((ids) => ids) ??
          const Iterable<String>.empty();
      final hasOnlyNewFiles =
          hasUnsyncedFiles &&
          (localDiffResult.deletePathToLocalIDs?.isEmpty ?? true) &&
          newlyMappedLocalIDs.every(newlyDiscoveredLocalIDs.contains);
      Bus.instance.fire(
        _localPhotosUpdatedEvent(
          updatedFiles: newlyDiscoveredFiles,
          newlyInsertedFiles: newlyDiscoveredFiles,
          source: "syncAllChange",
          hasOnlyNewFiles: hasOnlyNewFiles,
        ),
      );
    }
    if (flagService.syncRecoveryDiagnostics) {
      final int newMappingCount =
          localDiffResult.newPathToLocalIDs?.values.fold<int>(
            0,
            (sum, ids) => sum + ids.length,
          ) ??
          0;
      final int deletedMappingCount =
          localDiffResult.deletePathToLocalIDs?.values.fold<int>(
            0,
            (sum, ids) => sum + ids.length,
          ) ??
          0;
      if (newMappingCount > 0 || deletedMappingCount > 0 || hasUnsyncedFiles) {
        final sampleRecovered = (localDiffResult.uniqueLocalFiles ?? [])
            .take(3)
            .map((file) => file.localID)
            .toList();
        _logger.info(
          "syncAll recovery: "
          "newFiles=${localDiffResult.uniqueLocalFiles?.length ?? 0}, "
          "newMappings=$newMappingCount, "
          "deletedMappings=$deletedMappingCount, "
          "sampleRecovered=$sampleRecovered",
        );
      }
    }

    _logger.info("syncAll took ${stopwatch.elapsed.inMilliseconds}ms ");
    // syncAll can repair mappings without inserting new local files.
    // We still need the follow-up remote sync to promote those entries.
    return hasUnsyncedFiles || hasAnyMappingChanged;
  }

  Future<void> ignoreUpload(EnteFile file, InvalidFileError error) async {
    if (file.localID == null ||
        file.deviceFolder == null ||
        file.title == null) {
      _logger.warning('Invalid file received for ignoring: $file');
      return;
    }
    if (Platform.isIOS && error.reason == InvalidReason.sourceFileMissing) {
      // Do not persist this failure; iCloud may make the asset available later.
      return;
    }
    final reason = error.reason == InvalidReason.photosResourceUnavailable
        ? (error.message?.toString() ?? error.reason.name)
        : error.reason.name;
    final ignored = IgnoredFile(
      file.localID,
      file.title,
      file.deviceFolder,
      reason,
    );
    await IgnoredFilesService.instance.cacheAndInsert([ignored]);
  }

  Lock getLock() {
    return _lock;
  }

  bool hasCompletedFirstImport() {
    return _prefs.getBool(kHasCompletedFirstImportKey) ?? false;
  }

  // Onboarding skips and only-new backup intentionally bypass the first import.
  bool hasCompletedFirstImportOrBypassed() {
    if (!isLocalGalleryMode &&
        Configuration.instance.hasConfiguredAccount() &&
        localSettings.isFromLocalGalleryToEnte) {
      return false;
    }
    if (hasCompletedFirstImport()) {
      return true;
    }
    return backupPreferenceService.hasSkippedOnboardingPermission ||
        backupPreferenceService.isOnlyNewBackupEnabled;
  }

  Future<void> _loadAndStoreDiff(
    Set<String> existingLocalDs, {
    required int fromTime,
    required int toTime,
  }) async {
    final Tuple2<List<LocalPathAsset>, List<EnteFile>> result =
        await getLocalPathAssetsAndFiles(fromTime, toTime);

    final List<EnteFile> files = result.item2;
    if (files.isNotEmpty) {
      await FilesDB.instance.insertLocalAssets(
        result.item1,
        shouldAutoBackup:
            backupPreferenceService.hasSelectedAllFoldersForBackup,
      );

      _logger.info(
        "Loaded ${files.length} photos from " +
            DateTime.fromMicrosecondsSinceEpoch(fromTime).toString() +
            " to " +
            DateTime.fromMicrosecondsSinceEpoch(toTime).toString(),
      );
      await _trackUpdatedFiles(files, existingLocalDs);
      final List<EnteFile> allFiles = [];
      allFiles.addAll(files);
      files.removeWhere((file) => existingLocalDs.contains(file.localID));
      await _db.insertMultiple(
        files,
        conflictAlgorithm: SqliteAsyncConflictAlgorithm.ignore,
      );
      _logger.info('Inserted ${files.length} out of ${allFiles.length} files');
      if (flagService.syncRecoveryDiagnostics &&
          allFiles.length != files.length) {
        final sampleLocalIDs = allFiles
            .take(3)
            .map((file) => file.localID)
            .toList();
        _logger.info(
          "localSync partial materialization: "
          "from=$fromTime to=$toTime "
          "discovered=${allFiles.length} inserted=${files.length} "
          "sampleLocalIDs=$sampleLocalIDs",
        );
      }
      _checkAndFireLocalAssetUpdateEvent(allFiles, files);
    }
    await _prefs.setInt(kDbUpdationTimeKey, toTime);
  }

  void _checkAndFireLocalAssetUpdateEvent(
    List<EnteFile> allFiles,
    List<EnteFile> newlyInsertedFiles,
  ) {
    if (allFiles.isEmpty) return;
    final bool discoveredNewFiles = newlyInsertedFiles.isNotEmpty;
    if (!discoveredNewFiles) {
      allFiles.removeWhere(originFetchTracker.isUnchangedSinceFetch);
      if (allFiles.isEmpty) {
        _logger.info("skipping firing LocalPhotosUpdatedEvent as no new files");
        return;
      }
    }

    Bus.instance.fire(
      _localPhotosUpdatedEvent(
        updatedFiles: allFiles,
        newlyInsertedFiles: newlyInsertedFiles,
        source: "loadedPhoto",
        hasOnlyNewFiles:
            discoveredNewFiles && allFiles.length == newlyInsertedFiles.length,
      ),
    );
  }

  LocalPhotosUpdatedEvent _localPhotosUpdatedEvent({
    required List<EnteFile> updatedFiles,
    required List<EnteFile> newlyInsertedFiles,
    required String source,
    required bool hasOnlyNewFiles,
  }) {
    final sevenDaysAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .microsecondsSinceEpoch;
    final hasRecentNewLocalDiscovery = newlyInsertedFiles.any(
      (file) => (file.creationTime ?? 0) > sevenDaysAgo,
    );
    if (hasOnlyNewFiles) {
      return LocalPhotosAddedEvent(
        newlyInsertedFiles,
        source: source,
        hasRecentNewLocalDiscovery: hasRecentNewLocalDiscovery,
      );
    }
    return LocalPhotosUpdatedEvent(
      updatedFiles,
      source: source,
      hasRecentNewLocalDiscovery: hasRecentNewLocalDiscovery,
    );
  }

  Future<void> _trackUpdatedFiles(
    List<EnteFile> files,
    Set<String> existingLocalFileIDs,
  ) async {
    final List<EnteFile> updatedFiles = files
        .where(
          (file) =>
              file.localID != null &&
              existingLocalFileIDs.contains(file.localID),
        )
        .toList();

    if (updatedFiles.isNotEmpty) {
      final int updateCount = updatedFiles.length;
      updatedFiles.removeWhere((file) {
        final comparison = originFetchTracker.comparisonFor(file);
        if (comparison == null) return false;

        final title = file.title;
        _logger.info(
          "Origin fetch update decision for localID=${file.localID}"
          "${title == null || title.isEmpty ? '' : ', title=$title'}, "
          "modificationTime=${comparison.modificationTimeAtFetch} -> "
          "${comparison.observedModificationTime}, "
          "skipped=${comparison.shouldSkip}",
        );
        return comparison.shouldSkip;
      });
      _logger.info(
        "track ${updatedFiles.length}/ $updateCount files due to modification change",
      );
      if (updatedFiles.isNotEmpty) {
        await FileUpdationDB.instance.insertMultiple(
          updatedFiles.map((file) => file.localID!).toList(),
          FileUpdationDB.modificationTimeUpdated,
        );
      }
    }
  }

  void _registerChangeCallback() {
    if (_isChangeCallbackRegistered) {
      return;
    }
    _isChangeCallbackRegistered = true;
    _changeCallbackDebouncer = Debouncer(const Duration(milliseconds: 500));
    // iOS fires this immediately after the limited-access picker closes.
    PhotoManager.addChangeCallback((value) async {
      _logger.info("Something changed on disk");
      _changeCallbackDebouncer.run(() async {
        unawaited(checkAndSync());
      });
    });
    PhotoManager.startChangeNotify();
  }

  Future<void> checkAndSync() async {
    if (_existingSync != null) {
      await _existingSync!.future;
    }
    if (permissionService.hasGrantedLimitedPermissions()) {
      unawaited(syncAll());
    } else {
      unawaited(sync().then((value) => _refreshDeviceFolderCountAndCover()));
    }
  }
}
