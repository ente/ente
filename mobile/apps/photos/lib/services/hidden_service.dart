import "dart:async";
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import 'package:photos/core/event_bus.dart';
import "package:photos/db/files_db.dart";
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/gateways/collections/models/create_request.dart';
import "package:photos/gateways/collections/models/metadata.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/action.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/common_keys.dart";
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

/// Represents a file that needs to be cleaned up from a non-hidden collection.
class HiddenCleanupItem {
  final EnteFile file;
  final int nonHiddenCollectionID;
  final int hiddenCollectionID;

  HiddenCleanupItem({
    required this.file,
    required this.nonHiddenCollectionID,
    required this.hiddenCollectionID,
  });

  bool get isNonHiddenCollectionOwnedByUser {
    final userID = Configuration.instance.getUserID()!;
    final collection = CollectionsService.instance.getCollectionByID(
      nonHiddenCollectionID,
    );
    return collection?.isOwner(userID) ?? false;
  }

  bool get isHiddenCollectionOwnedByUser {
    final userID = Configuration.instance.getUserID()!;
    final collection = CollectionsService.instance.getCollectionByID(
      hiddenCollectionID,
    );
    return collection?.isOwner(userID) ?? false;
  }

  /// Returns true if this item should be acted upon (cleaned up).
  /// An item is actionable if the user owns the non-hidden collection.
  bool get isActionable => isNonHiddenCollectionOwnedByUser;

  /// Returns the collection ID to move from.
  int get fromCollectionID => nonHiddenCollectionID;

  /// Returns the collection ID to move to.
  /// Uses the original hidden collection if owned by user,
  /// otherwise uses the user's default hidden collection.
  int get toCollectionID {
    if (isHiddenCollectionOwnedByUser) {
      return hiddenCollectionID;
    }
    return CollectionsService.instance.cachedDefaultHiddenCollection!.id;
  }
}

extension HiddenService on CollectionsService {
  static final _logger = Logger("HiddenCollectionService");

  Future<Collection> getDefaultHiddenCollection() async {
    Collection? defaultHidden;
    if (cachedDefaultHiddenCollection != null) {
      return cachedDefaultHiddenCollection!;
    }
    final int userID = config.getUserID()!;
    final allDefaultHidden = collectionIDToCollections.values
        .where(
          (element) => element.isDefaultHidden() && element.owner.id == userID,
        )
        .toList();

    if (allDefaultHidden.length > 1) {
      defaultHidden = await clubAllDefaultHiddenToOne(allDefaultHidden);
    } else if (allDefaultHidden.length == 1) {
      defaultHidden = allDefaultHidden.first;
    }

    if (defaultHidden != null) {
      cachedDefaultHiddenCollection = defaultHidden;
      return cachedDefaultHiddenCollection!;
    }

    final Collection createdHiddenCollection =
        await _createDefaultHiddenAlbum();
    cachedDefaultHiddenCollection = createdHiddenCollection;
    return cachedDefaultHiddenCollection!;
  }

  Future<Collection> clubAllDefaultHiddenToOne(
    List<Collection> allDefaultHidden,
  ) async {
    // select first collection as default hidden where all files will be clubbed
    final Collection defaultHidden = allDefaultHidden.first;
    for (Collection hidden in allDefaultHidden) {
      try {
        if (hidden.id == defaultHidden.id) {
          continue;
        }
        final filesInCollection = (await FilesDB.instance.getFilesInCollection(
          hidden.id,
          galleryLoadStartTime,
          galleryLoadEndTime,
        )).files;
        await move(
          filesInCollection,
          toCollectionID: defaultHidden.id,
          fromCollectionID: hidden.id,
        );
        await CollectionsService.instance.trashEmptyCollection(hidden);
      } catch (e, s) {
        _logger.severe(
          "One iteration of clubbing all default hidden failed",
          e,
          s,
        );
        continue;
      }
    }

    return defaultHidden;
  }

  // getUncategorizedCollection will return the uncategorized collection
  // for the given user
  Future<Collection> getUncategorizedCollection() async {
    if (cachedUncategorizedCollection != null) {
      return cachedUncategorizedCollection!;
    }
    final int userID = config.getUserID()!;
    final Collection? matchedCollection = collectionIDToCollections.values
        .firstWhereOrNull(
          (element) =>
              element.type == CollectionType.uncategorized &&
              element.owner.id == userID,
        );
    if (matchedCollection != null) {
      cachedUncategorizedCollection = matchedCollection;
      return cachedUncategorizedCollection!;
    }
    return _createUncategorizedCollection();
  }

