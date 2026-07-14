import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/files_updated_event.dart';
import "package:photos/events/force_reload_trash_page_event.dart";
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/gateways/trash/models/trash_item_request.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/button_result.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/files_split.dart";
import "package:photos/models/freeable_space_info.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/module/download/file.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/files_service.dart";
import "package:photos/services/media_store_service.dart";
import "package:photos/services/sync/local_sync_service.dart";
import 'package:photos/services/sync/remote_sync_service.dart';
import 'package:photos/services/sync/sync_service.dart';
import "package:photos/settings/local_settings.dart";
import 'package:photos/ui/common/linear_progress_dialog.dart';
import 'package:photos/ui/components/buttons/button_widget.dart'
    show ButtonAction;
import 'package:photos/ui/notification/toast.dart';
import "package:photos/utils/device_info.dart";
import 'package:photos/utils/dialog_util.dart';

final _logger = Logger("DeleteFileUtil");

Future<void> deleteFilesFromEverywhere(
  BuildContext context,
  List<EnteFile> files,
) async {
  _logger.info("Trying to deleteFilesFromEverywhere " + files.toString());
  final List<String> localAssetIDs = [];
  final List<String> localSharedMediaIDs = [];
  final List<String> alreadyDeletedIDs = []; // to ignore already deleted files
  bool hasLocalOnlyFiles = false;
  for (final file in files) {
    if (file.localID != null) {
      if (!(await _localFileExist(file))) {
        _logger.warning("Already deleted " + file.toString());
        alreadyDeletedIDs.add(file.localID!);
      } else if (file.isSharedMediaToAppSandbox) {
        localSharedMediaIDs.add(file.localID!);
      } else {
        localAssetIDs.add(file.localID!);
      }
    }
    if (file.uploadedFileID == null) {
      hasLocalOnlyFiles = true;
    }
  }
  Set<String> deletedIDs = <String>{};
  try {
    deletedIDs = (await PhotoManager.editor.deleteWithIds(
      localAssetIDs,
    )).toSet();
  } catch (e, s) {
    _logger.severe("Could not delete file", e, s);
  }
  deletedIDs.addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));
  final updatedCollectionIDs = <int>{};
  final List<TrashRequest> uploadedFilesToBeTrashed = [];
  final List<EnteFile> deletedFiles = [];
  for (final file in files) {
    if (file.localID != null) {
      // Remove only those files that have already been removed from disk
      if (deletedIDs.contains(file.localID) ||
          alreadyDeletedIDs.contains(file.localID)) {
        deletedFiles.add(file);
        if (file.uploadedFileID != null) {
          uploadedFilesToBeTrashed.add(
            TrashRequest(file.uploadedFileID!, file.collectionID!),
          );
          updatedCollectionIDs.add(file.collectionID!);
        } else {
          await FilesDB.instance.deleteLocalFile(file);
        }
      }
    } else {
      updatedCollectionIDs.add(file.collectionID!);
      deletedFiles.add(file);
      uploadedFilesToBeTrashed.add(
        TrashRequest(file.uploadedFileID!, file.collectionID!),
      );
    }
  }
  if (uploadedFilesToBeTrashed.isNotEmpty) {
    try {
      final fileIDs = uploadedFilesToBeTrashed
          .map((item) => item.fileID)
          .toList();
      await trashSyncService.trashFilesOnServer(uploadedFilesToBeTrashed);
      await FilesDB.instance.deleteMultipleUploadedFiles(fileIDs);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
    for (final collectionID in updatedCollectionIDs) {
      Bus.instance.fire(
        CollectionUpdatedEvent(
          collectionID,
          deletedFiles
              .where((file) => file.collectionID == collectionID)
              .toList(),
          "deleteFilesEverywhere",
          type: EventType.deletedFromEverywhere,
        ),
      );
    }
  }
  if (deletedFiles.isNotEmpty) {
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(
        deletedFiles,
        type: EventType.deletedFromEverywhere,
        source: "deleteFilesEverywhere",
      ),
    );
    if (context.mounted) {
      if (hasLocalOnlyFiles && Platform.isAndroid) {
        showShortToast(context, AppLocalizations.of(context).filesDeleted);
      } else {
        showShortToast(context, AppLocalizations.of(context).movedToTrash);
      }
    }
  }
  if (uploadedFilesToBeTrashed.isNotEmpty) {
    // ignore: unawaited_futures
    RemoteSyncService.instance.sync(silently: true);
  }
}

