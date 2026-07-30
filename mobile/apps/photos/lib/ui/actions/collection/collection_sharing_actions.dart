import "dart:async";

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart' hide isValidEmail;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/core/errors.dart";
import 'package:photos/db/files_db.dart';
import 'package:photos/gateways/collections/models/create_request.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/button_result.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/files_split.dart';
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/common_keys.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/contacts/contact_identity_resolver.dart';
import 'package:photos/services/hidden_service.dart';
import 'package:photos/ui/common/progress_dialog.dart';
import "package:photos/ui/common/user_dialogs.dart";
import 'package:photos/ui/components/action_sheet_widget.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/email_util.dart';
import 'package:photos/utils/share_util.dart';
import "package:styled_text/styled_text.dart";

class CollectionActions {
  final Logger logger = Logger((CollectionActions).toString());
  final CollectionsService collectionsService;

  CollectionActions(this.collectionsService);

  Future<bool> enableUrl(
    BuildContext context,
    Collection collection, {
    bool enableCollect = false,
  }) async {
    try {
      await CollectionsService.instance.createShareUrl(
        collection,
        enableCollect: enableCollect,
      );
      return true;
    } catch (e) {
      if (e is SharingNotPermittedForFreeAccountsError) {
        if (!context.mounted) return false;
        await _showUnSupportedAlert(context);
      } else {
        logger.severe("Failed to update shareUrl collection", e);
        if (!context.mounted) return false;
        await showGenericErrorDialog(context: context, error: e);
      }
      return false;
    }
  }