  Future<void> movePendingRemovalActionsToUncategorized() async {
    try {
      final pendingActions = await fetchPendingRemovalActions();
      if (pendingActions.isEmpty) {
        return;
      }

      final Map<int, Set<int>> collectionToFileIDs = {};
      for (final CollectionAction action in pendingActions) {
        final int? fileID = action.fileID;
        if (fileID == null) {
          continue;
        }
        collectionToFileIDs
            .putIfAbsent(action.collectionID, () => <int>{})
            .add(fileID);
      }

      if (collectionToFileIDs.isEmpty) {
        return;
      }

      final List<int> uploadedFileIDs = collectionToFileIDs.values
          .expand((ids) => ids)
          .toSet()
          .toList();
      final Map<int, List<EnteFile>> localFilesByCollection = await filesDB
          .getAllFilesGroupByCollectionID(uploadedFileIDs);
      final Collection uncategorizedCollection =
          await getUncategorizedCollection();

      for (final MapEntry<int, Set<int>> entry in collectionToFileIDs.entries) {
        final int collectionID = entry.key;
        final Set<int> pendingFileIDs = entry.value;
        final List<EnteFile> localFiles =
            localFilesByCollection[collectionID] ?? <EnteFile>[];
        final List<EnteFile> filesToMove = localFiles
            .where(
              (file) =>
                  file.uploadedFileID != null &&
                  pendingFileIDs.contains(file.uploadedFileID),
            )
            .toList();
        if (filesToMove.isEmpty) {
          continue;
        }

        // Determine destination: files from hidden collections go to default
        // hidden collection, others go to uncategorized
        final Collection? sourceCollection = getCollectionByID(collectionID);
        final bool isSourceHidden = sourceCollection?.isHidden() ?? false;
        final int destinationCollectionID;
        if (isSourceHidden) {
          final Collection defaultHiddenCollection =
              await getDefaultHiddenCollection();
          destinationCollectionID = defaultHiddenCollection.id;
        } else {
          destinationCollectionID = uncategorizedCollection.id;
        }

        await move(
          filesToMove,
          toCollectionID: destinationCollectionID,
          fromCollectionID: collectionID,
        );
      }
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to process pending collection removal actions",
        error,
        stackTrace,
      );
    }
  }

  Future<bool> hideFiles(
    BuildContext context,
    List<EnteFile> filesToHide, {
    bool forceHide = false,
  }) async {
    final int userID = config.getUserID()!;
    final List<int> uploadedIDs = <int>[];
    final dialog = createProgressDialog(context, "Hiding...");
    await dialog.show();
    try {
      for (EnteFile file in filesToHide) {
        if (file.uploadedFileID == null) {
          throw AssertionError("Can only hide uploaded files");
        }
        if (file.ownerID != userID) {
          throw AssertionError("Can only hide files owned by user");
        }
        uploadedIDs.add(file.uploadedFileID!);
      }

      final defaultHiddenCollection = await getDefaultHiddenCollection();
      final Map<int, List<EnteFile>> collectionToFilesMap = await filesDB
          .getAllFilesGroupByCollectionID(uploadedIDs);
      for (MapEntry<int, List<EnteFile>> entry
          in collectionToFilesMap.entries) {
        if (entry.key == defaultHiddenCollection.id) {
          _logger.info('file already part of hidden collection');
          continue;
        }
        final Collection? c = getCollectionByID(entry.key);
        // if the collection is not owned by the user, remove the file from the
        // collection
        if (c != null && !c.isOwner(userID)) {
          await removeFromCollection(entry.key, entry.value);
        } else {
          await move(
            entry.value,
            toCollectionID: defaultHiddenCollection.id,
            fromCollectionID: entry.key,
          );
        }
      }
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          filesToHide,
          type: EventType.hide,
          source: "hideFiles",
        ),
      );

      await dialog.hide();
    } on AssertionError catch (e) {
      await dialog.hide();
      if (!context.mounted) return false;
      unawaited(
        showErrorDialog(
          context,
          AppLocalizations.of(context).oops,
          e.message as String,
        ),
      );
      return false;
    } catch (e, s) {
      _logger.severe("Could not hide", e, s);
      await dialog.hide();
      if (!context.mounted) return false;
      await showGenericErrorDialog(context: context, error: e);
      return false;
    } finally {
      await dialog.hide();
    }
    return true;
  }

  Future<Collection> createHiddenAlbum(String name) async {
    final CreateRequest createRequest = await buildCollectionCreateRequest(
      name,
      visibility: hiddenVisibility,
      subType: 0,
    );
    _logger.info("Creating Hidden Collection");
    final collection = await createAndCacheCollection(createRequest);
    _logger.info("Creating Hidden Collection Created Successfully");
    final Collection collectionFromServer = await fetchCollectionByID(
      collection.id,
    );
    _logger.info("Fetched Created Hidden Collection Successfully");
    return collectionFromServer;
  }

  Future<Collection> _createDefaultHiddenAlbum() async {
    final CreateRequest createRequest = await buildCollectionCreateRequest(
      ".Hidden",
      visibility: hiddenVisibility,
      subType: subTypeDefaultHidden,
    );
    _logger.info("Creating Default Hidden Collection");
    final collection = await createAndCacheCollection(createRequest);
    _logger.info("Default Hidden Collection Created Successfully");
    final Collection collectionFromServer = await fetchCollectionByID(
      collection.id,
    );
    _logger.info("Fetched Created Default Hidden Collection Successfully");
    return collectionFromServer;
  }

  Future<Collection> _createUncategorizedCollection() async {
    final uncategorizedCollectionKey = CryptoUtil.generateKey();
    final encKey = CryptoUtil.encryptSync(
      uncategorizedCollectionKey,
      config.getKey()!,
    );
    final encName = CryptoUtil.encryptSync(
      utf8.encode("Uncategorized"),
      uncategorizedCollectionKey,
    );
    final collection = await createAndCacheCollection(
      CreateRequest(
        encryptedKey: CryptoUtil.bin2base64(encKey.encryptedData!),
        keyDecryptionNonce: CryptoUtil.bin2base64(encKey.nonce!),
        encryptedName: CryptoUtil.bin2base64(encName.encryptedData!),
        nameDecryptionNonce: CryptoUtil.bin2base64(encName.nonce!),
        type: CollectionType.uncategorized,
        attributes: CollectionAttributes(),
      ),
    );
    cachedUncategorizedCollection = collection;
    return cachedUncategorizedCollection!;
  }

  Future<CreateRequest> buildCollectionCreateRequest(
    String name, {
    required int visibility,
    required int subType,
  }) async {
    final collectionKey = CryptoUtil.generateKey();
    final encryptedKeyData = CryptoUtil.encryptSync(
      collectionKey,
      config.getKey()!,
    );
    final encryptedName = CryptoUtil.encryptSync(
      utf8.encode(name),
      collectionKey,
    );
    final jsonToUpdate = CollectionMagicMetadata(
      visibility: visibility,
      subType: subType,
    ).toJson();
    assert(jsonToUpdate.length == 2, "metadata should have two keys");
    final encryptedMMd = await CryptoUtil.encryptChaCha(
      utf8.encode(jsonEncode(jsonToUpdate)),
      collectionKey,
    );
    final MetadataRequest metadataRequest = MetadataRequest(
      version: 1,
      count: jsonToUpdate.length,
      data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
      header: CryptoUtil.bin2base64(encryptedMMd.header!),
    );
    final CreateRequest createRequest = CreateRequest(
      encryptedKey: CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
      keyDecryptionNonce: CryptoUtil.bin2base64(encryptedKeyData.nonce!),
      encryptedName: CryptoUtil.bin2base64(encryptedName.encryptedData!),
      nameDecryptionNonce: CryptoUtil.bin2base64(encryptedName.nonce!),
      type: CollectionType.album,
      attributes: CollectionAttributes(),
      magicMetadata: metadataRequest,
    );
    return createRequest;
  }

  /// Returns true if there are hidden files with local copies on device.
  /// Uses an efficient LIMIT 1 query instead of loading all files.
  Future<bool> hasHiddenFilesOnDevice() async {
    final userID = config.getUserID();
    if (userID == null) {
      return false;
    }
    final hiddenCollectionIds = getHiddenCollectionIds();
    if (hiddenCollectionIds.isEmpty) {
      return false;
    }
    return filesDB.hasHiddenFilesWithLocalCopy(hiddenCollectionIds, userID);
  }

  /// Gets hidden files that have local copies, deduplicated by uploadedFileID.
  /// Only returns files owned by the current user from any hidden collection
  /// (owned or shared).
  Future<List<EnteFile>> getHiddenFilesOnDevice() async {
    final userID = config.getUserID();
    if (userID == null) {
      return [];
    }
    final hiddenCollectionIds = getHiddenCollectionIds();
    if (hiddenCollectionIds.isEmpty) {
      return [];
    }
    return filesDB.getHiddenFilesWithLocalCopy(hiddenCollectionIds, userID);
  }

  /// Checks if there are hidden files that also exist in non-hidden collections.
  /// Only considers files owned by the user.
  Future<bool> hasFilesNeedingHiddenCleanup() async {
    final int userID = config.getUserID()!;
    final hiddenCollectionIds = getHiddenCollectionIds();
    if (hiddenCollectionIds.isEmpty) {
      return false;
    }

    final uploadedHiddenFileIds = await filesDB.getUploadedFileIDsInCollections(
      hiddenCollectionIds,
      ownerID: userID,
    );
    if (uploadedHiddenFileIds.isEmpty) {
      return false;
    }

    final allCollectionIdsHiddenFilesExistsIn = await filesDB
        .getCollectionIDsForUploadedFileIDs(uploadedHiddenFileIds);

    // Check if any collection is non-hidden
    for (final collectionId in allCollectionIdsHiddenFilesExistsIn) {
      if (hiddenCollectionIds.contains(collectionId)) {
        continue;
      }

      final collection = getCollectionByID(collectionId);
      if (collection != null && collection.isOwner(userID)) {
        return true;
      }
    }

    return false;
  }

  /// Gets the list of files that need to be cleaned up from non-hidden
  /// collections. Only processes files owned by the user.
  Future<List<HiddenCleanupItem>> getFilesNeedingHiddenCleanup() async {
    final int userID = config.getUserID()!;
    final hiddenCollectionIds = getHiddenCollectionIds();
    if (hiddenCollectionIds.isEmpty) {
      return [];
    }

    final uploadedHiddenFileIds = await filesDB.getUploadedFileIDsInCollections(
      hiddenCollectionIds,
      ownerID: userID,
    );
    if (uploadedHiddenFileIds.isEmpty) {
      return [];
    }

    final filesByCollectionID = await filesDB.getAllFilesGroupByCollectionID(
      uploadedHiddenFileIds,
    );

    // Build map of uploadedFileID -> hiddenCollectionID
    final Map<int, int> fileToHiddenCollection = {};
    for (final entry in filesByCollectionID.entries) {
      final collectionID = entry.key;
      if (hiddenCollectionIds.contains(collectionID)) {
        for (final file in entry.value) {
          if (file.uploadedFileID != null) {
            // Store first hidden collection found for each file
            fileToHiddenCollection.putIfAbsent(
              file.uploadedFileID!,
              () => collectionID,
            );
          }
        }
      }
    }

    // Create cleanup items for non-hidden collections
    final cleanupItems = <HiddenCleanupItem>[];
    for (final entry in filesByCollectionID.entries) {
      final collectionID = entry.key;

      if (hiddenCollectionIds.contains(collectionID)) {
        continue;
      }

      final collection = getCollectionByID(collectionID);
      if (collection == null) {
        continue;
      }

      for (final file in entry.value) {
        // Files are already filtered by ownerID at DB level, but double-check
        if (file.ownerID != userID) {
          continue;
        }

        final hiddenCollectionID = fileToHiddenCollection[file.uploadedFileID];
        if (hiddenCollectionID == null) {
          continue; // Shouldn't happen
        }

        cleanupItems.add(
          HiddenCleanupItem(
            file: file,
            nonHiddenCollectionID: collectionID,
            hiddenCollectionID: hiddenCollectionID,
          ),
        );
      }
    }

    return cleanupItems;
  }

  /// Cleans up hidden files by moving them from non-hidden collections to their
  /// hidden collection.
  /// Only own files are processed.
  /// For files whose hidden collection is owned by the user,
  /// they are moved back to their original hidden collection.
  /// For files whose hidden collection is not owned by the user,
  /// they are moved to the user's default hidden collection.
  Future<void> cleanupHiddenFiles(BuildContext context) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
    await dialog.show();

    try {
      final cleanupItems = await getFilesNeedingHiddenCleanup();

      if (cleanupItems.isEmpty) {
        await dialog.hide();
        return;
      }

      final actionableItems = cleanupItems
          .where((item) => item.isActionable)
          .toList();
      final nonActionableItems = cleanupItems
          .where((item) => !item.isActionable)
          .toList();

      for (final item in nonActionableItems) {
        _logger.info(
          "Should not clean up file ${item.file.uploadedFileID} from collection "
          "${item.nonHiddenCollectionID} - user doesn't own the collection",
        );
      }

      // Group actionable items by (fromCollectionID, toCollectionID) for batch moves
      final Map<(int, int), List<EnteFile>> moveGroups = {};
      for (final item in actionableItems) {
        final key = (item.fromCollectionID, item.toCollectionID);
        moveGroups.putIfAbsent(key, () => []).add(item.file);
      }

      // Execute moves
      for (final entry in moveGroups.entries) {
        final (fromCollectionID, toCollectionID) = entry.key;
        final files = entry.value;

        await move(
          files,
          toCollectionID: toCollectionID,
          fromCollectionID: fromCollectionID,
        );
      }

      // Fire events for UI refresh
      final allMovedFiles = actionableItems.map((e) => e.file).toList();
      if (allMovedFiles.isNotEmpty) {
        Bus.instance.fire(
          FilesUpdatedEvent(allMovedFiles, source: "hiddenCleanup"),
        );
      }

      await dialog.hide();
      if (!context.mounted) return;
      showShortToast(context, AppLocalizations.of(context).cleanupComplete);
    } catch (e, s) {
      _logger.severe("Failed to cleanup hidden files", e, s);
      await dialog.hide();
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }
}