Future<void> deleteFilesFromRemoteOnly(
  BuildContext context,
  List<EnteFile> files,
) async {
  final l10n = AppLocalizations.of(context);
  files.removeWhere((element) => element.uploadedFileID == null);
  if (files.isEmpty) {
    showToast(context, l10n.selectedFilesAreNotOnEnte);
    return;
  }
  _logger.info(
    "Trying to deleteFilesFromRemoteOnly " +
        files.map((f) => f.uploadedFileID).toString(),
  );
  final updatedCollectionIDs = <int>{};
  final List<int> uploadedFileIDs = [];
  final List<TrashRequest> trashRequests = [];
  for (final file in files) {
    updatedCollectionIDs.add(file.collectionID!);
    uploadedFileIDs.add(file.uploadedFileID!);
    trashRequests.add(TrashRequest(file.uploadedFileID!, file.collectionID!));
  }
  try {
    await trashSyncService.trashFilesOnServer(trashRequests);
    await FilesDB.instance.deleteMultipleUploadedFiles(uploadedFileIDs);
  } catch (e, s) {
    _logger.severe("Failed to delete files from remote", e, s);
    rethrow;
  }
  for (final collectionID in updatedCollectionIDs) {
    Bus.instance.fire(
      CollectionUpdatedEvent(
        collectionID,
        files.where((file) => file.collectionID == collectionID).toList(),
        "deleteFromRemoteOnly",
        type: EventType.deletedFromRemote,
      ),
    );
  }
  Bus.instance.fire(
    LocalPhotosUpdatedEvent(
      files,
      type: EventType.deletedFromRemote,
      source: "deleteFromRemoteOnly",
    ),
  );
  // ignore: unawaited_futures
  SyncService.instance.sync();
  // ignore: unawaited_futures
  RemoteSyncService.instance.sync(silently: true);
}

Future<List<EnteFile>> deleteFilesOnDeviceOnly(
  BuildContext context,
  List<EnteFile> files,
) async {
  _logger.info("Trying to deleteFilesOnDeviceOnly" + files.toString());
  final List<String> localAssetIDs = [];
  final List<String> localSharedMediaIDs = [];
  final List<String> alreadyDeletedIDs = []; // to ignore already deleted files
  final List<String?> localOnlyIDs = [];
  bool hasLocalOnlyFiles = false;
  for (final file in files) {
    if (file.localID != null) {
      if (!(await _localFileExist(file))) {
        _logger.warning("Already deleted " + file.toString());
        alreadyDeletedIDs.add(file.localID!);
      } else if (file.isSharedMediaToAppSandbox) {
        localSharedMediaIDs.add(file.localID!);
      } else {
        localAssetIDs.add(file.localID!);
      }
    }
    if (file.uploadedFileID == null) {
      hasLocalOnlyFiles = true;
      localOnlyIDs.add(file.localID);
    }
  }
  Set<String> deletedIDs = <String>{};
  try {
    deletedIDs = (await PhotoManager.editor.deleteWithIds(
      localAssetIDs,
    )).toSet();
  } catch (e, s) {
    _logger.severe("Could not delete file", e, s);
  }
  deletedIDs.addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));
  final List<EnteFile> deletedFiles = [];
  for (final file in files) {
    // Remove only those files that have been removed from disk
    if (deletedIDs.contains(file.localID) ||
        alreadyDeletedIDs.contains(file.localID)) {
      deletedFiles.add(file);
      if (hasLocalOnlyFiles && localOnlyIDs.contains(file.localID)) {
        await FilesDB.instance.deleteLocalFile(file);
      } else {
        file.localID = null;
        await FilesDB.instance.update(file);
      }
    }
  }
  if (deletedFiles.isNotEmpty || alreadyDeletedIDs.isNotEmpty) {
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(
        deletedFiles,
        type: EventType.deletedFromDevice,
        source: "deleteFilesOnDeviceOnly",
      ),
    );
  }
  return deletedFiles;
}

Future<bool> deleteFromTrash(BuildContext context, List<EnteFile> files) async {
  bool didDeletionStart = false;
  final l10n = AppLocalizations.of(context);
  final actionResult = await showBottomSheetComponent<ButtonResult>(
    context: context,
    useRootNavigator: Platform.isIOS,
    builder: (sheetContext) => BottomSheetComponent(
      title: l10n.areYouSure,
      message: l10n.selectedItemsWillBePermanentlyDeletedAndCannotBeRecovered,
      illustration: Image.asset("assets/warning-grey.png"),
      closeTooltip: l10n.close,
      closeResult: ButtonResult(ButtonAction.fourth),
      actions: [
        ButtonComponent(
          label: l10n.yesDelete,
          variant: ButtonComponentVariant.critical,
          onTap: () => _runDeleteAction(
            sheetContext,
            ButtonAction.first,
            () async {
              try {
                didDeletionStart = true;
                await trashSyncService.deleteFromTrash(files);
                Bus.instance.fire(
                  FilesUpdatedEvent(
                    files,
                    type: EventType.deletedFromEverywhere,
                    source: "deleteFromTrash",
                  ),
                );
                //the FilesUpdateEvent is not reloading trash on premanently removing
                //files, so need to fire ForceReloadTrashPageEvent
                Bus.instance.fire(ForceReloadTrashPageEvent());
              } catch (e, s) {
                _logger.info("failed to delete from trash", e, s);
                rethrow;
              }
            },
          ),
        ),
      ],
    ),
  );

  if (actionResult?.action == null ||
      actionResult!.action == ButtonAction.cancel ||
      actionResult.action == ButtonAction.fourth) {
    return didDeletionStart ? true : false;
  } else if (actionResult.action == ButtonAction.error) {
    if (!context.mounted) return false;
    await showGenericErrorDialog(
      context: context,
      error: actionResult.exception,
    );
    return false;
  } else {
    return true;
  }
}

