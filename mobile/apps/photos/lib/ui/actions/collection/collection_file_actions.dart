import "dart:async";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/cupertino.dart';
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/errors.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/services/collections_service.dart";
import 'package:photos/services/favorites_service.dart';
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import 'package:photos/ui/components/action_sheet_widget.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import "package:photos/ui/payment/subscription.dart";
import "package:photos/ui/settings/backup/free_space_options.dart";
import 'package:photos/utils/dialog_util.dart';
import "package:photos/utils/share_util.dart";
import "package:receive_sharing_intent/receive_sharing_intent.dart";

extension CollectionFileActions on CollectionActions {
  Future<void> showRemoveFromCollectionSheetV2(
    BuildContext context,
    Collection collection,
    SelectedFiles selectedFiles,
    bool removingOthersFile, {
    bool isHidden = false,
    String? body,
  }) async {
    final actionResult = await showActionSheet(
      context: context,
      buttons: [
        ButtonWidget(
          labelText: context.strings.remove,
          buttonType: removingOthersFile
              ? ButtonType.critical
              : ButtonType.neutral,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          isInAlert: true,
          onTap: () async {
            try {
              await moveFilesFromCurrentCollection(
                context,
                collection,
                selectedFiles.files,
                isHidden: isHidden,
              );
            } catch (e) {
              logger.severe("Failed to move files", e);
              rethrow;
            }
          },
        ),
        ButtonWidget(
          labelText: context.strings.cancel,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          buttonAction: ButtonAction.second,
          shouldStickToDarkTheme: true,
          isInAlert: true,
        ),
      ],
      title: context.strings.removeFromAlbumTitle,
      body:
          body ??
          (removingOthersFile
              ? context.strings.removeShareItemsWarning
              : context.strings.itemsWillBeRemovedFromAlbum),
      actionSheetType: ActionSheetType.defaultActionSheet,
    );
    if (actionResult?.action != null &&
        actionResult!.action == ButtonAction.error) {
      if (!context.mounted) return;
      await showGenericErrorDialog(
        context: context,
        error: actionResult.exception,
      );
    } else {
      selectedFiles.clearAll();
    }
  }

  Future<bool> addToMultipleCollections(
    BuildContext context,
    List<Collection> collections,
    bool showProgressDialog, {
    List<EnteFile>? selectedFiles,
  }) async {
    final ProgressDialog? dialog = showProgressDialog
        ? createProgressDialog(
            context,
            context.strings.uploadingFilesToAlbum,
            isDismissible: true,
          )
        : null;
    await dialog?.show();
    for (final collection in collections) {
      try {
        final List<EnteFile> files = [];
        final List<EnteFile> filesPendingUpload = [];
        for (final file in selectedFiles!) {
          EnteFile? currentFile;
          if (file.uploadedFileID != null) {
            currentFile = file.copyWith();
          } else if (file.generatedID != null) {
            // Refresh before queuing in case the upload state has changed.
            currentFile = await (FilesDB.instance.getFile(file.generatedID!));
          } else if (file.generatedID == null) {
            logger.severe("generated id should not be null");
          }
          if (currentFile == null) {
            logger.severe("Failed to find fileBy genID");
            continue;
          }

          if (currentFile.uploadedFileID == null) {
            if (currentFile.collectionID != null &&
                currentFile.collectionID != collection.id) {
              currentFile.generatedID = null;
            }
            currentFile.collectionID = collection.id;
            filesPendingUpload.add(currentFile);
          } else {
            files.add(currentFile);
          }
        }
        if (filesPendingUpload.isNotEmpty) {
          await _queuePendingFilesForCollection(
            filesPendingUpload,
            collection.id,
          );
        }
        if (files.isNotEmpty) {
          await CollectionsService.instance.addOrCopyToCollection(
            collection.id,
            files,
          );
        }
        CollectionsService.instance.recordCollectionUsage(collection.id);
      } catch (e, s) {
        logger.severe("Failed to add to album", e, s);
        await dialog?.hide();
        if (!context.mounted) return false;
        if (_isStorageLimitError(e)) {
          await _showStorageFullSheet(context);
        } else {
          await showGenericErrorDialog(context: context, error: e);
        }
        return false;
      } finally {
        // Earlier collections may have succeeded before a later one failed.
        unawaited(RemoteSyncService.instance.sync(silently: true));
      }
    }

    await dialog?.hide();
    return true;
  }

