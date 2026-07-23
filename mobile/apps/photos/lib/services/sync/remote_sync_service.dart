import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/file_updation_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/backup_folders_updated_event.dart';
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/diff_sync_complete_event.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_home_gallery_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/events/sync_status_update_event.dart';
import 'package:photos/extensions/logger_extension.dart';
import 'package:photos/main.dart' show isProcessBg;
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/extensions/file_props.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/upload_strategy.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/module/upload/service/local_file_update_service.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/app_lifecycle_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/hidden_service.dart';
import 'package:photos/services/ignored_files_service.dart';
import 'package:photos/services/language_service.dart';
import 'package:photos/services/notification_service.dart';
import 'package:photos/services/social_notification_coordinator.dart';
import 'package:photos/services/social_sync_service.dart';
import 'package:photos/services/sync/diff_fetcher.dart';
import 'package:photos/services/sync/sync_service.dart';
import 'package:photos/utils/network_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteSyncService {
  final _logger = Logger("RemoteSyncService");
  final _db = FilesDB.instance;
  final FileUploader _uploader = FileUploader.instance;
  final Configuration _config = Configuration.instance;
  final CollectionsService _collectionsService = CollectionsService.instance;
  final DiffFetcher _diffFetcher = DiffFetcher();
  final PhotoManagerPlugin _photoManagerPlugin = PhotoManagerPlugin();
  final LocalFileUpdateService _localFileUpdateService =
      LocalFileUpdateService.instance;
  int _completedUploads = 0;
  int _ignoredUploads = 0;
  late SharedPreferences _prefs;
  Completer<void>? _existingSync;
  bool _isExistingSyncSilent = false;
  StreamSubscription<LocalPhotosUpdatedEvent>? _localPhotosUpdatedSubscription;

  // _hasCleanupStaleEntry is used to track if we have already cleaned up
  // statle db entries in this sync session.
  bool _hasCleanupStaleEntry = false;

  static const kHasSyncedArchiveKey = "has_synced_archive";
  /* This setting is used to maintain a list of local IDs for videos that the user has manually
 marked for upload, even if the global video upload setting is currently disabled.
 When the global video upload setting is disabled, we typically ignore all video uploads. However, for videos that have been added to this list, we
 want to still allow them to be uploaded, despite the global setting being disabled.

 This allows users to queue up videos for upload, and have them successfully upload
 even if they later toggle the global video upload setting to disabled.
   */
  static const _ignoreBackUpSettingsForIDs_ = "ignoreBackUpSettingsForIDs";
  final String _isFirstRemoteSyncDone = "isFirstRemoteSyncDone";

  // 28 Sept, 2021 9:03:20 AM IST
  static const kArchiveFeatureReleaseTime = 1632800000000000;
  static const kHasSyncedEditTime = "has_synced_edit_time";

  // 29 October, 2021 3:56:40 AM IST
  static const kEditTimeFeatureReleaseTime = 1635460000000000;

  static const kMaximumPermissibleUploadsInThrottledMode = 4;
  static final RemoteSyncService instance =
      RemoteSyncService._privateConstructor();

  RemoteSyncService._privateConstructor();

  void init(SharedPreferences preferences) {
    _prefs = preferences;

    _localPhotosUpdatedSubscription?.cancel();
    _localPhotosUpdatedSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .listen((event) async {
          if (event.type == EventType.addedOrUpdated) {
            if (_existingSync == null) {
              // ignore: unawaited_futures
              sync();
            }
          }
        });
  }

  Future<void> sync({bool silently = false}) async {
    if (!_config.hasConfiguredAccount()) {
      _logger.info("Skipping remote sync since account is not configured");
      return;
    }
    if (_existingSync != null) {
      _logger.info("Remote sync already in progress, skipping");
      // if current sync is silent but request sync is non-silent (demands UI
      // updates), update the syncSilently flag
      if (_isExistingSyncSilent && !silently) {
        _isExistingSyncSilent = false;
      }
      return _existingSync?.future;
    }
    _existingSync = Completer<void>();
    _isExistingSyncSilent = silently;
    _logger.info(
      "Starting remote sync " +
          (silently ? "silently" : " with status updates"),
    );

    try {
      final canPrepareUploadsInBackground =
          !isProcessBg || await canUseHighBandwidth();

      // use flag to decide if we should start marking files for upload before
      // remote-sync is done. This is done to avoid adding existing files to
      // the same or different collection when user had already uploaded them
      // before.
      final bool hasSyncedBefore = _prefs.containsKey(_isFirstRemoteSyncDone);
      if (hasSyncedBefore && canPrepareUploadsInBackground) {
        await syncDeviceCollectionFilesForUpload();
      }
      await _pullDiff();
      await trashSyncService.syncTrash();
      await _collectionsService.movePendingRemovalActionsToUncategorized();

      // Sync social data immediately after diff sync, before uploads
      if (AppLifecycleService.instance.isForeground) {
        _socialSync().ignore();
      } else {
        await _socialSync();
      }

      if (!hasSyncedBefore) {
        await _prefs.setBool(_isFirstRemoteSyncDone, true);
        if (canPrepareUploadsInBackground) {
          await syncDeviceCollectionFilesForUpload();
        }
      }

      if (
      // We don't need syncFDStatus here if in background
      !isProcessBg) {
        fileDataService.syncFDStatus().ignore();
      }

      if (!canPrepareUploadsInBackground) {
        throw WiFiUnavailableError();
      }

      final filesToBeUploaded = await _getFilesToBeUploaded();
      final hasUploadedFiles = await _uploadFiles(filesToBeUploaded);
      if (filesToBeUploaded.isNotEmpty) {
        _logger.info(
          "Files ${filesToBeUploaded.length} queued for upload, completed: "
          "$_completedUploads, ignored $_ignoredUploads",
        );
      } else {
        _logger.info("No files to upload for this session");
      }
      if (hasUploadedFiles) {
        await _pullDiff();
        _existingSync?.complete();
        _existingSync = null;
        await syncDeviceCollectionFilesForUpload();
        final hasMoreFilesToBackup = (await _getFilesToBeUploaded()).isNotEmpty;
        _logger.info("hasMoreFilesToBackup?" + hasMoreFilesToBackup.toString());
        if (hasMoreFilesToBackup) {
          // Skipping a resync to ensure that files that were ignored in this
          // session are not processed now
          await sync();
        } else {
          _logger.info("Fire backup completed event");
          Bus.instance.fire(SyncStatusUpdate(SyncStatus.completedBackup));
        }
      } else {
        // if filesToBeUploaded is empty, clear any stale files in the temp
        // directory
        if (filesToBeUploaded.isEmpty) {
          await _uploader.removeStaleFiles();
        }
        if (_ignoredUploads > 0) {
          _logger.info(
            "Ignored $_ignoredUploads files for upload, fire "
            "backup done",
          );
          Bus.instance.fire(SyncStatusUpdate(SyncStatus.completedBackup));
        }
        _existingSync?.complete();
        _existingSync = null;
      }
    } catch (e, s) {
      _existingSync?.complete();
      _existingSync = null;
      _logger.warning("Error executing remote sync", e, s);

      if (flagService.internalUser ||
          // rethrow whitelisted error so that UI status can be updated correctly.
          {
            UnauthorizedError,
            NoActiveSubscriptionError,
            WiFiUnavailableError,
            StorageLimitExceededError,
            SyncStopRequestedError,
            NoMediaLocationAccessError,
          }.contains(e.runtimeType)) {
        rethrow;
      }
    } finally {
      _isExistingSyncSilent = false;
    }
  }

  bool isFirstRemoteSyncDone() {
    return _prefs.containsKey(_isFirstRemoteSyncDone);
  }

  Future<bool> whiteListVideoForUpload(EnteFile file) async {
    if (file.fileType == FileType.video &&
        !backupSettings.shouldBackupVideos() &&
        file.localID != null) {
      final List<String> whitelistedIDs =
          _prefs.getStringList(_ignoreBackUpSettingsForIDs_) ?? <String>[];
      whitelistedIDs.add(file.localID!);
      return _prefs.setStringList(_ignoreBackUpSettingsForIDs_, whitelistedIDs);
    }
    return false;
  }

  Future<void> _pullDiff() async {
    _logger.info("Pulling remote diff");
    final isFirstSync = !_collectionsService.hasSyncedCollections();
    if (isFirstSync && !_isExistingSyncSilent) {
      Bus.instance.fire(SyncStatusUpdate(SyncStatus.applyingRemoteDiff));
    }
    await _collectionsService.sync();
    // check and reset user's collection syncTime in past for older clients
    if (isFirstSync) {
      // not need reset syncTime, mark all flags as done if firstSync
      await _markResetSyncTimeAsDone();
    } else if (_shouldResetSyncTime()) {
      _logger.warning('Resetting syncTime for for the client');
      await _resetAllCollectionsSyncTime();
      await _markResetSyncTimeAsDone();
    }

    final idsToRemoteUpdationTimeMap = await _collectionsService
        .getCollectionIDsToBeSynced();
    await _syncUpdatedCollections(idsToRemoteUpdationTimeMap);
    unawaited(_localFileUpdateService.markUpdatedFilesForReUpload());
    unawaited(_notifyNewFiles(idsToRemoteUpdationTimeMap.keys.toList()));
  }

  Future<void> _syncUpdatedCollections(
    final Map<int, int> idsToRemoteUpdationTimeMap,
  ) async {
    for (final cid in idsToRemoteUpdationTimeMap.keys) {
      await _syncCollectionDiff(
        cid,
        _collectionsService.getCollectionSyncTime(cid),
      );
      // update syncTime for the collection in sharedPrefs. Note: the
      // syncTime can change on remote but we might not get a diff for the
      // collection if there are not changes in the file, but the collection
      // metadata (name, archive status, sharing etc) has changed.
      final remoteUpdateTime = idsToRemoteUpdationTimeMap[cid];
      await _collectionsService.setCollectionSyncTime(cid, remoteUpdateTime);
    }
    _logger.info("All updated collections synced");
    Bus.instance.fire(DiffSyncCompleteEvent());
  }

  Future<void> _resetAllCollectionsSyncTime() async {
    final resetSyncTime = _getSinceTimeForReSync();
    _logger.info('re-setting all collections syncTime to: $resetSyncTime');
    final collections = _collectionsService.getActiveCollections();
    for (final c in collections) {
      final int newSyncTime = min(
        _collectionsService.getCollectionSyncTime(c.id),
        resetSyncTime,
      );
      await _collectionsService.setCollectionSyncTime(c.id, newSyncTime);
    }
  }

  Future<void> _syncCollectionDiff(int collectionID, int sinceTime) async {
    _logger.info(
      "[Collection-$collectionID] fetch diff silently: $_isExistingSyncSilent "
      "since: $sinceTime",
    );
    if (!_isExistingSyncSilent) {
      Bus.instance.fire(SyncStatusUpdate(SyncStatus.applyingRemoteDiff));
    }
    final diff = await _diffFetcher.getEncryptedFilesDiff(
      collectionID,
      sinceTime,
    );
    if (diff.deletedFiles.isNotEmpty) {
      await _syncCollectionDiffDelete(diff, collectionID);
    }
    if (diff.updatedFiles.isNotEmpty) {
      await _storeDiff(diff.updatedFiles, collectionID);
      _logger.info(
        "[Collection-$collectionID] Updated ${diff.updatedFiles.length} files"
        " from remote",
      );
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          diff.updatedFiles,
          source: "syncUpdateFromRemote",
        ),
      );
      Bus.instance.fire(
        CollectionUpdatedEvent(
          collectionID,
          diff.updatedFiles,
          "syncUpdateFromRemote",
        ),
      );
    }

    if (diff.latestUpdatedAtTime > 0) {
      await _collectionsService.setCollectionSyncTime(
        collectionID,
        diff.latestUpdatedAtTime,
      );
    }
    if (diff.hasMore) {
      return await _syncCollectionDiff(
        collectionID,
        _collectionsService.getCollectionSyncTime(collectionID),
      );
    }
    _logger.info("[Collection-$collectionID] synced");
  }

  Future<void> joinAndSyncCollection(
    BuildContext context,
    int collectionID,
  ) async {
    await _collectionsService.joinPublicCollection(context, collectionID);
    await _collectionsService.sync();
    await _syncCollectionDiff(collectionID, 0);
  }

  Future<void> _syncCollectionDiffDelete(Diff diff, int collectionID) async {
    final fileIDs = diff.deletedFiles.map((f) => f.uploadedFileID!).toList();
    final localDeleteCount = await _db.deleteFilesFromCollection(
      collectionID,
      fileIDs,
    );
    if (localDeleteCount > 0) {
      final collectionFiles = (await _db.getFileIDToFileFromIDs(
        fileIDs,
      )).values.toList();
      collectionFiles.removeWhere((f) => f.collectionID != collectionID);
      Bus.instance.fire(
        CollectionUpdatedEvent(
          collectionID,
          collectionFiles,
          "syncDeleteFromRemote",
          type: EventType.deletedFromRemote,
        ),
      );
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          collectionFiles,
          type: EventType.deletedFromRemote,
          source: "syncDeleteFromRemote",
        ),
      );
    }
  }

  Future<void> syncDeviceCollectionFilesForUpload() async {
    _logger.info("Syncing device collections to be uploaded");
    final int ownerID = _config.getUserID()!;

    final deviceCollections = await _db.getDeviceCollections();
    deviceCollections.removeWhere((element) => !element.shouldBackup);
    // Sort by count to ensure that photos in iOS are first inserted in
    // smallest album marked for backup. This is to ensure that photo is
    // first attempted to upload in a non-recent album.
    deviceCollections.sort((a, b) => a.count.compareTo(b.count));
    final Map<String, Set<String>> pathIdToLocalIDs = await _db
        .getDevicePathIDToLocalIDMap();

    // Fetch all newer local IDs once if only-new backup is enabled
    final backNewPhotosOnly = backupPreferenceService.isOnlyNewBackupEnabled;

    late final Set<String> newerLocalIDs;
    if (backNewPhotosOnly) {
      final int onlyNewSince = backupPreferenceService.onlyNewSinceEpoch!;
      // Single DB query for all newer files
      newerLocalIDs = await _db.getAllLocalIDsNewerThan(onlyNewSince);
      _logger.info("Found ${newerLocalIDs.length} newer files");
    }

    bool moreFilesMarkedForBackup = false;
    for (final deviceCollection in deviceCollections) {
      final Set<String> localIDsToSync =
          pathIdToLocalIDs[deviceCollection.id]?.toSet() ?? {};
      if (deviceCollection.uploadStrategy == UploadStrategy.ifMissing) {
        final Set<String> alreadyClaimedLocalIDs = await _db
            .getLocalIDsMarkedForOrAlreadyUploaded(ownerID);
        localIDsToSync.removeAll(alreadyClaimedLocalIDs);
        if (alreadyClaimedLocalIDs.isNotEmpty && !_hasCleanupStaleEntry) {
          try {
            await _db.removeQueuedLocalFiles(alreadyClaimedLocalIDs, ownerID);
          } catch (e, s) {
            _logger.severe("removeQueuedLocalFiles failed", e, s);
          }
        }
      }

      // Filter by only-new using pre-fetched set
      if (backNewPhotosOnly) {
        // Keep only files that are in newerLocalIDs (removes old files)
        localIDsToSync.retainAll(newerLocalIDs);
      }

      if (localIDsToSync.isEmpty) {
        if (flagService.syncRecoveryDiagnostics) {
          _logger.info(
            "[${deviceCollection.name}] upload-prep empty: "
            "pathID=${deviceCollection.id} mappedFromPath=0",
          );
        }
        continue;
      }
      final collectionID = await _getCollectionID(deviceCollection);
      if (collectionID == null) {
        _logger.warning('DeviceCollection was either deleted or missing');
        continue;
      }

      moreFilesMarkedForBackup = true;
      await _db.setCollectionIDForUnMappedLocalFiles(
        collectionID,
        localIDsToSync,
      );

      // mark IDs as already synced if corresponding entry is present in
      // the collection. This can happen when a user has marked a folder
      // for sync, then un-synced it and again tries to mark if for sync.
      final Set<String> existingMapping = await _db
          .getLocalFileIDsForCollection(collectionID);
      final Set<String> commonElements = localIDsToSync.intersection(
        existingMapping,
      );
      if (commonElements.isNotEmpty) {
        debugPrint(
          "${commonElements.length} files already existing in "
          "collection $collectionID for ${deviceCollection.name}",
        );
        localIDsToSync.removeAll(commonElements);
      }

      // At this point, the remaining localIDsToSync will need to create
      // new file entries, where we can store mapping for localID and
      // corresponding collection ID
      if (localIDsToSync.isNotEmpty) {
        debugPrint(
          'Adding new entries for ${localIDsToSync.length} files'
          ' for ${deviceCollection.name}',
        );
        final filesWithCollectionID = await _db.getLocalFiles(
          localIDsToSync.toList(),
        );
        final List<EnteFile> newFilesToInsert = [];
        final Set<String> fileFoundForLocalIDs = {};
        for (var existingFile in filesWithCollectionID) {
          final String localID = existingFile.localID!;
          if (!fileFoundForLocalIDs.contains(localID)) {
            existingFile.generatedID = null;
            existingFile.collectionID = collectionID;
            existingFile.uploadedFileID = null;
            existingFile.ownerID = null;
            newFilesToInsert.add(existingFile);
            fileFoundForLocalIDs.add(localID);
          }
        }
        await _db.insertMultiple(newFilesToInsert);
        if (fileFoundForLocalIDs.length != localIDsToSync.length) {
          _logger.warning(
            "mismatch in num of filesToSync ${localIDsToSync.length} to "
            "fileSynced ${fileFoundForLocalIDs.length}",
          );
        }
        if (flagService.syncRecoveryDiagnostics) {
          final int mappedCount = localIDsToSync.length;
          final int postFilterCount = localIDsToSync.length;
          final int missingFileRows =
              postFilterCount - fileFoundForLocalIDs.length;
          if (missingFileRows > 0) {
            final sample = localIDsToSync
                .difference(fileFoundForLocalIDs)
                .take(3);
            _logger.warning(
              "[${deviceCollection.name}] upload-prep missing rows: "
              "pathID=${deviceCollection.id} "
              "mappedFromPath=$mappedCount "
              "postFilter=$postFilterCount "
              "missingFileRows=$missingFileRows "
              "collectionID=$collectionID "
              "sample=${sample.toList()}",
            );
          }
        }
      }
    }
    if (moreFilesMarkedForBackup &&
        !backupPreferenceService.hasSelectedAllFoldersForBackup) {
      // "force reload due to display new files"
      Bus.instance.fire(ForceReloadHomeGalleryEvent("newFilesDisplay"));
    }
    _hasCleanupStaleEntry = true;
  }

  Future<void> updateDeviceFolderSyncStatus(
    Map<String, bool> syncStatusUpdate,
  ) async {
    final Set<int> oldCollectionIDsForAutoSync = await _db
        .getDeviceSyncCollectionIDs();
    await _db.updateDevicePathSyncStatus(syncStatusUpdate);
    final Set<int> newCollectionIDsForAutoSync = await _db
        .getDeviceSyncCollectionIDs();
    SyncService.instance.onDeviceCollectionSet(newCollectionIDsForAutoSync);
    // remove all collectionIDs which are still marked for backup
    oldCollectionIDsForAutoSync.removeAll(newCollectionIDsForAutoSync);
    await removeFilesQueuedForUpload(oldCollectionIDsForAutoSync.toList());
    if (syncStatusUpdate.values.any((syncStatus) => syncStatus == false)) {
      backupPreferenceService.setSelectAllFoldersForBackup(false).ignore();
    }
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(<EnteFile>[], source: "deviceFolderSync"),
    );
    Bus.instance.fire(BackupFoldersUpdatedEvent());
  }

  Future<void> removeFilesQueuedForUpload(List<int> collectionIDs) async {
    /*
      For each collection, perform following action
      1) Get List of all files not uploaded yet
      2) Delete files who localIDs is also present in other collections.
      3) For Remaining files, set the collectionID as -1
     */
    _logger.info("Removing files for collections $collectionIDs");
    for (int collectionID in collectionIDs) {
      final List<EnteFile> pendingUploads = await _db
          .getPendingUploadForCollection(collectionID);
      if (pendingUploads.isEmpty) {
        continue;
      } else {
        _logger.info(
          "RemovingFiles $collectionIDs: pendingUploads "
          "${pendingUploads.length}",
        );
      }
      final Set<String> localIDsInOtherFileEntries = await _db
          .getLocalIDsPresentInEntries(pendingUploads, collectionID);
      _logger.info(
        "RemovingFiles $collectionIDs: filesInOtherCollection "
        "${localIDsInOtherFileEntries.length}",
      );
      final List<EnteFile> entriesToUpdate = [];
      final List<int> entriesToDelete = [];
      for (EnteFile pendingUpload in pendingUploads) {
        if (localIDsInOtherFileEntries.contains(pendingUpload.localID)) {
          entriesToDelete.add(pendingUpload.generatedID!);
        } else {
          pendingUpload.collectionID = null;
          entriesToUpdate.add(pendingUpload);
        }
      }
      await _db.deleteMultipleByGeneratedIDs(entriesToDelete);
      await _db.insertMultiple(entriesToUpdate);
      _logger.info(
        "RemovingFiles $collectionIDs: deleted "
        "${entriesToDelete.length} and updated ${entriesToUpdate.length}",
      );
    }
  }

  Future<int?> _getCollectionID(DeviceCollection deviceCollection) async {
    if (deviceCollection.hasCollectionID()) {
      final collection = _collectionsService.getCollectionByID(
        deviceCollection.collectionID!,
      );
      if (collection != null && !collection.isDeleted) {
        return collection.id;
      }
      if (collection == null) {
        // ideally, this should never happen because the app keeps a track of
        // all collections and their IDs. But, if somehow the collection is
        // deleted, we should fetch it again
        _logger.severe(
          "Collection ${deviceCollection.collectionID} missing "
          "for pathID ${deviceCollection.id}",
        );
        _collectionsService
            .fetchCollectionByID(deviceCollection.collectionID!)
            .ignore();
        // return, by next run collection should be available.
        // we are not waiting on fetch by choice because device might have wrong
        // mapping which will result in breaking upload for other device path
        return null;
      } else if (collection.isDeleted) {
        _logger.warning(
          "Collection ${deviceCollection.collectionID} deleted "
          "for pathID ${deviceCollection.id}, new collection will be created",
        );
      }
    }
    final collection = await _collectionsService.getOrCreateForPath(
      deviceCollection.name,
    );
    await _db.updateDeviceCollection(deviceCollection.id, collection.id);
    return collection.id;
  }

  Future<List<EnteFile>> _getFilesToBeUploaded() async {
    // Note: "only backup new photos" filtering is applied at the local sync
    // stage (see _syncDeviceCollectionFilesForUpload) where we filter by
    // localID before setting collectionID. Files that reach here with a
    // collectionID but no uploadedFileID either:
    // 1. Passed the only-new filter during auto-backup sync, OR
    // 2. Were manually added by the user to a collection
    // In case 2, we should NOT filter them out - user explicitly chose them.
    final List<EnteFile> originalFiles = await _db.getFilesPendingForUpload();
    if (originalFiles.isEmpty) {
      return originalFiles;
    }
    final bool shouldRemoveVideos =
        !backupSettings.shouldBackupVideos() || bgWithoutResumableUpload;
    final ignoredIDs = await IgnoredFilesService.instance.idToIgnoreReasonMap;
    bool shouldSkipUploadFunc(EnteFile file) {
      return IgnoredFilesService.instance.shouldSkipUpload(ignoredIDs, file);
    }

    final List<EnteFile> filesToBeUploaded = [];
    int ignoredForUpload = 0;
    int skippedVideos = 0;
    final whitelistedIDs =
        (_prefs.getStringList(_ignoreBackUpSettingsForIDs_) ?? <String>[])
            .toSet();
    for (var file in originalFiles) {
      if (shouldRemoveVideos &&
          (file.fileType == FileType.video &&
              !whitelistedIDs.contains(file.localID))) {
        skippedVideos++;
        continue;
      }
      if (shouldSkipUploadFunc(file)) {
        ignoredForUpload++;
        continue;
      }
      filesToBeUploaded.add(file);
    }
    if (skippedVideos > 0 || ignoredForUpload > 0) {
      _logger.info(
        "Skipped $skippedVideos videos and $ignoredForUpload "
        "ignored files for upload",
      );
    }
    _sortByTime(filesToBeUploaded);
    _logger.info("${filesToBeUploaded.length} new files to be uploaded.");
    return filesToBeUploaded;
  }

  Future<bool> _uploadFiles(List<EnteFile> filesToBeUploaded) async {
    final int ownerID = _config.getUserID()!;
    final updatedFileIDs = await _db.getUploadedFileIDsToBeUpdated(ownerID);
    if (updatedFileIDs.isNotEmpty) {
      _logger.info("Identified ${updatedFileIDs.length} files for reupload");
    }

    _completedUploads = 0;
    _ignoredUploads = 0;
    final int toBeUploaded = filesToBeUploaded.length + updatedFileIDs.length;

    if (toBeUploaded > 0) {
      Bus.instance.fire(
        SyncStatusUpdate(SyncStatus.preparingForUpload, total: toBeUploaded),
      );
      await _uploader.verifyMediaLocationAccess();
      await _uploader.checkNetworkForUpload();
      await _uploader.validateUploadEligibility();
    }
    final List<Future> futures = [];

    var uploadQueue = filesToBeUploaded;
    if (Platform.isIOS &&
        isProcessBg &&
        flagService.enableBgLocalUploadPriority) {
      uploadQueue = await _buildBgUploadQueue(filesToBeUploaded);
    }

    for (final file in uploadQueue) {
      if (shouldThrottleUpload &&
          futures.length >= kMaximumPermissibleUploadsInThrottledMode) {
        break;
      }
      // prefer existing collection ID for manually uploaded files.
      // See https://github.com/ente/photos-app/pull/187
      try {
        final collectionID =
            file.collectionID ??
            (await _collectionsService.getOrCreateForPath(
              file.deviceFolder ?? 'Unknown Folder',
            )).id;
        _uploadFile(file, collectionID, futures);
      } catch (_) {}
    }

    for (final uploadedFileID in updatedFileIDs) {
      if (shouldThrottleUpload &&
          futures.length >= kMaximumPermissibleUploadsInThrottledMode) {
        break;
      }
      try {
        final allFiles = await _db.getFilesInAllCollection(
          uploadedFileID,
          ownerID,
        );
        if (allFiles.isEmpty) {
          continue;
        }
        EnteFile? fileInCollectionOwnedByUser;
        for (final file in allFiles) {
          if (file.canReUpload(ownerID)) {
            fileInCollectionOwnedByUser = file;
            break;
          }
        }
        if (fileInCollectionOwnedByUser != null) {
          _uploadFile(
            fileInCollectionOwnedByUser,
            fileInCollectionOwnedByUser.collectionID!,
            futures,
          );
        }
      } catch (_) {}
    }

    try {
      await Future.wait(futures);
    } on InvalidFileError {
      // Do nothing
    } on FileSystemException {
      // Do nothing since it's caused mostly due to concurrency issues
      // when the foreground app deletes temporary files, interrupting a background
      // upload
    } on LockAlreadyAcquiredError {
      // Do nothing
    } on SilentlyCancelUploadsError {
      // Do nothing
    } on UserCancelledUploadError {
      // Do nothing
    }

    return _completedUploads > 0;
  }

  void _uploadFile(EnteFile file, int collectionID, List<Future> futures) {
    final future = _uploader
        .upload(file, collectionID)
        .then((uploadedFile) {
          return _onFileUploaded(uploadedFile);
        })
        .onError((error, stackTrace) {
          return _onFileUploadError(error, stackTrace, file);
        });
    futures.add(future);
  }

  Future<void> _onFileUploaded(EnteFile file) async {
    Bus.instance.fire(
      CollectionUpdatedEvent(file.collectionID, [file], "fileUpload"),
    );
    _completedUploads++;
    final toBeUploadedInThisSession = _uploader.getCurrentSessionUploadCount();
    if (toBeUploadedInThisSession == 0) {
      return;
    }
    if (_completedUploads > toBeUploadedInThisSession ||
        _completedUploads < 0 ||
        toBeUploadedInThisSession < 0) {
      _logger.info(
        "Incorrect sync status",
        InvalidSyncStatusError(
          "Tried to report $_completedUploads as "
          "uploaded out of $toBeUploadedInThisSession",
        ),
      );
      return;
    }
    Bus.instance.fire(
      SyncStatusUpdate(
        SyncStatus.inProgress,
        completed: _completedUploads,
        total: toBeUploadedInThisSession,
      ),
    );
  }

  void _onFileUploadError(Object? error, StackTrace stackTrace, EnteFile file) {
    if (error == null) {
      return;
    }
    if (error is InvalidFileError) {
      _ignoredUploads++;
      _logger.warning("Invalid file error", error);
    } else {
      throw error;
    }
  }

  /* _storeDiff maps each remoteFile to existing
      entries in files table. When match is found, it compares both file to
      perform relevant actions like
      [1] Clear local cache when required (Both Shared and Owned files)
      [2] Retain localID of remote file based on matching logic [Owned files]
      [3] Refresh UI if visibility or creationTime has changed [Owned files]
      [4] Schedule file update if the local file has changed since last time
      [Owned files]
    [Important Note: If given uploadedFileID and collectionID is already present
     in files db, the generateID should already point to existing entry.
     Known Issues:
      [K1] Cached entry will not be cleared when if a file was edited and
      moved to different collection as Vid/Image cache key is uploadedID.
      [Existing]
    ]
   */
  Future<void> _storeDiff(List<EnteFile> diff, int collectionID) async {
    int sharedFileNew = 0,
        sharedFileUpdated = 0,
        localUploadedFromDevice = 0,
        localButUpdatedOnDevice = 0,
        remoteNewFile = 0;
    final int userID = _config.getUserID()!;
    bool needsGalleryReload = false;
    // this is required when same file is uploaded twice in the same
    // collection. Without this check, if both remote files are part of same
    // diff response, then we end up inserting one entry instead of two
    // as we update the generatedID for remoteFile to local file's genID
    final Set<int> alreadyClaimedLocalFilesGenID = {};

    final List<EnteFile> toBeInserted = [];
    for (EnteFile remoteFile in diff) {
      // existingFile will be either set to existing collectionID+localID or
      // to the unclaimed aka not already linked to any uploaded file.
      EnteFile? existingFile;
      if (remoteFile.generatedID != null) {
        // Case [1] Check and clear local cache when uploadedFile already exist
        // Note: Existing file can be null here if it's replaced by the time we
        // reach here
        existingFile = await _db.getUploadedFile(
          remoteFile.uploadedFileID!,
          remoteFile.collectionID!,
        );
        if (existingFile != null &&
            _shouldClearCache(remoteFile, existingFile)) {
          needsGalleryReload = true;
          await clearCache(remoteFile);
        }
      }

      /* If file is not owned by the user, no further processing is required
      as Case [2,3,4] are only relevant to files owned by user
       */
      if (userID != remoteFile.ownerID) {
        if (existingFile == null) {
          sharedFileNew++;
          remoteFile.localID = null;
        } else {
          sharedFileUpdated++;
          // if user has downloaded the file on the device, avoid removing the
          // localID reference.
          // [Todo-fix: Excluded shared file's localIDs during syncALL]
          remoteFile.localID = existingFile.localID;
        }
        toBeInserted.add(remoteFile);
        // end processing for file here, move to next file now
        continue;
      }

      // If remoteFile was synced before, assign the localID of the existing
      // file entry.
      // If remoteFile is not synced before and has localID (i.e. existingFile
      // is null), check if the remoteFile was uploaded from this device.
      // Note: DeviceFolder is ignored for iOS during matching
      if (existingFile != null) {
        remoteFile.localID = existingFile.localID;
      } else if (remoteFile.localID != null && existingFile == null) {
        final localFileEntries = await _db.getUnlinkedLocalMatchesForRemoteFile(
          userID,
          remoteFile.localID!,
          remoteFile.fileType,
          title: remoteFile.title ?? '',
          deviceFolder: remoteFile.deviceFolder ?? '',
        );
        if (localFileEntries.isEmpty) {
          // set remote file's localID as null because corresponding local file
          // does not exist [Case 2, do not retain localID of the remote file]
          remoteFile.localID = null;
        } else {
          // case 4: Check and schedule the file for update
          final int maxModificationTime = localFileEntries
              .map((e) => e.modificationTime ?? 0)
              .reduce(max);

          /* Note: In case of iOS, we will miss any asset modification in
            between of two installation. This is done to avoid fetching assets
            from iCloud when modification time could have changed for number of
            reasons. To fix this, we need to identify a way to store version
            for the adjustments or just if the asset has been modified ever.
            https://stackoverflow.com/a/50093266/546896
            */
          if (maxModificationTime > remoteFile.modificationTime! &&
              Platform.isAndroid) {
            localButUpdatedOnDevice++;
            await FileUpdationDB.instance.insertMultiple([
              remoteFile.localID!,
            ], FileUpdationDB.modificationTimeUpdated);
          }

          localFileEntries.removeWhere(
            (e) =>
                e.uploadedFileID != null ||
                alreadyClaimedLocalFilesGenID.contains(e.generatedID),
          );

          if (localFileEntries.isNotEmpty) {
            // file uploaded from same device, replace the local file row by
            // setting the generated ID of remoteFile to localFile generatedID
            existingFile = localFileEntries.first;
            localUploadedFromDevice++;
            alreadyClaimedLocalFilesGenID.add(existingFile.generatedID!);
            remoteFile.generatedID = existingFile.generatedID;
          }
        }
      }
      if (existingFile != null &&
          _shouldReloadHomeGallery(remoteFile, existingFile)) {
        needsGalleryReload = true;
      } else {
        remoteNewFile++;
      }
      toBeInserted.add(remoteFile);
    }
    await _db.insertMultiple(toBeInserted);
    _logger.info(
      "Diff to be deduplicated was: " +
          diff.length.toString() +
          " out of which \n" +
          localUploadedFromDevice.toString() +
          " was uploaded from device, \n" +
          localButUpdatedOnDevice.toString() +
          " was uploaded from device, but has been updated since and should be reuploaded, \n" +
          sharedFileNew.toString() +
          " new sharedFiles, \n" +
          sharedFileUpdated.toString() +
          " updatedSharedFiles, and \n" +
          remoteNewFile.toString() +
          " remoteFiles seen first time",
    );
    if (needsGalleryReload) {
      // 'force reload home gallery'
      Bus.instance.fire(ForceReloadHomeGalleryEvent("remoteSync"));
    }
  }

  bool _shouldClearCache(EnteFile remoteFile, EnteFile existingFile) {
    if (remoteFile.hash != null && existingFile.hash != null) {
      return remoteFile.hash != existingFile.hash;
    }
    return remoteFile.updationTime != (existingFile.updationTime ?? 0);
  }

  bool _shouldReloadHomeGallery(EnteFile remoteFile, EnteFile existingFile) {
    int remoteCreationTime = remoteFile.creationTime!;
    if (remoteFile.pubMmdVersion > 0 &&
        (remoteFile.pubMagicMetadata?.editedTime ?? 0) != 0) {
      remoteCreationTime = remoteFile.pubMagicMetadata!.editedTime!;
    }
    if (remoteCreationTime != existingFile.creationTime) {
      return true;
    }
    if (existingFile.mMdVersion > 0 &&
        remoteFile.mMdVersion != existingFile.mMdVersion &&
        remoteFile.magicMetadata.visibility !=
            existingFile.magicMetadata.visibility) {
      return false;
    }
    return false;
  }

  // return true if the client needs to re-sync the collections from previous
  // version
  bool _shouldResetSyncTime() {
    return !_prefs.containsKey(kHasSyncedEditTime) ||
        !_prefs.containsKey(kHasSyncedArchiveKey);
  }

  Future<void> _markResetSyncTimeAsDone() async {
    await _prefs.setBool(kHasSyncedArchiveKey, true);
    await _prefs.setBool(kHasSyncedEditTime, true);
    // Check to avoid regression because of change or additions of keys
    if (_shouldResetSyncTime()) {
      throw Exception("_shouldResetSyncTime should return false now");
    }
  }

  int _getSinceTimeForReSync() {
    // re-sync from archive feature time if the client still hasn't synced
    // since the feature release.
    if (!_prefs.containsKey(kHasSyncedArchiveKey)) {
      return kArchiveFeatureReleaseTime;
    }
    return kEditTimeFeatureReleaseTime;
  }

  bool get shouldThrottleUpload {
    return !Platform.isAndroid && !AppLifecycleService.instance.isForeground;
  }

  bool get bgWithoutResumableUpload {
    // if multiple part is enabled, then we are not throttling uploads in bg
    return !(flagService.enableMobMultiPart &&
            localSettings.userEnabledMultiplePart) &&
        !AppLifecycleService.instance.isForeground;
  }

  // _sortByTime sort by creation time (desc).
  // This is done to upload most recent photo first.
  void _sortByTime(List<EnteFile> file) {
    file.sort((first, second) {
      // 1. fileType: move videos to end when in bg
      if (!AppLifecycleService.instance.isForeground &&
          first.fileType != second.fileType) {
        if (first.fileType == FileType.video) return 1;
        if (second.fileType == FileType.video) return -1;
      }

      // 2. creationTime descending
      return second.creationTime!.compareTo(first.creationTime!);
    });
  }

  /// Builds an upload queue for iOS background sync. For each upload slot,
  /// checks up to [kMaximumPermissibleUploadsInThrottledMode] candidates to
  /// find one that's locally available (not iCloud-only). If a local file is
  /// found, it's picked; otherwise the next file in line is used.
  /// Files already checked and found to be iCloud-only are tracked to avoid
  /// re-checking.
  Future<List<EnteFile>> _buildBgUploadQueue(List<EnteFile> files) async {
    const maxChecksPerSlot = kMaximumPermissibleUploadsInThrottledMode;
    const slots = kMaximumPermissibleUploadsInThrottledMode;
    final Set<int> picked = {};
    final Set<int> knownICloud = {};
    final List<EnteFile> queue = [];

    for (int slot = 0; slot < slots && picked.length < files.length; slot++) {
      int checks = 0;
      int? fallback;
      bool found = false;

      for (int i = 0; i < files.length; i++) {
        if (picked.contains(i)) continue;

        fallback ??= i;

        if (knownICloud.contains(i)) continue;

        if (checks >= maxChecksPerSlot) break;
        checks++;

        if (await _isOriginLocallyAvailable(files[i])) {
          queue.add(files[i]);
          picked.add(i);
          found = true;
          break;
        } else {
          knownICloud.add(i);
        }
      }

      if (!found && fallback != null) {
        queue.add(files[fallback]);
        picked.add(fallback);
      }
    }

    _logger.internalInfo(
      "Built bg upload queue: ${queue.length} files, "
      "${knownICloud.length} iCloud-only skipped",
    );
    return queue;
  }

  Future<bool> _isOriginLocallyAvailable(EnteFile file) async {
    try {
      if (file.localID == null) {
        return false;
      }
      return await _photoManagerPlugin.isLocallyAvailable(
        file.localID!,
        isOrigin: true,
        subtype: file.fileType == FileType.livePhoto
            ? (file.fileSubType ?? 0)
            : 0,
      );
    } catch (e, s) {
      _logger.warning(
        "Failed to determine local availability for ${file.tag}",
        e,
        s,
      );
      return false;
    }
  }

  bool _shouldShowSharedPhotosAndAlbumsNotification(int collectionID) {
    // TODO: Add option to opt out of notifications for a specific collection
    // Screen: https://www.figma.com/file/SYtMyLBs5SAOkTbfMMzhqt/ente-Visual-Design?type=design&node-id=7689-52943&t=IyWOfh0Gsb0p7yVC-4
    final isForeground = AppLifecycleService.instance.isForeground;
    final bool shouldShowSharedPhotosAndAlbumsNotification =
        NotificationService.instance
            .shouldShowNotificationsForSharedPhotosAndAlbums() &&
        isFirstRemoteSyncDone() &&
        !isForeground;
    _logger.info(
      "[Collection-$collectionID] shouldShow notification: "
      "$shouldShowSharedPhotosAndAlbumsNotification, "
      "isAppInForeground: $isForeground",
    );
    return shouldShowSharedPhotosAndAlbumsNotification;
  }

  Future<void> _notifyNewFiles(List<int> collectionIDs) async {
    final appOpenTime = AppLifecycleService.instance.getLastAppOpenTime();
    for (final collectionID in collectionIDs) {
      if (!_shouldShowSharedPhotosAndAlbumsNotification(collectionID)) {
        continue;
      }
      final files = await _db.getNewFilesInCollection(
        collectionID,
        appOpenTime,
      );
      final Set<int> collectedFileIDs = {};
      for (final file in files) {
        if (file.isUploaded && file.isCollect && file.uploadedFileID != null) {
          collectedFileIDs.add(file.uploadedFileID!);
        }
      }
      final totalCount = collectedFileIDs.length;
      if (totalCount > 0) {
        final collection = _collectionsService.getCollectionByID(collectionID);
        _logger.info(
          'creating notification for ${collection?.displayName} '
          'collected: $collectedFileIDs files',
        );
        final s = await LanguageService.locals;
        // ignore: unawaited_futures
        _showNotificationSafely(
          title: collection!.displayName,
          message: "$totalCount${s.newPhotosEmoji}",
          channelID: "collection:$collectionID",
          channelName: collection.displayName,
          payload: "ente://collection/?collectionID=$collectionID",
          context: 'collection=$collectionID',
        );
      }
    }
  }

  Future<void> _showNotificationSafely({
    required String title,
    required String message,
    int? id,
    required String channelID,
    required String channelName,
    required String payload,
    required String context,
  }) async {
    try {
      await NotificationService.instance.showNotification(
        title,
        message,
        channelID: channelID,
        channelName: channelName,
        payload: payload,
        id: id,
      );
    } catch (e, stackTrace) {
      _logger.severe("Failed to show notification ($context)", e, stackTrace);
    }
  }

  /// Syncs social data and triggers notifications if needed.
  Future<void> _socialSync() async {
    try {
      _logger.info("Starting social sync");
      await SocialSyncService.instance.syncAllSharedCollections();
      await SocialNotificationCoordinator.instance.notifyAfterSocialSync(
        trigger: SocialNotificationTrigger.remoteSync,
      );
    } catch (e) {
      _logger.severe("Social sync failed, continuing", e);
    }
  }
}