Future<bool> emptyTrash(BuildContext context) async {
  final actionResult = await showChoiceActionSheet(
    context,
    title: AppLocalizations.of(context).emptyTrash,
    body: AppLocalizations.of(context).permDeleteWarning,
    firstButtonLabel: AppLocalizations.of(context).empty,
    isCritical: true,
    firstButtonOnTap: () async {
      try {
        await trashSyncService.emptyTrash();
      } catch (e, s) {
        _logger.info("failed empty trash", e, s);
        rethrow;
      }
    },
  );
  if (actionResult?.action == null ||
      actionResult!.action == ButtonAction.cancel) {
    return false;
  } else if (actionResult.action == ButtonAction.error) {
    if (!context.mounted) return false;
    await showGenericErrorDialog(
      context: context,
      error: actionResult.exception,
    );
    return false;
  } else {
    return true;
  }
}

Future<bool> deleteLocalFiles(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info("Trying to delete local files ");
  final List<String> deletedIDs = [];
  final List<String> localAssetIDs = [];
  final List<String> localSharedMediaIDs = [];

  // Keep large platform asset deletes in smaller batches. Shared-media sandbox
  // IDs are deleted separately above, and only platform asset IDs are sent to
  // PhotoManager.editor.deleteWithIds. Android 11+ routes those IDs through
  // MediaStore.createDeleteRequest, where our target SDK has a 2000 URI cap:
  // https://developer.android.com/reference/android/provider/MediaStore#createDeleteRequest(android.content.ContentResolver,%20java.util.Collection%3Candroid.net.Uri%3E)
  // Smaller batches are also safer for large iOS Photos deletes.
  const largeCountThreshold = 1900;
  try {
    for (String id in localIDs) {
      if (id.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(id);
      } else {
        localAssetIDs.add(id);
      }
    }
    deletedIDs.addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));

    final tooManyAssets = localAssetIDs.length > largeCountThreshold;
    final bool shouldDeleteInBatches =
        await isAndroidSDKVersionLowerThan(android11SDKINT) || tooManyAssets;
    if (!context.mounted) {
      _logger.info(
        "Skipping platform asset deletion after the initiating page was disposed",
      );
    } else if (shouldDeleteInBatches) {
      if (tooManyAssets) {
        _logger.info(
          "Too many assets (${localAssetIDs.length}) to delete in one shot, deleting in batches",
        );
        await _recursivelyReduceBatchSizeAndRetryDeletion(
          batchSize: largeCountThreshold,
          context: context,
          localIDs: localAssetIDs,
          deletedIDs: deletedIDs,
        );
      } else {
        _logger.info("Deleting in batches");
        deletedIDs.addAll(
          await deleteLocalFilesInBatches(context, localAssetIDs),
        );
      }
    } else {
      _logger.info("Deleting in one shot");
      deletedIDs.addAll(
        await _deleteLocalFilesInOneShot(context, localAssetIDs),
      );
    }
    if (deletedIDs.isEmpty && Platform.isIOS) {
      _logger.warning(
        "Deletion failed in deleteLocalFiles for ${localAssetIDs.length} files, on iOS",
      );
    }

    if (deletedIDs.isNotEmpty) {
      final deletedFiles = await FilesDB.instance.getLocalFiles(deletedIDs);
      await FilesDB.instance.deleteLocalFiles(deletedIDs);
      _logger.info(deletedFiles.length.toString() + " files deleted locally");
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(deletedFiles, source: "deleteLocal"),
      );
      return true;
    } else {
      //On android 10, even if files were deleted, deletedIDs is empty.
      //This is a workaround so that users are not shown an error message on
      //android 10
      if (!await isAndroidSDKVersionLowerThan(android11SDKINT)) {
        return false;
      }
      return true;
    }
  } catch (e, s) {
    _logger.severe("Could not delete local files", e, s);
    return false;
  }
}

