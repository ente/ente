import "dart:async";

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart' hide isValidEmail;
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/core/errors.dart";
import "package:photos/core/network/api_response.dart";
import 'package:photos/db/files_db.dart';
import 'package:photos/gateways/collections/models/create_request.dart';
import 'package:photos/models/button_result.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/files_split.dart';
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/common_keys.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/hidden_service.dart';
import 'package:photos/ui/components/action_sheet_widget.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/ui/sharing/widgets/sharing_role.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/email_util.dart';
import 'package:photos/utils/share_util.dart';
import "package:styled_text/styled_text.dart";

enum AddEmailToCollectionFailure {
  invalidEmail,
  currentUser,
  noAccount,
  sharingNotPermitted,
  other,
}

class AddEmailToCollectionResult {
  const AddEmailToCollectionResult.success()
    : failure = null,
      error = null,
      email = "";

  const AddEmailToCollectionResult.failure({
    required this.failure,
    required this.email,
    this.error,
  });

  final AddEmailToCollectionFailure? failure;
  final Object? error;
  final String email;

  bool get succeeded => failure == null;
}

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
          labelText: context.strings.yesRemove,
          onTap: () async {
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
          labelText: context.strings.cancel,
        ),
      ],
      title: context.strings.removePublicLink,
      body: context.strings.disableLinkMessage(
        albumName: collection.displayName,
      ),
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

  Future<AddEmailToCollectionResult> addEmailsToCollections(
    List<Collection> collections,
    Set<String> emails,
    CollectionParticipantRole role,
  ) async {
    final ownEmail = Configuration.instance.getEmail()?.trim().toLowerCase();
    for (final email in emails) {
      if (!isValidEmail(email)) {
        return AddEmailToCollectionResult.failure(
          failure: AddEmailToCollectionFailure.invalidEmail,
          email: email,
        );
      }
      if (email == ownEmail) {
        return AddEmailToCollectionResult.failure(
          failure: AddEmailToCollectionFailure.currentUser,
          email: email,
        );
      }
    }

    try {
      final keys = await UserService.instance.getPublicKeys(emails);
      final publicKeys = <String, String>{};
      for (final entry in keys.entries) {
        final publicKey = entry.value;
        if (publicKey == null || publicKey.isEmpty) {
          return AddEmailToCollectionResult.failure(
            failure: AddEmailToCollectionFailure.noAccount,
            email: entry.key,
          );
        }
        publicKeys[entry.key] = publicKey;
      }
      for (final collection in collections) {
        final collectionPublicKeys = {
          for (final entry in publicKeys.entries)
            if (collectionNeedsShare(collection, entry.key))
              entry.key: entry.value,
        };
        if (collectionPublicKeys.isEmpty) continue;
        final sharees = await collectionsService.shareBatch(
          collection.id,
          collectionPublicKeys,
          role,
        );
        collection.updateSharees(sharees);
      }
      return const AddEmailToCollectionResult.success();
    } catch (e) {
      if (e is UnexpectedApiResponseException &&
          e.response?.statusCode == 404) {
        AddEmailToCollectionResult? firstFailure;
        for (final collection in collections) {
          for (final email in emails) {
            if (!collectionNeedsShare(collection, email)) continue;
            final result = await addEmailToCollection(collection, email, role);
            if (!result.succeeded) firstFailure ??= result;
          }
        }
        return firstFailure ?? const AddEmailToCollectionResult.success();
      }
      logger.severe("Failed to share collections", e);
      return AddEmailToCollectionResult.failure(
        failure: e is SharingNotPermittedForFreeAccountsError
            ? AddEmailToCollectionFailure.sharingNotPermitted
            : AddEmailToCollectionFailure.other,
        email: emails.first,
        error: e,
      );
    }
  }

  Future<AddEmailToCollectionResult> addEmailToCollection(
    Collection collection,
    String email,
    CollectionParticipantRole role,
  ) async {
    if (!isValidEmail(email)) {
      return AddEmailToCollectionResult.failure(
        failure: AddEmailToCollectionFailure.invalidEmail,
        email: email,
      );
    } else if (email.trim() == Configuration.instance.getEmail()) {
      return AddEmailToCollectionResult.failure(
        failure: AddEmailToCollectionFailure.currentUser,
        email: email,
      );
    }
    String? publicKey;
    try {
      publicKey = await UserService.instance.getPublicKey(email);
    } catch (e) {
      logger.severe("Failed to get public key", e);
      return AddEmailToCollectionResult.failure(
        failure: AddEmailToCollectionFailure.other,
        email: email,
        error: e,
      );
    }
    if (publicKey == null || publicKey == '') {
      return AddEmailToCollectionResult.failure(
        failure: AddEmailToCollectionFailure.noAccount,
        email: email,
      );
    }
    try {
      final newSharees = await collectionsService.share(
        collection.id,
        email,
        publicKey,
        role,
      );
      collection.updateSharees(newSharees);
      return const AddEmailToCollectionResult.success();
    } catch (e) {
      if (e is SharingNotPermittedForFreeAccountsError) {
        return AddEmailToCollectionResult.failure(
          failure: AddEmailToCollectionFailure.sharingNotPermitted,
          email: email,
          error: e,
        );
      }
      logger.severe("failed to share collection", e);
      return AddEmailToCollectionResult.failure(
        failure: AddEmailToCollectionFailure.other,
        email: email,
        error: e,
      );
    }
  }

  Future<void> showAddEmailToCollectionFailure(
    BuildContext context,
    AddEmailToCollectionResult result,
  ) async {
    switch (result.failure) {
      case AddEmailToCollectionFailure.invalidEmail:
        await showErrorDialog(
          context,
          context.strings.invalidEmailAddress,
          context.strings.enterValidEmail,
        );
      case AddEmailToCollectionFailure.currentUser:
        await showErrorDialog(
          context,
          context.strings.oops,
          context.strings.youCannotShareWithYourself,
        );
      case AddEmailToCollectionFailure.noAccount:
        await showBottomSheetComponent<void>(
          context: context,
          builder: (sheetContext) => BottomSheetComponent(
            title: context.strings.inviteToEnte,
            message: context.strings.emailNoEnteAccountPhotos(
              email: result.email,
            ),
            illustration: Image.asset("assets/warning-grey.png"),
            closeTooltip: context.strings.close,
            actions: [
              ButtonComponent(
                label: context.strings.sendInvite,
                variant: ButtonComponentVariant.neutral,
                leading: Icon(Icons.adaptive.share),
                shouldSurfaceExecutionStates: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(
                    shareText(
                      context.strings.shareTextRecommendUsingEnteForPhotos,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      case AddEmailToCollectionFailure.sharingNotPermitted:
        await _showUnSupportedAlert(context);
      case AddEmailToCollectionFailure.other:
        await showGenericErrorDialog(context: context, error: result.error);
      case null:
        return;
    }
  }

  Future<bool> deleteMultipleCollectionSheet(
    BuildContext context,
    List<Collection> collections,
  ) async {
    return _showDeleteCollectionConfirmationSheet(
      context: context,
      title: context.strings.deleteMultipleAlbumsQuestion,
      message: context.strings.deleteMultipleAlbumDialog(
        count: collections.length,
      ),
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
      title: bContext.strings.deleteAlbumQuestion,
      message: bContext.strings.deleteAlbumDialog,
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
    final l10n = context.strings;
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
    await collectionsService.trashEmptyCollection(collection);
  }

  Future<int> removeFromUncatIfPresentInOtherAlbum(
    Collection collection,
    BuildContext bContext,
  ) async {
    try {
      final List<EnteFile> files = await FilesDB.instance.getAllFilesCollection(
        collection.id,
      );
      if (!bContext.mounted) {
        return 0;
      }
      return await moveFilesFromCurrentCollection(bContext, collection, files);
    } catch (e, s) {
      logger.severe("Failed to remove files from uncategorized", e, s);
      rethrow;
    }
  }

  Future<bool> _confirmSharedAlbumDeletion(
    BuildContext context,
    Collection collection,
  ) async {
    final actionResult = await showChoiceActionSheet(
      context,
      isCritical: true,
      title: context.strings.deleteSharedAlbum,
      firstButtonLabel: context.strings.deleteAlbum,
      body: context.strings.deleteSharedAlbumDialogBody,
    );
    return actionResult?.action != null &&
        actionResult!.action == ButtonAction.first;
  }

  // Moving an owned file must call the move API even if it is already in
  // another owned collection, because move also removes it from this one.
  // Files owned by someone else can only be removed from this collection.
  Future<int> moveFilesFromCurrentCollection(
    BuildContext? context,
    Collection collection,
    Iterable<EnteFile> files, {
    bool isHidden = false,
  }) async {
    var movedFilesCount = 0;
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
      return filesToRemove.length;
    }
    if (isCollectionOwner && split.ownedByOtherUsers.isNotEmpty) {
      await collectionsService.removeFromCollection(
        collection.id,
        split.ownedByOtherUsers,
      );
      movedFilesCount += split.ownedByOtherUsers.length;
    } else if (!isCollectionOwner && split.ownedByCurrentUser.isNotEmpty) {
      await collectionsService.removeFromCollection(
        collection.id,
        split.ownedByCurrentUser,
      );
      return split.ownedByCurrentUser.length;
    }

    if (!isCollectionOwner && split.ownedByOtherUsers.isNotEmpty) {
      if (context != null && context.mounted) {
        showShortToast(context, context.strings.canOnlyRemoveFilesOwnedByYou);
      }
      return movedFilesCount;
    }

    final Map<int, EnteFile> pendingAssignMap = {};
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

    // Preserve another album membership instead of moving to Uncategorized.
    for (MapEntry<int, List<EnteFile>> entry in collectionToFilesMap.entries) {
      if (!_isAutoMoveCandidate(collection.id, entry.key, currentUserID)) {
        continue;
      }
      final targetCollection = collectionsService.getCollectionByID(entry.key)!;
      for (EnteFile file in entry.value) {
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
        logger.info(
          'skipping moving ${entry.value.length} files to uncategorized collection',
        );
      } else {
        final movedFilesInCollection = entry.value.length;
        await collectionsService.move(
          entry.value,
          toCollectionID: entry.key,
          fromCollectionID: collection.id,
        );
        movedFilesCount += movedFilesInCollection;
      }
    }
    return movedFilesCount;
  }

  bool _isAutoMoveCandidate(int fromCollectionID, toCollectionID, int userID) {
    if (fromCollectionID == toCollectionID) {
      return false;
    }
    final Collection? targetCollection = collectionsService.getCollectionByID(
      toCollectionID,
    );
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
      title: Text(context.strings.sorry),
      content: Text(context.strings.subscribeToEnableSharing),
      actions: [
        ButtonWidget(
          buttonType: ButtonType.primary,
          isInAlert: true,
          shouldStickToDarkTheme: false,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          labelText: context.strings.subscribe,
          onTap: () async {
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
            labelText: context.strings.ok,
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
