import "package:ente_ui/components/buttons/button_widget.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:locker/core/errors.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/models/info/info_item.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/favorites_service.dart";
import "package:locker/services/files/links/links_service.dart";
import "package:locker/services/files/sync/metadata_updater_service.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/services/info_file_service.dart";
import "package:locker/services/trash/models/trash_file.dart";
import "package:locker/services/trash/trash_service.dart";
import "package:locker/ui/components/delete_confirmation_sheet.dart";
import "package:locker/ui/components/file_edit_sheet.dart";
import "package:locker/ui/components/share_link_sheet.dart";
import "package:locker/ui/components/subscription_required_sheet.dart";
import "package:locker/ui/pages/account_credentials_page.dart";
import "package:locker/ui/pages/base_info_page.dart";
import "package:locker/ui/pages/emergency_contact_page.dart";
import "package:locker/ui/pages/personal_note_page.dart";
import "package:locker/ui/pages/physical_records_page.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";
import "package:logging/logging.dart";

/// Utility class for common file actions like edit, share, delete, and favorites
class FileActions {
  static final _logger = Logger("FileActions");

  /// Shows edit dialog for a file to update title
  static Future<void> editFile(
    BuildContext context,
    EnteFile file, {
    VoidCallback? onSuccess,
  }) async {
    if (file is TrashFile) {
      _logger.warning(
        'Ignoring edit request for trashed file ${file.uploadedFileID}',
      );
      return;
    }

    if (InfoFileService.instance.isInfoFile(file)) {
      await _editInfoFile(context, file);
      return;
    }

    _logger.info('Opening edit dialog for file ${file.uploadedFileID}');

    final editableCollections = await CollectionService.instance
        .getCollectionsForUI(includeUncategorized: true);

    final currentCollections = await CollectionService.instance
        .getCollectionsForFile(file);

    final favoriteCollection = await CollectionService.instance
        .getOrCreateImportantCollection();

    final currentCollectionIds = currentCollections.map((c) => c.id).toSet();

    if (!context.mounted) return;
    final result = await showFileEditSheet(
      context,
      file: file,
      collections: editableCollections,
    );

    if (result == null) {
      return;
    }

    // Fetch collections in case new ones were created during file edit dialog
    final updatedAllCollections = await CollectionService.instance
        .getCollections();

    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.pleaseWait,
            isDismissible: false,
          )
        : null;
    await dialog?.show();