Future<bool> deleteLocalFilesAfterRemovingAlreadyDeletedIDs(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info(
    "Trying to delete local files after removing already deleted IDs",
  );

  final List<String> deletedIDs = [];
  final List<String> localAssetIDs = [];
  final List<String> localSharedMediaIDs = [];
  final List<String> alreadyDeletedIDs = []; // to ignore already deleted files

  final dialog = createProgressDialog(context, "Loading...");
  await dialog.show();
  try {
    final files = await FilesDB.instance.getLocalFiles(
      localIDs,
      dedupeByLocalID: true,
    );
    for (final file in files) {
      if (!(await _localFileExist(file))) {
        _logger.warning("Already deleted ${file.tag}");
        alreadyDeletedIDs.add(file.localID!);
      } else if (file.localID!.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(file.localID!);
      } else {
        localAssetIDs.add(file.localID!);
      }
    }
    deletedIDs.addAll(alreadyDeletedIDs);
    deletedIDs.addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));

    await dialog.hide();

    final bool shouldDeleteInBatches = await isAndroidSDKVersionLowerThan(
      android11SDKINT,
    );
    if (!context.mounted) {
      _logger.info(
        "Skipping platform asset deletion after the initiating page was disposed",
      );
    } else if (shouldDeleteInBatches) {
      _logger.info("Deleting in batches");
      deletedIDs.addAll(
        await deleteLocalFilesInBatches(context, localAssetIDs),
      );
    } else {
      _logger.info("Deleting in one shot");
      deletedIDs.addAll(
        await _deleteLocalFilesInOneShot(context, localAssetIDs),
      );
    }

    if (deletedIDs.isEmpty && Platform.isIOS) {
      _logger.warning(
        "Deletion failed in deleteLocalFilesAfterRemovingAlreadyDeletedIDs for ${localAssetIDs.length} files, on iOS",
      );
    }

    if (deletedIDs.isNotEmpty) {
      final deletedFiles = await FilesDB.instance.getLocalFiles(deletedIDs);
      await FilesDB.instance.deleteLocalFiles(deletedIDs);
      _logger.info(deletedFiles.length.toString() + " files deleted locally");
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(deletedFiles, source: "deleteLocal"),
      );
      return true;
    } else {
      //On android 10, even if files were deleted, deletedIDs is empty.
      //This is a workaround so that users are not shown an error message on
      //android 10
      if (!await isAndroidSDKVersionLowerThan(android11SDKINT)) {
        return false;
      }
      return true;
    }
  } catch (e, s) {
    _logger.severe("Could not delete local files", e, s);
    await dialog.hide();
    return false;
  }
}

/// Only to be used on Android
Future<bool> retryFreeUpSpaceAfterRemovingAssetsNonExistingInDisk(
  BuildContext context,
) async {
  _logger.info(
    "Retrying free up space after removing assets non-existing in disk",
  );

  final dialog = createProgressDialog(
    context,
    context.l10n.pleaseWaitThisWillTakeAWhile,
  );
  await dialog.show();
  try {
    final stopwatch = Stopwatch()..start();
    final res = await PhotoManager.editor.android.removeAllNoExistsAsset();
    if (res == false) {
      _logger.warning("Failed to remove non-existing assets");
    }
    _logger.info(
      "removeAllNoExistsAsset took: ${stopwatch.elapsedMilliseconds}ms",
    );
    await LocalSyncService.instance.sync();

    late final FreeableSpaceInfo status;
    final List<String> deletedIDs = [];
    final List<String> localAssetIDs = [];
    final List<String> localSharedMediaIDs = [];
    status = await FilesService.instance.getFreeableSpaceInfo();

    for (String localID in status.localIDs) {
      if (localID.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(localID);
      } else {
        localAssetIDs.add(localID);
      }
    }
    deletedIDs.addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));

    await dialog.hide();

    final bool shouldDeleteInBatches = await isAndroidSDKVersionLowerThan(
      android11SDKINT,
    );
    if (!context.mounted) {
      _logger.info(
        "Skipping platform asset deletion after the initiating page was disposed",
      );
    } else if (shouldDeleteInBatches) {
      _logger.info("Deleting in batches");
      deletedIDs.addAll(
        await deleteLocalFilesInBatches(context, localAssetIDs),
      );
    } else {
      _logger.info("Deleting in one shot");
      deletedIDs.addAll(
        await _deleteLocalFilesInOneShot(context, localAssetIDs),
      );
    }

    if (deletedIDs.isNotEmpty) {
      final deletedFiles = await FilesDB.instance.getLocalFiles(deletedIDs);
      await FilesDB.instance.deleteLocalFiles(deletedIDs);
      _logger.info(deletedFiles.length.toString() + " files deleted locally");
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(deletedFiles, source: "deleteLocal"),
      );
      return true;
    } else {
      //On android 10, even if files were deleted, deletedIDs is empty.
      //This is a workaround so that users are not shown an error message on
      //android 10
      if (!await isAndroidSDKVersionLowerThan(android11SDKINT)) {
        return false;
      }
      return true;
    }
  } catch (e) {
    await dialog.hide();
    return false;
  }
}

