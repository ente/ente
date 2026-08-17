import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ente_components/ente_components.dart';
import "package:ente_strings/ente_strings.dart";
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
import "package:photos/models/button_result.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/trash_file.dart";
import "package:photos/models/files_split.dart";
import "package:photos/models/freeable_space_info.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/module/download/file.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/files_service.dart";
import "package:photos/services/free_space/deletion_batch_runner.dart";
import "package:photos/services/sync/local_sync_service.dart";
import 'package:photos/services/sync/remote_sync_service.dart';
import 'package:photos/services/sync/sync_service.dart';
import "package:photos/settings/local_settings.dart";
import 'package:photos/ui/common/linear_progress_dialog.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/components/buttons/button_widget.dart'
    show ButtonAction;
import 'package:photos/ui/notification/toast.dart';
import "package:photos/utils/device_info.dart";
import 'package:photos/utils/dialog_util.dart';

final _logger = Logger("DeleteFileUtil");

Future<({Set<String> deletedIDs, Set<String> trashedIDs})>
_tryTrashOrDeleteFiles(List<String> assetIDs) async {
  if (assetIDs.isEmpty) {
    return (deletedIDs: <String>{}, trashedIDs: <String>{});
  }
  try {
    if (flagService.internalUser &&
        Platform.isAndroid &&
        !await isAndroidSDKVersionLowerThan(android11SDKINT)) {
      final assets = (await Future.wait(
        assetIDs.map(AssetEntity.fromId),
      )).whereType<AssetEntity>().toList();
      return (
        deletedIDs: <String>{},
        trashedIDs: (await PhotoManager.editor.android.moveToTrash(
          assets,
        )).toSet(),
      );
    }
    final removedIDs = (await PhotoManager.editor.deleteWithIds(
      assetIDs,
    )).toSet();
    return Platform.isAndroid
        ? (deletedIDs: removedIDs, trashedIDs: <String>{})
        : (deletedIDs: <String>{}, trashedIDs: removedIDs);
  } catch (e, s) {
    _logger.severe("Could not delete file", e, s);
    return (deletedIDs: <String>{}, trashedIDs: <String>{});
  }
}

Future<List<EnteFile>> deleteFilesFromEverywhere(
  BuildContext context,
  List<EnteFile> files,
) async {
  _logger.info("Trying to deleteFilesFromEverywhere " + files.toString());
  final List<String> localAssetIDs = [];
  final List<String> localSharedMediaIDs = [];
  final List<String> alreadyDeletedIDs = [];
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
  final result = await _tryTrashOrDeleteFiles(localAssetIDs);
  final deletedIDs = result.deletedIDs
    ..addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));
  final removedIDs = deletedIDs.union(result.trashedIDs);
  final updatedCollectionIDs = <int>{};
  final List<TrashRequest> uploadedFilesToBeTrashed = [];
  final List<EnteFile> deletedFiles = [];
  for (final file in files) {
    if (file.localID != null) {
      if (removedIDs.contains(file.localID) ||
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
      final message = hasLocalOnlyFiles && deletedIDs.isNotEmpty
          ? context.strings.filesDeleted
          : context.strings.movedToTrash;
      showShortToast(context, message);
    }
  }
  if (uploadedFilesToBeTrashed.isNotEmpty) {
    // ignore: unawaited_futures
    RemoteSyncService.instance.sync(silently: true);
  }
  return deletedFiles;
}

Future<void> deleteFilesFromRemoteOnly(
  BuildContext context,
  List<EnteFile> files,
) async {
  final l10n = context.strings;
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
  final List<String> alreadyDeletedIDs = [];
  final localOnlyIDs = <String?>{};
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
      localOnlyIDs.add(file.localID);
    }
  }
  final result = await _tryTrashOrDeleteFiles(localAssetIDs);
  final deletedIDs = result.deletedIDs
    ..addAll(await _tryDeleteSharedMediaFiles(localSharedMediaIDs));
  final removedIDs = deletedIDs.union(result.trashedIDs);
  final List<EnteFile> deletedFiles = [];
  final List<int> uploadedFileIDsToClear = [];
  for (final file in files) {
    if (removedIDs.contains(file.localID) ||
        alreadyDeletedIDs.contains(file.localID)) {
      deletedFiles.add(file);
      if (localOnlyIDs.contains(file.localID)) {
        await FilesDB.instance.deleteLocalFile(file);
      } else {
        final uploadedFileID = file.uploadedFileID;
        file.localID = null;
        if (uploadedFileID != null) {
          uploadedFileIDsToClear.add(uploadedFileID);
        } else {
          await FilesDB.instance.update(file);
        }
      }
    }
  }
  if (uploadedFileIDsToClear.isNotEmpty) {
    await FilesDB.instance.clearLocalIDsForUploadedFileIDs(
      uploadedFileIDsToClear,
    );
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
  if (removedIDs.isNotEmpty && context.mounted) {
    final message = deletedIDs.isNotEmpty
        ? context.strings.filesDeleted
        : context.strings.movedToTrash;
    showShortToast(context, message);
  }
  return deletedFiles;
}

