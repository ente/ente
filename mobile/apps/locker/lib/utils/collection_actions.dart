import "dart:async";

import "package:ente_accounts/services/user_service.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_sharing/components/invite_dialog.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_ui/components/buttons/button_widget.dart";
import "package:ente_ui/components/progress_dialog.dart";
import 'package:ente_ui/utils/dialog_util.dart';
import "package:ente_ui/utils/toast_util.dart";
import 'package:flutter/material.dart';
import "package:locker/core/errors.dart";
import 'package:locker/l10n/l10n.dart';
import "package:locker/services/collections/collections_api_client.dart";
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import "package:locker/services/configuration.dart";
import "package:locker/services/trash/trash_service.dart";
import "package:locker/ui/components/delete_confirmation_sheet.dart";
import "package:locker/ui/components/subscription_required_sheet.dart";
import "package:locker/ui/components/text_input_sheet.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";
import 'package:logging/logging.dart';

/// Utility class for common collection actions like edit and delete
class CollectionActions {
  static final _logger = Logger('CollectionActions');

  /// Shows a dialog sheet to create a new collection
  static Future<Collection?> createCollection(
    BuildContext context, {
    bool autoSelectInParent = false,
  }) async {
    Collection? createdCollection;

    final result = await showTextInputSheet(
      context,
      title: context.l10n.newCollection,
      hintText: context.l10n.enterCollectionName,
      submitButtonLabel: context.l10n.createCollection,
      onSubmit: (String text) async {
        if (text.trim().isEmpty) {
          return;
        }

        try {
          createdCollection = await CollectionService.instance.createCollection(
            text.trim(),
          );
        } catch (e, s) {
          _logger.severe('Failed to create collection', e, s);
          rethrow;
        }
      },
    );

    if (result is Exception) {
      if (context.mounted) {
        await showLockerErrorSheet(context, result);
      }
      return null;
    } else if (createdCollection != null) {
      return createdCollection;
    }

    return null;
  }

  // Shows a dialog to edit/rename a collection
  static Future<void> editCollection(
    BuildContext context,
    Collection collection, {
    VoidCallback? onSuccess,
  }) async {
    final l10n = context.l10n;
    if (!collection.type.canEdit) {
      showToast(context, l10n.collectionCannotBeEdited);
      return;
    }

    await showTextInputSheet(
      context,
      title: l10n.renameCollection,
      initialValue: collection.name ?? '',
      hintText: l10n.documentsHint,
      submitButtonLabel: l10n.save,
      onSubmit: (String newName) async {
        if (newName.isEmpty || newName == collection.name) return;

        final progressDialog = createProgressDialog(context, l10n.pleaseWait);
        await progressDialog.show();

        try {
          await CollectionService.instance.rename(collection, newName);
          await progressDialog.hide();

          if (context.mounted) {
            showToast(context, l10n.collectionRenamedSuccessfully);
          }

          // Update the collection name locally
          collection.setName(newName);

          // Call success callback if provided
          onSuccess?.call();
        } catch (error) {
          await progressDialog.hide();

          if (context.mounted) {
            await showLockerErrorSheet(context, error);
          }
        }
      },
    );
  }

  static Future<void> deleteMultipleCollections(
    BuildContext context,
    List<Collection> collections, {
    VoidCallback? onSuccess,
  }) async {
    if (collections.isEmpty) return;
    final l10n = context.l10n;

    final dialogChoice = await showDeleteConfirmationSheet(
      context,
      title: l10n.areYouSure,
      body: l10n.deleteMultipleCollectionsDialogBody(collections.length),
      deleteButtonLabel: l10n.yesDeleteCollections(collections.length),
      illustration: LockerBottomSheetIllustration.collectionDelete,
      showDeleteFromAllCollectionsOption: true,
    );

    if (dialogChoice?.buttonResult.action != ButtonAction.first) return;

    ProgressDialog? progressDialog;
    if (context.mounted) {
      progressDialog = createProgressDialog(context, l10n.pleaseWait);
      await progressDialog.show();
    }

    bool isFavoriteCollection = false;
    final bool keepFiles = !(dialogChoice?.deleteFromAllCollections ?? false);
    final List<Collection> emptyCollections = [];
    final List<Collection> nonEmptyCollections = [];
    final List<dynamic> errors = [];
    var deletedCount = 0;

    try {
      for (final collection in collections) {
        if (collection.type == CollectionType.favorites) {
          isFavoriteCollection = true;
          continue;
        }
        if (!collection.type.canDelete) {
          continue;
        }

        final fileCount = await CollectionService.instance.getFileCount(
          collection,
        );

        if (fileCount == 0) {
          emptyCollections.add(collection);
        } else {
          nonEmptyCollections.add(collection);
        }
      }

      for (final collection in emptyCollections) {
        try {
          await CollectionService.instance.trashEmptyCollection(
            collection,
            isBulkDelete: true,
          );
          deletedCount++;
        } catch (e, s) {
          _logger.severe("Failed to trash empty collection", e, s);
          errors.add(e);
        }
      }

      if (emptyCollections.isNotEmpty) {
        await CollectionService.instance.sync();
        await TrashService.instance.syncTrash();
      }

      for (final collection in nonEmptyCollections) {
        try {
          await CollectionService.instance.trashCollection(
            context.mounted ? context : null,
            collection,
            keepFiles: keepFiles,
          );
          deletedCount++;
        } catch (e, s) {
          _logger.severe("Failed to trash collection", e, s);
          errors.add(e);
        }
      }

      await progressDialog?.hide();

      if (deletedCount > 0) {
        onSuccess?.call();
      }

      if (errors.isNotEmpty && context.mounted) {
        await showLockerErrorSheet(context, errors.first);
      }

      if (context.mounted) {
        if (deletedCount > 0) {
          showToast(context, l10n.collectionsDeletedSuccessfully(deletedCount));
        }

        if (isFavoriteCollection) {
          showToast(context, l10n.actionNotSupportedOnFavouritesAlbum);
        }
      }
    } catch (error) {
      await progressDialog?.hide();

      if (context.mounted) {
        await showLockerErrorSheet(context, error);
      }
    }
  }