Future<List<String>> _deleteLocalFilesInOneShot(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info('starting _deleteLocalFilesInOneShot for ${localIDs.length}');
  final List<String> deletedIDs = [];
  final dialog = createProgressDialog(
    context,
    "Deleting " + localIDs.length.toString() + " backed up files...",
  );
  await dialog.show();
  try {
    deletedIDs.addAll(await PhotoManager.editor.deleteWithIds(localIDs));
  } catch (e, s) {
    _logger.severe("Could not delete files ", e, s);
  }
  _logger.info(
    '_deleteLocalFilesInOneShot deleted ${deletedIDs.length} out '
    'of ${localIDs.length}',
  );
  await dialog.hide();
  return deletedIDs;
}

Future<List<String>> deleteLocalFilesInBatches(
  BuildContext context,
  List<String> localIDs, {
  int minimumParts = 10,
  int minimumBatchSize = 1,
  int maximumBatchSize = 100,
}) async {
  final dialogKey = GlobalKey<LinearProgressDialogState>();
  final dialog = LinearProgressDialog(
    "Deleting " + localIDs.length.toString() + " backed up files...",
    key: dialogKey,
  );
  // ignore: unawaited_futures
  showDialog(
    useRootNavigator: false,
    context: context,
    builder: (context) {
      return dialog;
    },
    barrierColor: Colors.black.withValues(alpha: 0.85),
  );
  final batchSize = min(
    max(minimumBatchSize, (localIDs.length / minimumParts).round()),
    maximumBatchSize,
  );
  _logger.info("Batch size: $batchSize");
  final List<String> deletedIDs = [];
  for (int index = 0; index < localIDs.length; index += batchSize) {
    if (dialogKey.currentState != null) {
      dialogKey.currentState!.setProgress(index / localIDs.length);
    }
    final ids = localIDs
        .getRange(index, min(localIDs.length, index + batchSize))
        .toList();
    _logger.info("Trying to delete ${ids.length} files");
    final int countBefore = deletedIDs.length;
    try {
      deletedIDs.addAll(await PhotoManager.editor.deleteWithIds(ids));
      _logger.info(
        "Deleted ${deletedIDs.length - countBefore} of ${ids.length} files",
      );
    } catch (e, s) {
      _logger.severe("Could not delete batch of ${ids.length} files", e, s);
      for (final id in ids) {
        try {
          deletedIDs.addAll(await PhotoManager.editor.deleteWithIds([id]));
          _logger.info("Deleted " + id);
        } catch (e, s) {
          _logger.severe("Could not delete file " + id, e, s);
        }
      }
    }
  }
  Navigator.of(dialogKey.currentContext!).pop('dialog');
  return deletedIDs;
}

Future<void> _recursivelyReduceBatchSizeAndRetryDeletion({
  required int batchSize,
  required BuildContext context,
  required List<String> localIDs,
  required List<String> deletedIDs,
  int minimumBatchSizeThresholdToStopRetry = 1900,
}) async {
  // TODO: Revisit whether this recursive retry is still needed. The batch
  // helper already falls back to single-ID deletes when a batch fails.
  if (batchSize < minimumBatchSizeThresholdToStopRetry) {
    _logger.warning(
      "Batch size is too small ($batchSize), stopping further retries.",
    );
    throw Exception(
      "Batch size is too small ($batchSize), stopping further retries.",
    );
  }
  try {
    deletedIDs.addAll(
      await deleteLocalFilesInBatches(
        context,
        localIDs,
        minimumBatchSize: 1,
        maximumBatchSize: batchSize,
        minimumParts: 1,
      ),
    );
  } catch (e) {
    _logger.warning(
      "Failed to delete local files in batches of $batchSize. Reducing batch size and retrying.",
      e,
    );
    if (!context.mounted) return;
    await _recursivelyReduceBatchSizeAndRetryDeletion(
      batchSize: (batchSize / 2).floor(),
      context: context,
      localIDs: localIDs,
      deletedIDs: deletedIDs,
    );
  }
}

Future<bool> _localFileExist(EnteFile file) {
  if (file.isSharedMediaToAppSandbox) {
    final localFile = File(getSharedMediaFilePath(file));
    return localFile.exists();
  } else {
    return file.getAsset.then((asset) {
      if (asset == null) {
        return false;
      }
      return asset.exists;
    });
  }
}