Future<bool> deleteFromTrash(BuildContext context, List<EnteFile> files) async {
  final trashFiles = files.map((file) => file as EnteTrashFile).toList();
  bool didDeletionStart = false;
  final l10n = context.strings;
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
          onTap: () =>
              _runDeleteAction(sheetContext, ButtonAction.first, () async {
                try {
                  didDeletionStart = true;
                  await trashSyncService.deleteFromTrash(trashFiles);
                  Bus.instance.fire(
                    FilesUpdatedEvent(
                      trashFiles,
                      type: EventType.deletedFromEverywhere,
                      source: "deleteFromTrash",
                    ),
                  );
                  // FilesUpdatedEvent does not reload Trash here.
                  Bus.instance.fire(ForceReloadTrashPageEvent());
                } catch (e, s) {
                  _logger.info("failed to delete from trash", e, s);
                  rethrow;
                }
              }),
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
    title: context.strings.emptyTrashQuestion,
    body: context.strings.permDeleteWarning,
    firstButtonLabel: context.strings.empty,
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

Future<LocalDeletionResult> deleteLocalFiles(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info("Trying to delete local files");
  final localAssetIDs = <String>[];
  final localSharedMediaIDs = <String>[];

  try {
    for (final id in localIDs.toSet()) {
      if (id.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(id);
      } else {
        localAssetIDs.add(id);
      }
    }

    final sharedMediaResult = await _deleteAndCheckpointSharedMediaFiles(
      localSharedMediaIDs,
    );
    if (sharedMediaResult.isTerminalFailure) {
      return sharedMediaResult;
    }
    if (!context.mounted) {
      _logger.info(
        "Skipping platform asset deletion after the initiating page was disposed",
      );
      return LocalDeletionResult(
        status: LocalDeletionStatus.failed,
        deletedIDs: sharedMediaResult.deletedIDs,
      );
    }

    final platformResult = await _deletePlatformAssets(context, localAssetIDs);
    return combineDeletionResults(sharedMediaResult, platformResult);
  } catch (e, s) {
    _logger.severe("Could not delete local files", e, s);
    return const LocalDeletionResult(
      status: LocalDeletionStatus.failed,
      shouldTryNextFallback: true,
    );
  }
}

Future<LocalDeletionResult> deleteLocalFilesAfterRemovingAlreadyDeletedIDs(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info(
    "Trying to delete local files after removing already deleted IDs",
  );

  final localAssetIDs = <String>[];
  final localSharedMediaIDs = <String>[];
  final alreadyDeletedIDs = <String>{};
  late LocalDeletionResult sharedMediaResult;

  final dialog = createProgressDialog(context, "Loading...");
  await dialog.show();
  try {
    late final PermissionState permissionState;
    try {
      permissionState = await permissionService.getPermissionState();
    } catch (e, s) {
      _logger.severe(
        "Could not verify gallery permission for stale-ID recovery",
        e,
        s,
      );
      return const LocalDeletionResult(status: LocalDeletionStatus.failed);
    }
    // Restricted gallery access can make an existing asset appear missing, so
    // only use failed lookups as evidence of stale IDs with full access.
    if (permissionState != PermissionState.authorized) {
      _logger.warning(
        "Skipping stale-ID recovery because gallery permission is "
        "$permissionState",
      );
      return const LocalDeletionResult(status: LocalDeletionStatus.failed);
    }

    final files = await FilesDB.instance.getLocalFiles(
      localIDs,
      dedupeByLocalID: true,
    );
    for (final file in files) {
      if (!(await _localFileExist(file))) {
        alreadyDeletedIDs.add(file.localID!);
      } else if (file.localID!.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(file.localID!);
      } else {
        localAssetIDs.add(file.localID!);
      }
    }
    _logger.info(
      "Stale-ID recovery found ${alreadyDeletedIDs.length} missing files",
    );

    try {
      await _checkpointRemovedLocalIDs(alreadyDeletedIDs);
    } catch (e, s) {
      _logger.severe("Could not checkpoint already-missing files", e, s);
      return const LocalDeletionResult(status: LocalDeletionStatus.failed);
    }

    sharedMediaResult = await _deleteAndCheckpointSharedMediaFiles(
      localSharedMediaIDs,
    );
    if (sharedMediaResult.isTerminalFailure) {
      return LocalDeletionResult(
        status: LocalDeletionStatus.failed,
        deletedIDs: sharedMediaResult.deletedIDs,
      );
    }
  } catch (e, s) {
    _logger.severe("Could not delete local files", e, s);
    return const LocalDeletionResult(
      status: LocalDeletionStatus.failed,
      shouldTryNextFallback: true,
    );
  } finally {
    await _hideProgressDialog(dialog);
  }

  if (!context.mounted) {
    _logger.info(
      "Skipping platform asset deletion after the initiating page was disposed",
    );
    return LocalDeletionResult(
      status: LocalDeletionStatus.failed,
      deletedIDs: sharedMediaResult.deletedIDs,
    );
  }

  final platformResult = await _deletePlatformAssets(context, localAssetIDs);
  return combineDeletionResults(sharedMediaResult, platformResult);
}

// Only use on Android.
Future<LocalDeletionResult>
retryFreeUpSpaceAfterRemovingAssetsNonExistingInDisk(
  BuildContext context, {
  required Iterable<String> originalLocalIDs,
}) async {
  _logger.info(
    "Retrying free up space after removing assets non-existing in disk",
  );

  final dialog = createProgressDialog(
    context,
    context.strings.pleaseWaitThisWillTakeAWhile,
  );
  final localAssetIDs = <String>[];
  final localSharedMediaIDs = <String>[];
  late LocalDeletionResult sharedMediaResult;

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

    final FreeableSpaceInfo status = await FilesService.instance
        .getFreeableSpaceInfo();

    final scopedLocalIDs = retainOriginalDeletionCandidates(
      refreshedLocalIDs: status.localIDs,
      originalLocalIDs: originalLocalIDs,
    );
    for (final localID in scopedLocalIDs) {
      if (localID.startsWith(sharedMediaIdentifier)) {
        localSharedMediaIDs.add(localID);
      } else {
        localAssetIDs.add(localID);
      }
    }
    sharedMediaResult = await _deleteAndCheckpointSharedMediaFiles(
      localSharedMediaIDs,
    );
    if (sharedMediaResult.isTerminalFailure) {
      return LocalDeletionResult(
        status: LocalDeletionStatus.failed,
        deletedIDs: sharedMediaResult.deletedIDs,
      );
    }
  } catch (e, s) {
    _logger.severe("Could not complete MediaStore recovery", e, s);
    return const LocalDeletionResult(status: LocalDeletionStatus.failed);
  } finally {
    await _hideProgressDialog(dialog);
  }

  if (!context.mounted) {
    _logger.info(
      "Skipping final platform deletion after the initiating page was disposed",
    );
    return LocalDeletionResult(
      status: LocalDeletionStatus.failed,
      deletedIDs: sharedMediaResult.deletedIDs,
    );
  }

  final platformResult = await _deletePlatformAssets(context, localAssetIDs);
  final result = combineDeletionResults(sharedMediaResult, platformResult);
  return LocalDeletionResult(
    status: result.status,
    deletedIDs: result.deletedIDs,
  );
}