  /// Shows a confirmation dialog and deletes a collection
  static Future<void> deleteCollection(
    BuildContext context,
    Collection collection, {
    VoidCallback? onSuccess,
  }) async {
    final l10n = context.l10n;
    if (!collection.type.canDelete) {
      showToast(context, l10n.collectionCannotBeDeleted);
      return;
    }

    final fileCount = await CollectionService.instance.getFileCount(collection);

    if (fileCount == 0) {
      ProgressDialog? progressDialog;
      if (context.mounted) {
        progressDialog = createProgressDialog(context, l10n.pleaseWait);
        await progressDialog.show();
      }

      try {
        await CollectionService.instance.trashEmptyCollection(collection);

        await progressDialog?.hide();

        if (context.mounted) {
          showToast(context, l10n.collectionDeletedSuccessfully);
        }

        // Call success callback if provided
        onSuccess?.call();
      } catch (error) {
        await progressDialog?.hide();

        if (context.mounted) {
          await showLockerErrorSheet(context, error);
        }
      }
      return;
    }

    final collectionName = collection.name ?? 'this collection';
    if (!context.mounted) return;

    final result = await showDeleteConfirmationSheet(
      context,
      title: l10n.areYouSure,
      body: l10n.deleteCollectionDialogBody(collectionName),
      deleteButtonLabel: l10n.yesDeleteCollections(1),
      illustration: LockerBottomSheetIllustration.collectionDelete,
      showDeleteFromAllCollectionsOption: true,
    );

    if (result?.buttonResult.action != ButtonAction.first) {
      return;
    }

    ProgressDialog? progressDialog;
    if (context.mounted) {
      progressDialog = createProgressDialog(context, l10n.pleaseWait);
      await progressDialog.show();
    }

    try {
      // If deleteFromAllCollections is true → keepFiles should be false (move files to trash)
      // If deleteFromAllCollections is false → keepFiles should be true (keep files in other collections)
      await CollectionService.instance.trashCollection(
        context.mounted ? context : null,
        collection,
        keepFiles: !(result?.deleteFromAllCollections ?? false),
      );

      await progressDialog?.hide();

      if (context.mounted) {
        showToast(context, l10n.collectionDeletedSuccessfully);
      }

      // Call success callback if provided
      onSuccess?.call();
    } catch (error) {
      await progressDialog?.hide();

      if (context.mounted) {
        await showLockerErrorSheet(context, error);
      }
    }
  }