Future<List<String>> _tryDeleteSharedMediaFiles(List<String> localIDs) {
  final List<String> actuallyDeletedIDs = [];
  try {
    return Future.forEach<String>(localIDs, (id) async {
      final String localPath = getSharedMediaPathFromLocalID(id);
      try {
        // verify the file exists as the OS may have already deleted it from cache
        if (File(localPath).existsSync()) {
          await File(localPath).delete();
        }
        actuallyDeletedIDs.add(id);
      } catch (e, s) {
        _logger.warning("Could not delete file " + id, e, s);
        // server log shouldn't contain localId
        _logger.severe("Could not delete file ", e, s);
      }
    }).then((ignore) {
      return actuallyDeletedIDs;
    });
  } catch (e, s) {
    _logger.severe("Unexpected error while deleting share media files", e, s);
    return Future.value(actuallyDeletedIDs);
  }
}

Future<void> showMediaManagementHintSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  if (!Platform.isAndroid) {
    return;
  }
  if (!await MediaStoreService.isMediaManagementSupported()) {
    return;
  }
  if (await MediaStoreService.canManageMedia()) {
    return;
  }
  if (localSettings.isMediaManagementHintDismissed) {
    return;
  }
  await localSettings.incrementMediaManagementHintDeleteAttempts();
  if (!localSettings.hasMediaManagementHintDeleteAttemptsReached()) {
    return;
  }
  if (!context.mounted) return;
  final shouldDismissHint = await showBottomSheetComponent<bool>(
    context: context,
    useRootNavigator: Platform.isIOS,
    builder: (sheetContext) => BottomSheetComponent(
      title: l10n.mediaManagementHintTitle,
      message: l10n.mediaManagementHintMessage,
      illustration: Image.asset("assets/ducky_smart_feature.png"),
      closeTooltip: l10n.close,
      closeResult: true,
      actions: [
        ButtonComponent(
          label: l10n.openSettings,
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            await MediaStoreService.openManageMediaSettings();
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop(false);
            }
          },
        ),
        ButtonComponent(
          label: l10n.skip,
          variant: ButtonComponentVariant.secondary,
          shouldSurfaceExecutionStates: false,
          onTap: () {
            Navigator.of(sheetContext).pop(true);
          },
        ),
      ],
    ),
  );
  if (shouldDismissHint == true) {
    await localSettings.resetMediaManagementHintDeleteAttempts();
    await localSettings.setMediaManagementHintDismissed();
  }
}

Future<void> showDeleteSheet(
  BuildContext context,
  SelectedFiles selectedFiles,
  FilesSplit filesSplit, {
  @visibleForTesting
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteFromRemoteOnlyOverride,
  @visibleForTesting
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteOnDeviceOnlyOverride,
  @visibleForTesting
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteFromEverywhereOverride,
}) async {
  final l10n = AppLocalizations.of(context);
  if (selectedFiles.files.length != filesSplit.count) {
    throw AssertionError(
      "Unexpected state, #{selectedFiles.files.length} != "
      "${filesSplit.count}",
    );
  }
  final List<EnteFile> deletableFiles =
      filesSplit.ownedByCurrentUser + filesSplit.pendingUploads;
  final Future<void> Function(BuildContext context, List<EnteFile> files)
  deleteFromRemoteOnlyAction =
      deleteFromRemoteOnlyOverride ?? deleteFilesFromRemoteOnly;
  final Future<void> Function(BuildContext context, List<EnteFile> files)
  deleteOnDeviceOnlyAction =
      deleteOnDeviceOnlyOverride ??
      (context, files) async => deleteFilesOnDeviceOnly(context, files);
  final Future<void> Function(BuildContext context, List<EnteFile> files)
  deleteFromEverywhereAction =
      deleteFromEverywhereOverride ?? deleteFilesFromEverywhere;

  if (deletableFiles.isEmpty && filesSplit.ownedByOtherUsers.isNotEmpty) {
    showShortToast(context, l10n.cannotDeleteSharedFiles);
    return;
  }
  if (isLocalGalleryMode) {
    final localGalleryDeletableFiles = deletableFiles
        .where((file) => file.localID != null)
        .toList();
    if (localGalleryDeletableFiles.isEmpty) {
      showShortToast(context, l10n.noDeviceThatCanBeDeleted);
      return;
    }
    var didDelete = false;
    if (Platform.isAndroid && await MediaStoreService.canManageMedia()) {
      if (!context.mounted) return;
      didDelete =
          await showBottomSheetComponent<bool>(
            context: context,
            useRootNavigator: Platform.isIOS,
            builder: (_) => DeleteConfirmationSheet(
              count: localGalleryDeletableFiles.length,
              isLocal: true,
              isRemote: false,
              onDeleteFromLocal: () async {
                await deleteOnDeviceOnlyAction(
                  context,
                  localGalleryDeletableFiles,
                );
              },
              onDeleteFromRemote: () async {
                throw AssertionError(
                  "delete from remote in local gallery mode",
                );
              },
              onDeleteFromBoth: () async {
                throw AssertionError("delete from both in local gallery mode");
              },
            ),
          ) ==
          true;
    } else {
      if (!context.mounted) return;
      await deleteOnDeviceOnlyAction(context, localGalleryDeletableFiles);
      didDelete = true;
    }
    if (!didDelete) {
      return;
    }
    selectedFiles.unSelectAll(localGalleryDeletableFiles.toSet());
    if (!context.mounted) return;
    await showMediaManagementHintSheet(context);
    return;
  }
  final hasRemoteFiles = deletableFiles.any((f) => f.isUploaded);
  final hasLocalFiles = deletableFiles.any((f) => f.localID != null);

  final bool isBothLocalAndRemote = hasRemoteFiles && hasLocalFiles;
  final bool isLocalOnly = !hasRemoteFiles;
  final bool isRemoteOnly = !hasLocalFiles;
  if (!isBothLocalAndRemote && !isRemoteOnly && !isLocalOnly) {
    throw AssertionError("Unexpected state");
  }

  Future<void> deleteFromEnte() async {
    await deleteFromRemoteOnlyAction(context, deletableFiles);
    if (!context.mounted) return;
    showShortToast(context, l10n.movedToTrash);
  }

  var didDeleteLocalFiles = false;
  final actionResult = await showBottomSheetComponent<bool>(
    context: context,
    useRootNavigator: Platform.isIOS,
    builder: (_) => DeleteConfirmationSheet(
      isLocal: hasLocalFiles,
      isRemote: hasRemoteFiles,
      count: deletableFiles.length,
      onDeleteFromLocal: () async {
        await deleteOnDeviceOnlyAction(context, deletableFiles);
        didDeleteLocalFiles = true;
      },
      onDeleteFromRemote: () async {
        await deleteFromEnte();
      },
      onDeleteFromBoth: () async {
        await deleteFromEverywhereAction(context, deletableFiles);
        didDeleteLocalFiles = true;
      },
    ),
  );
  if (actionResult == true) {
    selectedFiles.clearAll();
    if (didDeleteLocalFiles) {
      if (!context.mounted) return;
      await showMediaManagementHintSheet(context);
    }
  }
}