Future<LocalDeletionResult> _deletePlatformAssets(
  BuildContext context,
  List<String> localIDs,
) async {
  final uniqueLocalIDs = localIDs.toSet().toList();
  if (uniqueLocalIDs.isEmpty) {
    return const LocalDeletionResult(status: LocalDeletionStatus.completed);
  }
  if (!context.mounted) {
    return const LocalDeletionResult(status: LocalDeletionStatus.failed);
  }

  // Keep Android 11+ requests below MediaStore's 2000 URI limit. The same
  // threshold also avoids oversized Photos requests on iOS.
  const largeCountThreshold = 1900;
  final isLegacyAndroid =
      Platform.isAndroid && await isAndroidSDKVersionLowerThan(android11SDKINT);
  if (!context.mounted) {
    return const LocalDeletionResult(status: LocalDeletionStatus.failed);
  }
  if (isLegacyAndroid) {
    _logger.info("Deleting platform assets in legacy Android batches");
    return deleteLocalFilesInBatches(
      context,
      uniqueLocalIDs,
      emptyResultMeansCompleted: true,
    );
  }
  if (uniqueLocalIDs.length > largeCountThreshold) {
    _logger.info(
      "Deleting ${uniqueLocalIDs.length} platform assets in bounded batches",
    );
    return deleteLocalFilesInBatches(
      context,
      uniqueLocalIDs,
      minimumParts: 1,
      maximumBatchSize: largeCountThreshold,
    );
  }
  return _deleteLocalFilesInOneShot(context, uniqueLocalIDs);
}