  Future<bool> addToCollection(
    BuildContext context,
    int collectionID,
    bool showProgressDialog, {
    List<EnteFile>? selectedFiles,
    List<SharedMediaFile>? sharedFiles,
    List<AssetEntity>? picketAssets,
  }) async {
    final ProgressDialog? dialog = showProgressDialog
        ? createProgressDialog(
            context,
            context.strings.uploadingFilesToAlbum,
            isDismissible: true,
          )
        : null;
    await dialog?.show();
    try {
      final List<EnteFile> files = [];
      final List<EnteFile> filesPendingUpload = [];
      if (sharedFiles != null) {
        filesPendingUpload.addAll(
          await convertIncomingSharedMediaToFile(sharedFiles, collectionID),
        );
      } else if (picketAssets != null) {
        filesPendingUpload.addAll(
          await convertPicketAssets(picketAssets, collectionID),
        );
      } else {
        for (final file in selectedFiles!) {
          EnteFile? currentFile;
          if (file.uploadedFileID != null) {
            currentFile = file.copyWith();
          } else if (file.generatedID != null) {
            // Refresh before queuing in case the upload state has changed.
            currentFile = await (FilesDB.instance.getFile(file.generatedID!));
          } else if (file.generatedID == null) {
            logger.severe("generated id should not be null");
          }
          if (currentFile == null) {
            logger.severe("Failed to find fileBy genID");
            continue;
          }
          if (currentFile.uploadedFileID == null) {
            currentFile.collectionID = collectionID;
            filesPendingUpload.add(currentFile);
          } else {
            files.add(currentFile);
          }
        }
      }
      if (filesPendingUpload.isNotEmpty) {
        await _queuePendingFilesForCollection(
          filesPendingUpload,
          collectionID,
        );
      }
      if (files.isNotEmpty) {
        await CollectionsService.instance.addOrCopyToCollection(
          collectionID,
          files,
        );
      }
      unawaited(RemoteSyncService.instance.sync(silently: true));
      await dialog?.hide();
      return true;
    } catch (e, s) {
      logger.severe("Failed to add to album", e, s);
      await dialog?.hide();
      if (context.mounted) {
        if (_isStorageLimitError(e)) {
          await _showStorageFullSheet(context);
        } else {
          await showGenericErrorDialog(context: context, error: e);
        }
      }
      rethrow;
    }
  }

  Future<bool> updateFavorites(
    BuildContext context,
    List<EnteFile> files,
    bool markAsFavorite,
  ) async {
    final ProgressDialog dialog = createProgressDialog(
      context,
      markAsFavorite
          ? context.strings.addingToFavorites
          : context.strings.removingFromFavorites,
    );
    await dialog.show();

    try {
      if (!context.mounted) return false;
      await FavoritesService.instance.updateFavorites(
        context,
        files,
        markAsFavorite,
      );
      return true;
    } catch (e, s) {
      logger.severe("Failed to update favorites", e, s);
      if (!context.mounted) return false;
      showShortToast(
        context,
        markAsFavorite
            ? context.strings.sorryCouldNotAddToFavorites
            : context.strings.sorryCouldNotRemoveFromFavorites,
      );
    } finally {
      await dialog.hide();
    }
    return false;
  }

  // Owned albums queue CreateFile against the dest collection. Collaborative
  // albums cannot: CreateFile requires ownership, and storage must stay on
  // the uploader. Queue CreateFile into Uncategorized and keep a pending row
  // in the shared album so add-files can resume after the file ID exists.
  Future<void> _queuePendingFilesForCollection(
    List<EnteFile> filesPendingUpload,
    int destCollectionID,
  ) async {
    final int currentUserID = Configuration.instance.getUserID()!;
    final Collection? dest = CollectionsService.instance.getCollectionByID(
      destCollectionID,
    );
    final bool isSharedCollection = dest != null && !dest.isOwner(currentUserID);
    final int uploadCollectionID = isSharedCollection
        ? (await CollectionsService.instance.getUncategorizedCollection()).id
        : destCollectionID;
    for (final file in filesPendingUpload) {
      file.collectionID = uploadCollectionID;
    }
    await IgnoredFilesService.instance.removeIgnoredMappings(
      filesPendingUpload,
    );
    await FilesDB.instance.insertMultiple(filesPendingUpload);
    Bus.instance.fire(
      CollectionUpdatedEvent(
        uploadCollectionID,
        filesPendingUpload,
        "pendingFilesAdd",
      ),
    );
    if (!isSharedCollection) {
      return;
    }
    final placeholders = <EnteFile>[];
    for (final file in filesPendingUpload) {
      final placeholder = file.copyWith();
      placeholder.generatedID = null;
      placeholder.collectionID = destCollectionID;
      placeholders.add(placeholder);
    }
    await FilesDB.instance.insertMultiple(placeholders);
    Bus.instance.fire(
      CollectionUpdatedEvent(
        destCollectionID,
        placeholders,
        "pendingFilesAdd",
      ),
    );
  }
}

enum _StorageFullAction { upgrade, freeUpSpace }

Future<void> _showStorageFullSheet(BuildContext context) async {
  final action = await showBottomSheetComponent<_StorageFullAction>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: sheetContext.strings.notEnoughStorageTitle,
      content: Text(
        sheetContext.strings.notEnoughStorageBody,
        style: TextStyles.body.copyWith(
          color: sheetContext.componentColors.textLight,
        ),
      ),
      actions: [
        ButtonComponent(
          label: sheetContext.strings.upgrade,
          variant: ButtonComponentVariant.primary,
          size: ButtonComponentSize.large,
          onTap: () =>
              Navigator.of(sheetContext).pop(_StorageFullAction.upgrade),
        ),
        ButtonComponent(
          label: sheetContext.strings.freeUpSpace,
          variant: ButtonComponentVariant.secondary,
          size: ButtonComponentSize.large,
          onTap: () =>
              Navigator.of(sheetContext).pop(_StorageFullAction.freeUpSpace),
        ),
      ],
    ),
  );
  if (!context.mounted) {
    return;
  }
  switch (action) {
    case _StorageFullAction.upgrade:
      await routeToPage(context, getSubscriptionPage());
    case _StorageFullAction.freeUpSpace:
      await routeToPage(context, const FreeUpSpaceOptionsScreen());
    case null:
      return;
  }
}

bool _isStorageLimitError(Object error) {
  return error is StorageLimitExceededError ||
      error is DioException && error.response?.statusCode == 426;
}