Future<void> _runDeleteAction(
  BuildContext context,
  ButtonAction action,
  Future<void> Function() onDelete,
) async {
  try {
    await onDelete();
    if (!context.mounted) return;
    Navigator.of(context).pop(ButtonResult(action));
  } catch (error) {
    if (context.mounted) {
      Navigator.of(
        context,
      ).pop(ButtonResult(ButtonAction.error, _toException(error)));
    }
    rethrow;
  }
}

Exception _toException(Object error) {
  return error is Exception ? error : Exception(error.toString());
}

class _MoreOptionsButton extends StatefulWidget {
  const _MoreOptionsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_MoreOptionsButton> createState() => _MoreOptionsButtonState();
}

// TODO: Replace this component once ente_components has a ghost button variant.
class _MoreOptionsButtonState extends State<_MoreOptionsButton> {
  var _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final foreground = context.componentColors.textLight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.moreOptions,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyles.body.copyWith(color: foreground),
            ),
            const SizedBox(width: Spacing.xs),
            Icon(
              Icons.keyboard_arrow_up,
              color: foreground,
              size: IconSizes.small,
            ),
          ],
        ),
      ),
    );
  }
}

class DeleteConfirmationSheet extends StatefulWidget {
  final bool isLocal;
  final bool isRemote;
  final int count;
  final Future<void> Function() onDeleteFromLocal;
  final Future<void> Function() onDeleteFromRemote;
  final Future<void> Function() onDeleteFromBoth;

  const DeleteConfirmationSheet({
    super.key,
    required this.isLocal,
    required this.isRemote,
    required this.count,
    required this.onDeleteFromLocal,
    required this.onDeleteFromRemote,
    required this.onDeleteFromBoth,
  });

  @override
  State<StatefulWidget> createState() {
    return DeleteConfirmationSheetState();
  }
}

class DeleteConfirmationSheetState extends State<DeleteConfirmationSheet> {
  var _isMoreOptionsShown = false;
  var _isSetAsDefaultSelected = false;

  @override
  void initState() {
    super.initState();
    // Always display the more options if the user hasn't set a preference yet.
    if (localSettings.getDeletePreference() == null) {
      _isMoreOptionsShown = true;
    }
  }