Future<LocalDeletionResult> _deleteLocalFilesInOneShot(
  BuildContext context,
  List<String> localIDs,
) async {
  _logger.info('starting _deleteLocalFilesInOneShot for ${localIDs.length}');
  final dialog = createProgressDialog(
    context,
    "Deleting " + localIDs.length.toString() + " backed up files...",
  );
  await dialog.show();
  try {
    final result = await executeDeletionBatches(
      localIDs: localIDs,
      batchSize: localIDs.length,
      deleteBatch: PhotoManager.editor.deleteWithIds,
      checkpoint: _checkpointRemovedLocalIDs,
    );
    _logger.info(
      '_deleteLocalFilesInOneShot deleted ${result.deletedIDs.length} out '
      'of ${localIDs.length}',
    );
    return result;
  } finally {
    await _hideProgressDialog(dialog);
  }
}

Future<LocalDeletionResult> deleteLocalFilesInBatches(
  BuildContext context,
  List<String> localIDs, {
  int minimumParts = 10,
  int minimumBatchSize = 1,
  int maximumBatchSize = 100,
  bool emptyResultMeansCompleted = false,
}) async {
  final dialogKey = GlobalKey<LinearProgressDialogState>();
  final dialog = LinearProgressDialog(
    "Deleting " + localIDs.length.toString() + " backed up files...",
    key: dialogKey,
  );
  ModalRoute<void>? dialogRoute;
  final dialogPopped = showDialog<void>(
    useRootNavigator: false,
    context: context,
    builder: (context) {
      dialogRoute = ModalRoute.of<void>(context);
      return dialog;
    },
    barrierColor: Colors.black.withValues(alpha: 0.85),
  );
  await WidgetsBinding.instance.endOfFrame;
  final batchSize = min(
    max(minimumBatchSize, (localIDs.length / minimumParts).round()),
    maximumBatchSize,
  );
  try {
    return await executeDeletionBatches(
      localIDs: localIDs,
      batchSize: batchSize,
      deleteBatch: PhotoManager.editor.deleteWithIds,
      checkpoint: _checkpointRemovedLocalIDs,
      emptyResultMeansCompleted: emptyResultMeansCompleted,
      onProgress: (completed, total) {
        dialogKey.currentState?.setProgress(completed / total);
      },
    );
  } finally {
    final dialogContext = dialogKey.currentContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
      await (dialogRoute?.completed ?? dialogPopped);
    }
  }
}

Future<void> _checkpointRemovedLocalIDs(Iterable<String> localIDs) async {
  final uniqueLocalIDs = localIDs.toSet();
  if (uniqueLocalIDs.isEmpty) {
    return;
  }
  final ids = uniqueLocalIDs.toList();
  final deletedFiles = await FilesDB.instance.getLocalFiles(ids);
  await FilesDB.instance.deleteLocalFiles(ids);
  _logger.info("${deletedFiles.length} files deleted locally");
  if (deletedFiles.isNotEmpty) {
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(deletedFiles, source: "deleteLocal"),
    );
  }
}