  static Future<void> leaveCollection(
    BuildContext context,
    Collection collection, {
    VoidCallback? onSuccess,
  }) async {
    final confirmed = await showBottomSheetComponent(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.l10n.leaveCollection,
        message: context.l10n.filesAddedByYouWillBeRemovedFromTheCollection,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.leaveCollection,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await CollectionApiClient.instance.leaveCollection(collection);
        onSuccess?.call();
        if (context.mounted) {
          showToast(context, context.l10n.leaveCollectionSuccessfully);
        }
      } catch (e) {
        _logger.severe("Failed to leave collection", e);
        if (context.mounted) {
          await showLockerErrorSheet(context, e);
        }
      }
    }
  }

  static Future<void> leaveMultipleCollection(
    BuildContext context,
    List<Collection> collections, {
    VoidCallback? onSuccess,
  }) async {
    final confirmed = await showBottomSheetComponent(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.l10n.leaveCollection,
        message: context.l10n.filesAddedByYouWillBeRemovedFromTheCollection,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.leaveCollection,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        for (final col in collections) {
          await CollectionApiClient.instance.leaveCollection(col);
        }
        onSuccess?.call();
        if (context.mounted) {
          showToast(
            context,
            context.l10n.leftCollectionsSuccessfully(collections.length),
          );
        }
      } catch (e) {
        _logger.severe("Failed to leave collections", e);
        if (context.mounted) {
          await showLockerErrorSheet(context, e);
        }
      }
    }
  }

  static Future<bool> enableUrl(
    BuildContext context,
    Collection collection, {
    bool enableCollect = false,
  }) async {
    try {
      await CollectionApiClient.instance.createShareUrl(
        collection,
        enableCollect: enableCollect,
      );
      return true;
    } catch (e) {
      if (e is! SharingNotPermittedForFreeAccountsError) {
        _logger.severe("Failed to update shareUrl collection", e);
      }
      if (context.mounted) {
        if (e is SharingNotPermittedForFreeAccountsError) {
          await showSubscriptionRequiredSheet(context);
        } else {
          await showLockerErrorSheet(context, e);
        }
      }
      return false;
    }
  }

  static Future<bool> disableUrl(
    BuildContext context,
    Collection collection,
  ) async {
    final shouldRemove = await showBottomSheetComponent<bool>(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.l10n.removePublicLink,
        message: context.l10n.removePublicLinkConfirmation(
          collection.name ?? "this collection",
        ),
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.yesRemove,
            variant: ButtonComponentVariant.critical,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (shouldRemove != true) {
      return false;
    }

    try {
      await CollectionApiClient.instance.disableShareUrl(collection);
      return true;
    } catch (e) {
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      return false;
    }
  }

  Future<bool> doesEmailHaveAccount(
    BuildContext context,
    String email, {
    bool showProgress = false,
  }) async {
    ProgressDialog? dialog;
    String? publicKey;
    if (showProgress) {
      dialog = createProgressDialog(
        context,
        context.l10n.sharing,
        isDismissible: true,
      );
      await dialog.show();
    }
    try {
      publicKey = await UserService.instance.getPublicKey(email);
    } catch (e) {
      await dialog?.hide();
      _logger.severe("Failed to get public key", e);
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      return false;
    }
    // getPublicKey can return null when no user is associated with given
    // email id
    if (publicKey == null || publicKey == '') {
      // todo: neeraj replace this as per the design where a new screen
      // is used for error. Do this change along with handling of network errors
      if (context.mounted) {
        await showInviteSheet(context, email: email);
      }
      return false;
    } else {
      return true;
    }
  }

  // addEmailToCollection returns true if add operation was successful
  Future<bool> addEmailToCollection(
    BuildContext? context,
    Collection collection,
    String email,
    CollectionParticipantRole role, {
    bool showProgress = false,
  }) async {
    if (!isValidEmail(email)) {
      if (context != null && context.mounted) {
        await showBottomSheetComponent(
          context: context,
          builder: (_) => BottomSheetComponent(
            title: context.l10n.invalidEmailAddress,
            message: context.l10n.enterValidEmail,
            illustration: LockerBottomSheetIllustration.warningBlue,
          ),
        );
      }
      return false;
    } else if (email.trim() == Configuration.instance.getEmail()) {
      if (context != null && context.mounted) {
        await showBottomSheetComponent(
          context: context,
          builder: (_) => BottomSheetComponent(
            title: context.l10n.oops,
            message: context.l10n.youCannotShareWithYourself,
            illustration: LockerBottomSheetIllustration.warningBlue,
          ),
        );
      }
      return false;
    }

    ProgressDialog? dialog;
    String? publicKey;
    if (showProgress && context != null && context.mounted) {
      dialog = createProgressDialog(
        context,
        context.l10n.sharing,
        isDismissible: true,
      );
      await dialog.show();
    }

    try {
      publicKey = await UserService.instance.getPublicKey(email);
    } catch (e) {
      await dialog?.hide();
      _logger.severe("Failed to get public key", e);
      if (context != null && context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      return false;
    }
    // getPublicKey can return null when no user is associated with given
    // email id
    if (publicKey == null || publicKey == '') {
      await dialog?.hide();
      if (context != null && context.mounted) {
        await showInviteSheet(context, email: email);
      }
      return false;
    } else {
      try {
        final newSharees = await CollectionApiClient.instance.share(
          collection.id,
          email,
          publicKey,
          role,
        );
        await dialog?.hide();
        collection.updateSharees(newSharees);
        return true;
      } catch (e) {
        await dialog?.hide();
        if (e is! SharingNotPermittedForFreeAccountsError) {
          _logger.severe("failed to share collection", e);
        }
        if (context != null && context.mounted) {
          if (e is SharingNotPermittedForFreeAccountsError) {
            await showSubscriptionRequiredSheet(context);
          } else {
            await showLockerErrorSheet(context, e);
          }
        }
        return false;
      }
    }
  }

  // removeParticipant remove the user from a share album
  Future<bool> removeParticipant(
    BuildContext context,
    Collection collection,
    User user,
  ) async {
    try {
      final newSharees = await CollectionApiClient.instance.unshare(
        collection.id,
        user.email,
      );
      collection.updateSharees(newSharees);
      return true;
    } catch (e) {
      _logger.severe("Failed to remove participant", e);
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      return false;
    }
  }
}