  Future<void> _onDelete(
    BuildContext context,
    Future<void> Function() callback,
  ) async {
    try {
      await callback();
      if (context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (context.mounted) {
        await showGenericErrorDialog(
          context: context,
          error: _toException(error),
        );
        if (context.mounted) {
          Navigator.of(context).pop(false);
        }
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.deleteItemsQuestion(count: widget.count);
    var body = l10n.selectedFilesSavedOnDeviceOnly;
    if (widget.count == 1 && widget.isLocal && widget.isRemote) {
      body = l10n.singleFileInBothLocalAndRemote;
    } else if (widget.count == 1 && widget.isRemote) {
      body = l10n.singleFileInRemoteOnly;
    } else if (widget.count == 1 && widget.isLocal) {
      body = l10n.singleFileDeleteFromDevice;
    } else if (widget.isLocal && widget.isRemote) {
      body = l10n.someSelectedFilesBackedUpToEnte;
    } else if (widget.isRemote) {
      body = l10n.selectedFilesBackedUpToEnte;
    }
    var deletePreference = DeletePreference.DeleteFromBoth;
    if (widget.isLocal && !widget.isRemote) {
      deletePreference = DeletePreference.DeleteFromLocalOnly;
    } else if (widget.isRemote && !widget.isLocal) {
      deletePreference = DeletePreference.DeleteFromRemoteOnly;
    } else {
      deletePreference =
          localSettings.getDeletePreference() ??
          DeletePreference.DeleteFromBoth;
    }

    return BottomSheetComponent(
      title: title,
      illustration: Image.asset("assets/warning-red.png"),
      closeTooltip: l10n.close,
      content: Text(
        body,
        textAlign: TextAlign.center,
        style: TextStyles.body.copyWith(
          color: context.componentColors.textLight,
        ),
      ),
      actions: [
        // Expanded target choices
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [...previousChildren, ?currentChild],
              );
            },
            child: (widget.isLocal && widget.isRemote && _isMoreOptionsShown)
                ? Column(
                    spacing: Spacing.md,
                    children: [
                      ButtonComponent(
                        label: l10n.deleteFromDevice,
                        variant: ButtonComponentVariant.secondary,
                        onTap: () async {
                          if (_isSetAsDefaultSelected) {
                            await localSettings.setDeletePreference(
                              .DeleteFromLocalOnly,
                            );
                          }
                          if (!context.mounted) return;
                          await _onDelete(context, widget.onDeleteFromLocal);
                        },
                      ),
                      ButtonComponent(
                        label: l10n.deleteFromEnte,
                        variant: ButtonComponentVariant.secondary,
                        onTap: () async {
                          if (_isSetAsDefaultSelected) {
                            await localSettings.setDeletePreference(
                              .DeleteFromRemoteOnly,
                            );
                          }
                          if (!context.mounted) return;
                          await _onDelete(context, widget.onDeleteFromRemote);
                        },
                      ),
                      ButtonComponent(
                        label: l10n.deleteFromBoth,
                        variant: ButtonComponentVariant.critical,
                        onTap: () async {
                          if (_isSetAsDefaultSelected) {
                            await localSettings.setDeletePreference(
                              .DeleteFromBoth,
                            );
                          }
                          if (!context.mounted) return;
                          await _onDelete(context, widget.onDeleteFromBoth);
                        },
                      ),
                    ],
                  )
                :
                  // Preferred target shortcut
                  ButtonComponent(
                    label: switch (deletePreference) {
                      DeletePreference.DeleteFromRemoteOnly =>
                        l10n.deleteFromEnte,
                      DeletePreference.DeleteFromLocalOnly =>
                        l10n.deleteFromDevice,
                      DeletePreference.DeleteFromBoth => l10n.deleteFromBoth,
                    },
                    variant: ButtonComponentVariant.critical,
                    onTap: () async {
                      switch (deletePreference) {
                        case DeletePreference.DeleteFromRemoteOnly:
                          await _onDelete(context, widget.onDeleteFromRemote);
                        case DeletePreference.DeleteFromLocalOnly:
                          await _onDelete(context, widget.onDeleteFromLocal);
                        case DeletePreference.DeleteFromBoth:
                          await _onDelete(context, widget.onDeleteFromBoth);
                      }
                    },
                  ),
          ),
        ),
        // Preference control
        if (widget.isLocal && widget.isRemote)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: _isMoreOptionsShown
                ? Center(
                    child: LabeledControlComponent(
                      control: CheckboxComponent(
                        selected: _isSetAsDefaultSelected,
                        onChanged: (value) {
                          setState(() {
                            _isSetAsDefaultSelected = value;
                          });
                        },
                      ),
                      label: l10n.setAsMyDefaultChoice,
                      foreground: context.componentColors.textLight,
                      onTap: () {
                        setState(() {
                          _isSetAsDefaultSelected = !_isSetAsDefaultSelected;
                        });
                      },
                    ),
                  )
                : _MoreOptionsButton(
                    onTap: () {
                      setState(() {
                        _isMoreOptionsShown = true;
                      });
                    },
                  ),
          ),
      ],
    );
  }
}