  Future<bool> disableUrl(BuildContext context, Collection collection) async {
    final actionResult = await showActionSheet(
      context: context,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.critical,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          labelText: AppLocalizations.of(context).yesRemove,
          onTap: () async {
            // for quickLink collection, we need to trash the collection
            if (collection.isQuickLinkCollection() && !collection.hasSharees) {
              await trashCollectionKeepingPhotos(collection);
            } else {
              await CollectionsService.instance.disableShareUrl(collection);
            }
          },
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          labelText: AppLocalizations.of(context).cancel,
        ),
      ],
      title: AppLocalizations.of(context).removePublicLink,
      body:
          //'This will remove the public link for accessing "${collection.name}".',
          AppLocalizations.of(
            context,
          ).disableLinkMessage(albumName: collection.displayName),
    );
    if (actionResult?.action != null) {
      if (actionResult!.action == ButtonAction.error) {
        if (!context.mounted) return false;
        await showGenericErrorDialog(
          context: context,
          error: actionResult.exception,
        );
      }
      return actionResult.action == ButtonAction.first;
    } else {
      return false;
    }
  }

  Future<Collection?> createSharedCollectionLink(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    late final Collection newCollection;
    try {
      // create album with emptyName, use collectionCreationTime on UI to
      // show name
      logger.info("creating album for sharing files");
      final EnteFile fileWithMinCreationTime = files.reduce(
        (a, b) => (a.creationTime ?? 0) < (b.creationTime ?? 0) ? a : b,
      );
      final EnteFile fileWithMaxCreationTime = files.reduce(
        (a, b) => (a.creationTime ?? 0) > (b.creationTime ?? 0) ? a : b,
      );
      final String dummyName = getNameForDateRange(
        fileWithMinCreationTime.creationTime!,
        fileWithMaxCreationTime.creationTime!,
      );
      final CreateRequest req = await collectionsService
          .buildCollectionCreateRequest(
            dummyName,
            visibility: visibleVisibility,
            subType: subTypeSharedFilesCollection,
          );
      final collection = await collectionsService.createAndCacheCollection(req);
      newCollection = collection;
      logger.info("adding files to share to new album");
      await collectionsService.addOrCopyToCollection(collection.id, files);
      logger.info("creating public link for the newly created album");
      try {
        await CollectionsService.instance.createShareUrl(collection);
      } catch (e) {
        if (e is SharingNotPermittedForFreeAccountsError) {
          if (newCollection.isQuickLinkCollection() &&
              !newCollection.hasSharees) {
            await trashCollectionKeepingPhotos(newCollection);
          }
          rethrow;
        }
      }
      return collection;
    } catch (e, s) {
      if (e is SharingNotPermittedForFreeAccountsError) {
        if (!context.mounted) return null;
        await _showUnSupportedAlert(context);
      } else {
        logger.severe("Failing to create link for selected files", e, s);
        if (!context.mounted) return null;
        await showGenericErrorDialog(context: context, error: e);
      }
    }
    return null;
  }

  // removeParticipant remove the user from a share album
  Future<bool> removeParticipant(
    BuildContext context,
    Collection collection,
    User user,
  ) async {
    final actionResult = await showActionSheet(
      context: context,
      buttons: [
        ButtonWidget(
          buttonType: ButtonType.critical,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          labelText: AppLocalizations.of(context).yesRemove,
          onTap: () async {
            final newSharees = await CollectionsService.instance.unshare(
              collection.id,
              user.email,
            );
            collection.updateSharees(newSharees);
          },
        ),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
          shouldStickToDarkTheme: true,
          labelText: AppLocalizations.of(context).cancel,
        ),
      ],
      title: AppLocalizations.of(context).removeWithQuestionMark,
      body: AppLocalizations.of(
        context,
      ).removeParticipantBody(userEmail: resolveDisplayName(user)),
    );
    if (actionResult?.action != null) {
      if (actionResult!.action == ButtonAction.error) {
        if (!context.mounted) return false;
        await showGenericErrorDialog(
          context: context,
          error: actionResult.exception,
        );
      }
      return actionResult.action == ButtonAction.first;
    }
    return false;
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
        AppLocalizations.of(context).sharing,
        isDismissible: true,
      );
      await dialog.show();
    }
    try {
      publicKey = await UserService.instance.getPublicKey(email);
    } catch (e) {
      await dialog?.hide();
      logger.severe("Failed to get public key", e);
      if (!context.mounted) return false;
      await showGenericErrorDialog(context: context, error: e);
      return false;
    }
    // getPublicKey can return null when no user is associated with given
    // email id
    if (publicKey == null || publicKey == '') {
      // todo: neeraj replace this as per the design where a new screen
      // is used for error. Do this change along with handling of network errors
      if (!context.mounted) return false;
      await showInviteDialog(context, email);
      return false;
    } else {
      return true;
    }
  }

  // addEmailToCollection returns true if add operation was successful
  Future<bool> addEmailToCollection(
    BuildContext context,
    Collection collection,
    String email,
    CollectionParticipantRole role, {
    bool showProgress = false,
  }) async {
    if (!isValidEmail(email)) {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).invalidEmailAddress,
        AppLocalizations.of(context).enterValidEmail,
      );
      return false;
    } else if (email.trim() == Configuration.instance.getEmail()) {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).oops,
        AppLocalizations.of(context).youCannotShareWithYourself,
      );
      return false;
    }

    ProgressDialog? dialog;
    String? publicKey;
    if (showProgress) {
      dialog = createProgressDialog(
        context,
        AppLocalizations.of(context).sharing,
        isDismissible: true,
      );
      await dialog.show();
    }

    try {
      publicKey = await UserService.instance.getPublicKey(email);
    } catch (e) {
      await dialog?.hide();
      logger.severe("Failed to get public key", e);
      if (!context.mounted) return false;
      await showGenericErrorDialog(context: context, error: e);
      return false;
    }
    // getPublicKey can return null when no user is associated with given
    // email id
    if (publicKey == null || publicKey == '') {
      // todo: neeraj replace this as per the design where a new screen
      // is used for error. Do this change along with handling of network errors
      if (!context.mounted) return false;
      await showDialogWidget(
        context: context,
        title: AppLocalizations.of(context).inviteToEnte,
        icon: Icons.info_outline,
        body: AppLocalizations.of(context).emailNoEnteAccount(email: email),
        isDismissible: true,
        buttons: [
          ButtonWidget(
            buttonType: ButtonType.neutral,
            icon: Icons.adaptive.share,
            labelText: AppLocalizations.of(context).sendInvite,
            isInAlert: true,
            onTap: () async {
              unawaited(
                shareText(
                  AppLocalizations.of(context).shareTextRecommendUsingEnte,
                ),
              );
            },
          ),
        ],
      );
      return false;
    } else {
      try {
        final newSharees = await CollectionsService.instance.share(
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
        if (e is SharingNotPermittedForFreeAccountsError) {
          if (!context.mounted) return false;
          await _showUnSupportedAlert(context);
        } else {
          logger.severe("failed to share collection", e);
          if (!context.mounted) return false;
          await showGenericErrorDialog(context: context, error: e);
        }
        return false;
      }
    }
  }

  Future<bool> deleteMultipleCollectionSheet(
    BuildContext context,
    List<Collection> collections,
  ) async {
    return _showDeleteCollectionConfirmationSheet(
      context: context,
      title: AppLocalizations.of(context).deleteMultipleAlbumsQuestion,
      message: AppLocalizations.of(
        context,
      ).deleteMultipleAlbumDialog(count: collections.length),
      keepPhotos: () async {
        for (final collection in collections) {
          try {
            await trashCollectionKeepingPhotos(collection);
          } catch (e, s) {
            logger.severe("Failed to keep photos & delete collection", e, s);
            rethrow;
          }
        }
      },
      deletePhotos: () async {
        for (final collection in collections) {
          try {
            await collectionsService.trashNonEmptyCollection(collection);
          } catch (e) {
            logger.severe("Failed to delete collection", e);
            rethrow;
          }
        }
      },
    );
  }

  // deleteCollectionSheet returns true if the album is successfully deleted
  Future<bool> deleteCollectionSheet(
    BuildContext bContext,
    Collection collection,
  ) async {
    final currentUserID = Configuration.instance.getUserID()!;
    if (collection.owner.id != currentUserID) {
      throw AssertionError("Can not delete album owned by others");
    }
    if (collection.hasSharees) {
      final bool confirmDelete = await _confirmSharedAlbumDeletion(
        bContext,
        collection,
      );
      if (!confirmDelete) {
        return false;
      }
    }
    if (!bContext.mounted) return false;
    return _showDeleteCollectionConfirmationSheet(
      context: bContext,
      title: AppLocalizations.of(bContext).deleteAlbumQuestion,
      message: AppLocalizations.of(bContext).deleteAlbumDialog,
      keepPhotos: () async {
        try {
          await trashCollectionKeepingPhotos(collection);
        } catch (e, s) {
          logger.severe("Failed to keep photos & delete collection", e, s);
          rethrow;
        }
      },
      deletePhotos: () async {
        try {
          await collectionsService.trashNonEmptyCollection(collection);
        } catch (e) {
          logger.severe("Failed to delete collection", e);
          rethrow;
        }
      },
    );
  }

  Future<bool> _showDeleteCollectionConfirmationSheet({
    required BuildContext context,
    required String title,
    required String message,
    required Future<void> Function() keepPhotos,
    required Future<void> Function() deletePhotos,
  }) async {
    final l10n = AppLocalizations.of(context);
    final actionResult = await showBottomSheetComponent<ButtonResult>(
      context: context,
      builder: (sheetContext) {
        final colors = sheetContext.componentColors;
        return BottomSheetComponent(
          title: title,
          illustration: Image.asset("assets/warning-grey.png"),
          closeTooltip: l10n.close,
          closeResult: ButtonResult(ButtonAction.third),
          content: StyledText(
            text: message,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(color: colors.textLight),
            tags: {
              'bold': StyledTextTag(
                style: TextStyles.body.copyWith(color: colors.textBase),
              ),
            },
          ),
          actions: [
            ButtonComponent(
              label: l10n.keepPhotos,
              variant: ButtonComponentVariant.neutral,
              onTap: () => _runCollectionAction(
                sheetContext,
                ButtonAction.first,
                keepPhotos,
              ),
            ),
            ButtonComponent(
              label: l10n.deletePhotos,
              variant: ButtonComponentVariant.critical,
              onTap: () => _runCollectionAction(
                sheetContext,
                ButtonAction.second,
                deletePhotos,
              ),
            ),
          ],
        );
      },
    );
    if (actionResult?.action != null &&
        actionResult!.action == ButtonAction.error) {
      if (!context.mounted) return false;
      await showGenericErrorDialog(
        context: context,
        error: actionResult.exception,
      );
      return false;
    }
    if ((actionResult?.action != null) &&
        (actionResult!.action == ButtonAction.first ||
            actionResult.action == ButtonAction.second)) {
      return true;
    }
    return false;
  }

  Future<void> _runCollectionAction(
    BuildContext context,
    ButtonAction action,
    Future<void> Function() callback,
  ) async {
    try {
      await callback();
      if (context.mounted) {
        Navigator.of(context).pop(ButtonResult(action));
      }
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

  Future<void> trashCollectionKeepingPhotos(Collection collection) async {
    final List<EnteFile> files = await FilesDB.instance.getAllFilesCollection(
      collection.id,
    );
    await moveFilesFromCurrentCollection(
      null,
      collection,
      files,
      isHidden: collection.isHidden() && !collection.isDefaultHidden(),
    );
    // collection should be empty on server now
    await collectionsService.trashEmptyCollection(collection);
  }

  Future<void> removeFromUncatIfPresentInOtherAlbum(
    Collection collection,
    BuildContext bContext,
  ) async {
    try {
      final List<EnteFile> files = await FilesDB.instance.getAllFilesCollection(
        collection.id,
      );
      if (!bContext.mounted) return;
      await moveFilesFromCurrentCollection(bContext, collection, files);
    } catch (e) {
      logger.severe("Failed to remove files from uncategorized", e);
      if (!bContext.mounted) return;
      await showErrorDialogForException(
        context: bContext,
        exception: e as Exception,
      );
    }
  }

  // _confirmSharedAlbumDeletion should be shown when user tries to delete an
  // album shared with other ente users.
  Future<bool> _confirmSharedAlbumDeletion(
    BuildContext context,
    Collection collection,
  ) async {
    final actionResult = await showChoiceActionSheet(
      context,
      isCritical: true,
      title: AppLocalizations.of(context).deleteSharedAlbum,
      firstButtonLabel: AppLocalizations.of(context).deleteAlbum,
      body: AppLocalizations.of(context).deleteSharedAlbumDialogBody,
    );
    return actionResult?.action != null &&
        actionResult!.action == ButtonAction.first;
  }

  /*
  _moveFilesFromCurrentCollection removes the file from the current
  collection. Based on the file and collection ownership, files will be
  either moved to different collection (Case A). or will just get removed
  from current collection (Case B).
  -------------------------------
  Case A: Files and collection belong to the same user. Such files
  will be moved to a collection which belongs to the user and removed from
  the current collection as part of move operation.
  Note: Even files are present in the
  destination collection, we need to make move API call on the server
  so that the files are removed from current collection and are actually
  moved to a collection owned by the user.
  -------------------------------
  Case B: Owner of files and collections are different. In such cases,
  we will just remove (not move) the files from the given collection.
  */
  Future<void> moveFilesFromCurrentCollection(
    BuildContext? context,
    Collection collection,
    Iterable<EnteFile> files, {
    bool isHidden = false,
  }) async {
    final int currentUserID = Configuration.instance.getUserID()!;
    final isCollectionOwner = collection.owner.id == currentUserID;
    final bool canRemoveAllParticipants = collectionsService
        .canRemoveFilesFromAllParticipants(collection);
    final bool isCollectionAdmin =
        canRemoveAllParticipants && !isCollectionOwner;
    final FilesSplit split = FilesSplit.split(
      files,
      Configuration.instance.getUserID()!,
    );
    if (isCollectionAdmin) {
      final filesToRemove = <EnteFile>[
        ...split.ownedByCurrentUser,
        ...split.ownedByOtherUsers,
      ];
      if (filesToRemove.isNotEmpty) {
        await collectionsService.removeFromCollection(
          collection.id,
          filesToRemove,
        );
      }
      return;
    }
    if (isCollectionOwner && split.ownedByOtherUsers.isNotEmpty) {
      await collectionsService.removeFromCollection(
        collection.id,
        split.ownedByOtherUsers,
      );
    } else if (!isCollectionOwner && split.ownedByCurrentUser.isNotEmpty) {
      // collection is not owned by the user, just remove files owned
      // by current user and return
      await collectionsService.removeFromCollection(
        collection.id,
        split.ownedByCurrentUser,
      );
      return;
    }

    if (!isCollectionOwner && split.ownedByOtherUsers.isNotEmpty) {
      if (context != null && context.mounted) {
        showShortToast(
          context,
          AppLocalizations.of(context).canOnlyRemoveFilesOwnedByYou,
        );
      }
      return;
    }

    // pendingAssignMap keeps a track of files which are yet to be assigned to
    // to destination collection.
    final Map<int, EnteFile> pendingAssignMap = {};
    // destCollectionToFilesMap contains the destination collection and
    // files entry which needs to be moved in destination.
    // After the end of mapping logic, the number of files entries in
    // pendingAssignMap should be equal to files in destCollectionToFilesMap
    final Map<int, List<EnteFile>> destCollectionToFilesMap = {};
    final List<int> uploadedIDs = [];
    for (EnteFile f in split.ownedByCurrentUser) {
      if (f.uploadedFileID != null) {
        pendingAssignMap[f.uploadedFileID!] = f;
        uploadedIDs.add(f.uploadedFileID!);
      }
    }

    final Map<int, List<EnteFile>> collectionToFilesMap = await FilesDB.instance
        .getAllFilesGroupByCollectionID(uploadedIDs);

    // Fix files in pendingAssignMap with correct collectionID entries.
    // This is needed when files are selected after filtering by another album,
    // as the file's collectionID might point to the filtered album instead of
    // the current collection.
    final filesInCurrentCollection = collectionToFilesMap[collection.id];
    if (filesInCurrentCollection != null) {
      for (final file in filesInCurrentCollection) {
        if (file.uploadedFileID != null &&
            pendingAssignMap.containsKey(file.uploadedFileID) &&
            file.ownerID == currentUserID) {
          pendingAssignMap[file.uploadedFileID!] = file;
        }
      }
    }

    // Find and map the files from current collection to to entries in other
    // collections. This mapping is done to avoid moving all the files to
    // uncategorized during remove from album.
    for (MapEntry<int, List<EnteFile>> entry in collectionToFilesMap.entries) {
      if (!_isAutoMoveCandidate(collection.id, entry.key, currentUserID)) {
        continue;
      }
      final targetCollection = collectionsService.getCollectionByID(entry.key)!;
      // for each file which already exist in the destination collection
      // add entries in the moveDestCollectionToFiles map
      for (EnteFile file in entry.value) {
        // Check if the uploaded file is still waiting to be mapped
        if (pendingAssignMap.containsKey(file.uploadedFileID)) {
          if (!destCollectionToFilesMap.containsKey(targetCollection.id)) {
            destCollectionToFilesMap[targetCollection.id] = <EnteFile>[];
          }
          destCollectionToFilesMap[targetCollection.id]!.add(
            pendingAssignMap[file.uploadedFileID!]!,
          );
          pendingAssignMap.remove(file.uploadedFileID);
        }
      }
    }
    // Move the remaining files to uncategorized collection
    if (pendingAssignMap.isNotEmpty) {
      late final int toCollectionID;
      if (isHidden) {
        toCollectionID = collectionsService.cachedDefaultHiddenCollection!.id;
      } else {
        final Collection uncategorizedCollection = await collectionsService
            .getUncategorizedCollection();
        toCollectionID = uncategorizedCollection.id;
      }

      for (MapEntry<int, EnteFile> entry in pendingAssignMap.entries) {
        final file = entry.value;
        if (pendingAssignMap.containsKey(file.uploadedFileID)) {
          if (!destCollectionToFilesMap.containsKey(toCollectionID)) {
            destCollectionToFilesMap[toCollectionID] = <EnteFile>[];
          }
          destCollectionToFilesMap[toCollectionID]!.add(
            pendingAssignMap[file.uploadedFileID!]!,
          );
        }
      }
    }

    // Verify that all files are mapped.
    int mappedFilesCount = 0;
    destCollectionToFilesMap.forEach((key, value) {
      mappedFilesCount += value.length;
    });
    if (mappedFilesCount != uploadedIDs.length) {
      throw AssertionError(
        "Failed to map all files toMap: ${uploadedIDs.length} and mapped "
        "$mappedFilesCount",
      );
    }

    for (MapEntry<int, List<EnteFile>> entry
        in destCollectionToFilesMap.entries) {
      if (collection.type == CollectionType.uncategorized &&
          entry.key == collection.id) {
        // skip moving files to uncategorized collection from uncategorized
        // this flow is triggered while cleaning up uncategerized collection
        logger.info(
          'skipping moving ${entry.value.length} files to uncategorized collection',
        );
      } else {
        await collectionsService.move(
          entry.value,
          toCollectionID: entry.key,
          fromCollectionID: collection.id,
        );
      }
    }
  }

  // This method returns true if the given destination collection is a good
  // target to moving files during file remove or delete collection but keey
  // photos action. Uncategorized or favorite type of collections are not
  // good auto-move candidates. Uncategorized will be fall back for all files
  // which could not be mapped to a potential target collection
  bool _isAutoMoveCandidate(int fromCollectionID, toCollectionID, int userID) {
    if (fromCollectionID == toCollectionID) {
      return false;
    }
    final Collection? targetCollection = collectionsService.getCollectionByID(
      toCollectionID,
    );
    // ignore non-cached, deleted, uncategorized and favorite collections,
    // and collections ignored by others
    if (targetCollection == null ||
        targetCollection.isDeleted ||
        (CollectionType.uncategorized == targetCollection.type ||
            targetCollection.type == CollectionType.favorites) ||
        targetCollection.owner.id != userID) {
      return false;
    }
    return true;
  }

  Future<void> _showUnSupportedAlert(BuildContext context) async {
    final AlertDialog alert = AlertDialog(
      title: Text(AppLocalizations.of(context).sorry),
      content: Text(AppLocalizations.of(context).subscribeToEnableSharing),
      actions: [
        ButtonWidget(
          buttonType: ButtonType.primary,
          isInAlert: true,
          shouldStickToDarkTheme: false,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          labelText: AppLocalizations.of(context).subscribe,
          onTap: () async {
            // for quickLink collection, we need to trash the collection
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (BuildContext context) {
                      return getSubscriptionPage();
                    },
                  ),
                )
                .ignore();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: ButtonWidget(
            buttonType: ButtonType.secondary,
            buttonAction: ButtonAction.cancel,
            isInAlert: true,
            shouldStickToDarkTheme: false,
            labelText: AppLocalizations.of(context).ok,
          ),
        ),
      ],
    );

    return showDialog(
      useRootNavigator: false,
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
      barrierDismissible: true,
    );
  }
}