Future<LocalDeletionResult> _deleteAndCheckpointSharedMediaFiles(
  List<String> localIDs,
) async {
  final requestedIDs = localIDs.toSet();
  if (requestedIDs.isEmpty) {
    return const LocalDeletionResult(status: LocalDeletionStatus.completed);
  }
  final deletedIDs = (await _tryDeleteSharedMediaFiles(
    requestedIDs.toList(),
  )).toSet().intersection(requestedIDs);
  try {
    await _checkpointRemovedLocalIDs(deletedIDs);
  } catch (e, s) {
    _logger.severe("Could not checkpoint deleted shared-media files", e, s);
    return LocalDeletionResult(
      status: LocalDeletionStatus.failed,
      deletedIDs: deletedIDs,
    );
  }
  return LocalDeletionResult(
    status: deletedIDs.length == requestedIDs.length
        ? LocalDeletionStatus.completed
        : LocalDeletionStatus.failed,
    deletedIDs: deletedIDs,
    shouldTryNextFallback: deletedIDs.length != requestedIDs.length,
  );
}

Future<void> _hideProgressDialog(ProgressDialog dialog) async {
  try {
    await dialog.hide();
  } catch (e, s) {
    _logger.warning("Could not hide deletion progress dialog", e, s);
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
  final l10n = context.strings;
  if (!Platform.isAndroid) {
    return;
  }
  if (await isAndroidSDKVersionLowerThan(android12SDKINT)) {
    return;
  }
  if (await PhotoManager.canManageMedia()) {
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
            await PhotoManager.requestManageMedia();
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
  final l10n = context.strings;
  if (selectedFiles.files.length != filesSplit.count) {
    throw AssertionError(
      "Unexpected state, #{selectedFiles.files.length} != "
      "${filesSplit.count}",
    );
  }
  final List<EnteFile> deletableFiles =
      filesSplit.ownedByCurrentUser + filesSplit.pendingUploads;
  Future<bool> deleteFromRemoteOnlyAction(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    if (deleteFromRemoteOnlyOverride != null) {
      await deleteFromRemoteOnlyOverride(context, files);
    } else {
      await deleteFilesFromRemoteOnly(context, files);
    }
    return true;
  }

  Future<bool> deleteOnDeviceOnlyAction(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    if (deleteOnDeviceOnlyOverride != null) {
      await deleteOnDeviceOnlyOverride(context, files);
      return true;
    }
    return (await deleteFilesOnDeviceOnly(context, files)).isNotEmpty;
  }

  Future<bool> deleteFromEverywhereAction(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    if (deleteFromEverywhereOverride != null) {
      await deleteFromEverywhereOverride(context, files);
      return true;
    }
    return (await deleteFilesFromEverywhere(context, files)).isNotEmpty;
  }

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
    if (Platform.isAndroid &&
        (await isAndroidSDKVersionLowerThan(android11SDKINT) ||
            await PhotoManager.canManageMedia())) {
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
                return deleteOnDeviceOnlyAction(
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
      didDelete = await deleteOnDeviceOnlyAction(
        context,
        localGalleryDeletableFiles,
      );
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

  var didDeleteLocalFiles = false;
  final actionResult = await showBottomSheetComponent<bool>(
    context: context,
    useRootNavigator: Platform.isIOS,
    builder: (_) => DeleteConfirmationSheet(
      isLocal: hasLocalFiles,
      isRemote: hasRemoteFiles,
      count: deletableFiles.length,
      onDeleteFromLocal: () async {
        final didDelete = await deleteOnDeviceOnlyAction(
          context,
          deletableFiles,
        );
        didDeleteLocalFiles = didDelete;
        return didDelete;
      },
      onDeleteFromRemote: () async {
        final didDelete = await deleteFromRemoteOnlyAction(
          context,
          deletableFiles,
        );
        if (didDelete && context.mounted) {
          showShortToast(context, l10n.movedToTrash);
        }
        return didDelete;
      },
      onDeleteFromBoth: () async {
        final didDelete = await deleteFromEverywhereAction(
          context,
          deletableFiles,
        );
        didDeleteLocalFiles = didDelete;
        return didDelete;
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
    final l10n = context.strings;
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
  final Future<bool> Function() onDeleteFromLocal;
  final Future<bool> Function() onDeleteFromRemote;
  final Future<bool> Function() onDeleteFromBoth;

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
    Future<bool> Function() callback,
  ) async {
    try {
      final didDelete = await callback();
      if (context.mounted) {
        Navigator.of(context).pop(didDelete);
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
    final l10n = context.strings;
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
                : ButtonComponent(
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