    try {
      final currentTitle = file.displayName;
      final hasMetadataChanged = result.title != currentTitle;

      if (hasMetadataChanged) {
        _logger.info('Updating file metadata: title changed');
        final metadataUpdateSuccess = await MetadataUpdaterService.instance
            .editFileName(file, result.title);

        if (!metadataUpdateSuccess) {
          await dialog?.hide();
          if (!context.mounted) {
            return;
          }
          showToast(
            context,
            context.l10n.failedToUpdateFile('Metadata update failed'),
          );
          return;
        }
      }
      final selectedCollectionIds = result.selectedCollections
          .map((c) => c.id)
          .toSet();

      final wasFavorite = currentCollectionIds.contains(favoriteCollection.id);
      final isFavoriteNow = selectedCollectionIds.contains(
        favoriteCollection.id,
      );

      if (wasFavorite && !isFavoriteNow) {
        await FavoritesService.instance.removeFromFavorites(file);
      } else if (!wasFavorite && isFavoriteNow) {
        await FavoritesService.instance.addToFavorites(file);
      }

      final regularCurrentIds = currentCollectionIds
          .where((id) => id != favoriteCollection.id)
          .toSet();
      final regularSelectedIds = selectedCollectionIds
          .where((id) => id != favoriteCollection.id)
          .toSet();

      final collectionsToRemove = regularCurrentIds.difference(
        regularSelectedIds,
      );

      final collectionsToAdd = regularSelectedIds.difference(regularCurrentIds);

      if (regularSelectedIds.isEmpty && collectionsToRemove.isNotEmpty) {
        _logger.info('All collections deselected, moving to uncategorized');

        for (final collectionId in collectionsToRemove) {
          try {
            final collection = updatedAllCollections.firstWhere(
              (c) => c.id == collectionId,
            );
            await CollectionService.instance.moveFilesFromCurrentCollection(
              context.mounted ? context : null,
              collection,
              [file],
            );
          } catch (e) {
            final collection = updatedAllCollections.firstWhere(
              (c) => c.id == collectionId,
            );
            _logger.severe(
              'Failed to remove file from collection (ID: ${collection.id}): $e',
            );
          }
        }
      } else {
        for (final collectionId in collectionsToAdd) {
          final collection = updatedAllCollections.firstWhere(
            (c) => c.id == collectionId,
          );

          try {
            await CollectionService.instance.addToCollection(
              collection,
              file,
              runSync: false,
            );
          } catch (e) {
            _logger.severe(
              'Failed to move file to collection (ID: ${collection.id}): $e',
            );
          }
        }

        for (final collectionId in collectionsToRemove) {
          final collection = updatedAllCollections.firstWhere(
            (c) => c.id == collectionId,
          );
          await CollectionService.instance.moveFilesFromCurrentCollection(
            context.mounted ? context : null,
            collection,
            [file],
          );
        }
      }

      await CollectionService.instance.sync();
      await dialog?.hide();
      onSuccess?.call();

      if (!context.mounted) {
        return;
      }

      showToast(context, context.l10n.fileUpdatedSuccessfully);
    } catch (e) {
      await dialog?.hide();
      _logger.severe('Failed to update file collections: $e');

      if (!context.mounted) {
        return;
      }
      await showLockerErrorSheet(context, e);
    }
  }

  static Future<void> _editInfoFile(BuildContext context, EnteFile file) async {
    Widget page;
    final infoItem = InfoFileService.instance.extractInfoFromFile(file);

    if (infoItem == null) {
      _logger.warning(
        'File ${file.uploadedFileID} marked as info file but no info payload found',
      );
      return;
    }

    switch (infoItem.type) {
      case InfoType.note:
        page = PersonalNotePage(mode: InfoPageMode.edit, existingFile: file);
        break;
      case InfoType.accountCredential:
        page = AccountCredentialsPage(
          mode: InfoPageMode.edit,
          existingFile: file,
        );
        break;
      case InfoType.physicalRecord:
        page = PhysicalRecordsPage(mode: InfoPageMode.edit, existingFile: file);
        break;
      case InfoType.emergencyContact:
        page = EmergencyContactPage(
          mode: InfoPageMode.edit,
          existingFile: file,
        );
        break;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => page));
  }

  /// Creates and shows a shareable link for a file
  static Future<void> shareFileLink(BuildContext context, EnteFile file) async {
    final dialog = createProgressDialog(
      context,
      context.l10n.creatingShareLink,
      isDismissible: false,
    );

    try {
      await dialog.show();

      final shareableLink = await LinksService.instance.getOrCreateLink(file);

      await dialog.hide();

      if (context.mounted) {
        await showShareLinkSheet(
          context,
          shareableLink.fullURL!,
          shareableLink.linkID,
          file,
        );
      }
    } catch (e) {
      await dialog.hide();

      if (context.mounted) {
        if (e is SharingNotPermittedForFreeAccountsError) {
          await showSubscriptionRequiredSheet(context);
        } else {
          await showLockerErrorSheet(context, e);
        }
      }
    }
  }

  /// Deletes a single file after confirmation
  static Future<void> deleteFile(
    BuildContext context,
    EnteFile file, {
    VoidCallback? onSuccess,
  }) async {
    final confirmation = await showDeleteConfirmationSheet(
      context,
      title: context.l10n.areYouSure,
      body: context.l10n.deleteMultipleFilesDialogBody(1),
      deleteButtonLabel: context.l10n.yesDeleteFiles(1),
      illustration: LockerBottomSheetIllustration.fileDelete,
    );

    if (confirmation?.buttonResult.action != ButtonAction.first) {
      return;
    }

    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.deletingFile,
            isDismissible: false,
          )
        : null;

    try {
      await dialog?.show();

      final collections = await CollectionService.instance
          .getCollectionsForFile(file);
      if (collections.isNotEmpty) {
        await CollectionService.instance.trashFile(file, collections.first);
      }

      await dialog?.hide();

      if (context.mounted) {
        showToast(context, context.l10n.fileDeletedSuccessfully);
      }

      onSuccess?.call();
    } catch (e) {
      await dialog?.hide();

      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  /// Deletes multiple files after confirmation
  static Future<void> deleteMultipleFiles(
    BuildContext context,
    List<EnteFile> files, {
    VoidCallback? onSuccess,
  }) async {
    if (files.isEmpty) {
      return;
    }

    final confirmation = await showDeleteConfirmationSheet(
      context,
      title: context.l10n.areYouSure,
      body: context.l10n.deleteMultipleFilesDialogBody(files.length),
      deleteButtonLabel: context.l10n.yesDeleteFiles(files.length),
      illustration: LockerBottomSheetIllustration.fileDelete,
    );

    if (confirmation?.buttonResult.action != ButtonAction.first) {
      return;
    }

    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.deletingFile,
            isDismissible: false,
          )
        : null;

    try {
      await dialog?.show();

      for (final file in files) {
        final collections = await CollectionService.instance
            .getCollectionsForFile(file);

        if (collections.isNotEmpty) {
          await CollectionService.instance.trashFile(
            file,
            collections.first,
            runSync: false,
          );
        }
      }

      await CollectionService.instance.sync();
      await TrashService.instance.syncTrash();

      await dialog?.hide();

      if (context.mounted) {
        showToast(context, context.l10n.fileDeletedSuccessfully);
      }

      onSuccess?.call();
    } catch (e, stackTrace) {
      await dialog?.hide();

      _logger.severe('Failed to delete files: $e', e, stackTrace);
      if (!context.mounted) {
        return;
      }
      await showLockerErrorSheet(context, e);
    }
  }

  /// Checks if a file is marked as important using cache
  static bool isImportant(EnteFile file) {
    return FavoritesService.instance.isFavoriteCache(file);
  }

  /// Toggles important status of a single file
  static Future<void> markImportant(
    BuildContext context,
    EnteFile file, {
    VoidCallback? onSuccess,
  }) async {
    final isCurrentlyImportant = isImportant(file);
    final dialog = createProgressDialog(
      context,
      isCurrentlyImportant
          ? context.l10n.removingFromImportant
          : context.l10n.markingAsImportant,
      isDismissible: false,
    );

    try {
      await dialog.show();

      if (isCurrentlyImportant) {
        await FavoritesService.instance.removeFromFavorites(file);
      } else {
        await FavoritesService.instance.addToFavorites(file);
      }

      await dialog.hide();

      if (context.mounted) {
        showToast(
          context,
          !isCurrentlyImportant
              ? context.l10n.fileMarkedAsImportant
              : context.l10n.fileRemovedFromImportant,
        );
      }

      onSuccess?.call();
    } catch (e, stackTrace) {
      _logger.severe("Failed to toggle important status: $e", e, stackTrace);
      await dialog.hide();

      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  /// Marks multiple files as important
  static Future<void> markMultipleImportant(
    BuildContext context,
    List<EnteFile> files, {
    VoidCallback? onSuccess,
  }) async {
    final dialog = createProgressDialog(
      context,
      context.l10n.markingAsImportant,
      isDismissible: false,
    );

    try {
      await dialog.show();

      final filesToMark = files
          .where((file) => !FavoritesService.instance.isFavoriteCache(file))
          .toList();

      if (filesToMark.isEmpty) {
        await dialog.hide();
        if (context.mounted) {
          showToast(context, context.l10n.allFilesAlreadyMarkedAsImportant);
        }
        return;
      }

      await FavoritesService.instance.updateFavorites(filesToMark, true);

      await dialog.hide();

      if (context.mounted) {
        showToast(
          context,
          context.l10n.filesMarkedAsImportant(filesToMark.length),
        );
      }

      onSuccess?.call();
    } catch (e, stackTrace) {
      _logger.severe(
        "Failed to mark multiple files as important: $e",
        e,
        stackTrace,
      );
      await dialog.hide();

      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }
}
