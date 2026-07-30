import 'dart:async';
import "dart:math";
import 'dart:typed_data';

import "package:ente_accounts/services/user_service.dart";
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_in_event.dart';
import "package:ente_events/models/trigger_logout_event.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:fast_base58/fast_base58.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import 'package:locker/core/errors.dart';
import 'package:locker/events/collections_updated_event.dart';
import 'package:locker/events/user_details_refresh_event.dart';
import 'package:locker/l10n/l10n.dart';
import "package:locker/services/collections/collections_api_client.dart";
import 'package:locker/services/collections/models/collection.dart';
import "package:locker/services/collections/models/files_split.dart";
import "package:locker/services/collections/models/public_url.dart";
import 'package:locker/services/configuration.dart';
import "package:locker/services/db/locker_db.dart";
import 'package:locker/services/files/offline/offline_files_service.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/trash/models/trash_item_request.dart';
import "package:locker/services/trash/trash_service.dart";
import "package:locker/utils/collection_list_util.dart";
import "package:locker/utils/crypto_helper.dart";
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CollectionService {
  static final CollectionService instance =
      CollectionService._privateConstructor();

  // Fixed set of suggested collection names
  static const Set<String> _suggestedCollectionNames = {
    'Personal',
    'Work',
    'Travel',
    'Family',
    'Projects',
    'School',
    'Music',
    'Books',
    'Events',
    'Holidays',
  };

  final _logger = Logger("CollectionService");

  late CollectionApiClient _apiClient;
  late LockerDB _db;

  final _collectionIDToCollections = <int, Collection>{};

  static const String _firstSyncCompletedPrefKey = 'first_sync_completed';
  late SharedPreferences _prefs;
  Future<void>? _defaultSetupInFlight;

  CollectionService._privateConstructor();

  Future<void> init(SharedPreferences preferences) async {
    _db = LockerDB.instance;
    _apiClient = CollectionApiClient.instance;
    _prefs = preferences;

    Bus.instance.on<SignedInEvent>().listen((event) async {
      _logger.info("User signed in, starting initial sync.");
      await _init();
    });

    if (Configuration.instance.hasConfiguredAccount()) {
      await _init();
    }
  }

  Future<void> sync() async {
    final previousSyncTime = _db.getSyncTime();
    final shouldCheckFirstSyncCompletion = previousSyncTime == 0;

    final updatedCollections = await CollectionApiClient.instance
        .getCollections(previousSyncTime);
    if (updatedCollections.isEmpty) {
      if (shouldCheckFirstSyncCompletion) {
        final didMarkFirstSync = await _setFirstSyncCompleted();
        if (didMarkFirstSync) {
          Bus.instance.fire(
            CollectionsUpdatedEvent('first_sync_complete_empty'),
          );
        }
      }
      _logger.info("No collections to sync.");
      return;
    }
    await _db.updateCollections(updatedCollections);
    // Update the cache with new/updated collections
    for (final collection in updatedCollections) {
      _collectionIDToCollections[collection.id] = collection;
    }
    await _db.setSyncTime(updatedCollections.last.updationTime);
    if (shouldCheckFirstSyncCompletion) {
      await _setFirstSyncCompleted();
    }

    final List<Future<bool>> fileFutures = [];
    for (final collection in updatedCollections) {
      if (collection.isDeleted) {
        continue;
      }
      final syncTime = _db.getCollectionSyncTime(collection.id);
      fileFutures.add(
        _apiClient
            .getFiles(collection, syncTime)
            .then((diff) async {
              if (diff.updatedFiles.isNotEmpty) {
                await _db.addFilesToCollection(collection, diff.updatedFiles);
              }
              if (diff.deletedFiles.isNotEmpty) {
                await _db.deleteFilesFromCollection(
                  collection,
                  diff.deletedFiles,
                );
              }
              await _db.setCollectionSyncTime(
                collection.id,
                diff.latestUpdatedAtTime,
              );
              return true;
            })
            .catchError((e) {
              _logger.severe(
                "Failed to fetch files for collection ${collection.id}: $e",
              );
              return false;
            }),
      );
    }
    final fileSyncResults = await Future.wait(fileFutures);
    if (fileSyncResults.every((didSync) => didSync)) {
      await OfflineFilesService.instance.cleanupInactiveOfflineFiles();
    } else {
      _logger.warning(
        "Skipping offline stale cleanup because one or more collection syncs failed",
      );
    }
    if (updatedCollections.isNotEmpty) {
      Bus.instance.fire(CollectionsUpdatedEvent('sync'));
    }
  }

  bool hasCompletedFirstSync() {
    if (!Configuration.instance.hasConfiguredAccount()) {
      return false;
    }
    if (_db.getSyncTime() > 0) {
      return true;
    }
    return _hasCompletedFirstSyncInPrefs();
  }

  Future<bool> _setFirstSyncCompleted() async {
    if (_hasCompletedFirstSyncInPrefs()) {
      return false;
    }
    await _prefs.setBool(_firstSyncCompletedPrefKey, true);
    return true;
  }

  bool _hasCompletedFirstSyncInPrefs() {
    return _prefs.getBool(_firstSyncCompletedPrefKey) ?? false;
  }

  Future<Collection> createCollection(
    String name, {
    CollectionType type = CollectionType.folder,
  }) async {
    try {
      final collection = await _apiClient.create(name, type);
      _logger.info("Created collection: ${collection.id}");

      // Cache in memory
      _collectionIDToCollections[collection.id] = collection;

      // Add to local database immediately
      await _db.updateCollections([collection]);

      // Fire event to update UI
      Bus.instance.fire(CollectionsUpdatedEvent('collection_created'));

      // Sync to ensure we have the latest state
      await sync();

      return collection;
    } catch (e) {
      _logger.severe("Failed to create collection: $e");
      rethrow;
    }
  }

  Future<List<Collection>> getCollections({bool includeDeleted = false}) async {
    final collections = await _db.getCollections();
    if (includeDeleted) {
      return collections;
    }
    return collections.where((collection) => !collection.isDeleted).toList();
  }

  Future<List<Collection>> getCollectionsForUI({
    bool includeViewerCollections = false,
    bool includeUncategorized = false,
  }) async {
    final collections = await getCollections();
    final int userID = Configuration.instance.getUserID()!;

    return collections.where((c) {
      if (!includeUncategorized &&
          c.type == CollectionType.uncategorized &&
          c.isOwner(userID)) {
        return false;
      }

      if (includeViewerCollections) {
        return true;
      }

      return c.canAdd(userID);
    }).toList();
  }

  Future<Collection?> getCollectionByID(int collectionID) async {
    if (_collectionIDToCollections.containsKey(collectionID)) {
      return _collectionIDToCollections[collectionID];
    }

    final collections = await _db.getCollections();
    for (final collection in collections) {
      if (collection.id == collectionID) {
        _collectionIDToCollections[collectionID] = collection;
        return collection;
      }
    }
    return null;
  }

  Future<List<Collection>> getCollectionsForFile(EnteFile file) async {
    return _db.getCollectionsForFile(file);
  }

  Future<List<EnteFile>> getFilesInCollection(Collection collection) async {
    try {
      final files = await _db.getFilesInCollection(collection);
      return files;
    } catch (e) {
      _logger.severe(
        "Failed to fetch files for collection ${collection.id}: $e",
      );
      rethrow;
    }
  }

  Future<int> getFileCount(Collection collection) async {
    final files = await getFilesInCollection(collection);
    return files.length;
  }

  Future<int> getFileSize(EnteFile file) async {
    int fileSize;
    if (file.fileSize != null) {
      fileSize = file.fileSize!;
    } else {
      // TODO: Need to write the code to getFile from server
      // fileSize = await getFile(file).then((f) => f!.length());
      fileSize = 0;
    }
    return fileSize;
  }

  Future<List<EnteFile>> getAllFiles() async {
    try {
      final allFiles = await _db.getAllFiles();
      return allFiles;
    } catch (e) {
      _logger.severe("Failed to fetch all files: $e");
      rethrow;
    }
  }

  /// Removes orphaned files that exist in files but have no collection mappings.
  Future<void> cleanupOrphanedFiles() async {
    try {
      await _db.cleanupOrphanedFiles();
      _logger.info("Cleaned up orphaned files from database");
    } catch (e) {
      _logger.severe("Failed to cleanup orphaned files: $e");
      rethrow;
    }
  }

  /// Adds a file to a collection. By default this triggers a full sync to
  /// update local state. Set [runSync] to false to delay syncing (useful when
  /// adding the same file to multiple collections during an upload).
  Future<void> addToCollection(
    Collection collection,
    EnteFile file, {
    bool runSync = true,
  }) async {
    try {
      await _apiClient.addToCollection(collection, [file]);
      _logger.info(
        "Added file (ID: ${file.uploadedFileID}) to collection ${collection.id}",
      );

      // Update local database immediately
      await _db.addFilesToCollection(collection, [file]);

      // Fire event to update UI
      Bus.instance.fire(CollectionsUpdatedEvent('add_to_collection'));

      if (runSync) {
        // Also sync to ensure we have the latest state from server
        await sync();
      }
    } catch (e, stackTrace) {
      _logger.severe("Failed to add file to collection: $e", e, stackTrace);
      rethrow;
    }
  }

  Future<void> trashFile(
    EnteFile file,
    Collection collection, {
    bool runSync = true,
  }) async {
    try {
      final List<TrashRequest> requests = [];
      requests.add(TrashRequest(file.uploadedFileID!, collection.id));
      await _apiClient.trash(requests);

      await _db.deleteFilesFromCollection(collection, [file]);

      if (runSync) {
        await TrashService.instance.syncTrash();
        await sync();
        Bus.instance.fire(UserDetailsRefreshEvent());
      }
    } catch (e) {
      _logger.severe("Failed to remove file from collections: $e");
      rethrow;
    }
  }

  Future<void> rename(Collection collection, String newName) async {
    try {
      await _apiClient.rename(collection, newName);
      _logger.info("Renamed collection ${collection.id}");
      // Let sync update the local state
      await sync();
    } catch (e, s) {
      _logger.severe("failed to rename collection", e, s);
      rethrow;
    }
  }

  Future<Collection> getOrCreateUncategorizedCollection() async {
    final collections = await getCollections();
    final userID = Configuration.instance.getUserID()!;
    final collection = findUserUncategorizedCollection(collections, userID);
    if (collection != null) {
      return collection;
    }
    _logger.info("No collections found, creating uncategorized collection.");
    return await createCollection(
      "Uncategorized",
      type: CollectionType.uncategorized,
    );
  }

  Future<void> _init() async {
    // One-time cleanup of orphaned files from before the trash deletion fix
    unawaited(cleanupOrphanedFiles());

    unawaited(
      sync()
          .then((_) {
            ensureDefaultCollections();
          })
          .catchError((error) {
            if (error is UnauthorizedError) {
              _logger.info("Session expired, triggering logout");
              Bus.instance.fire(TriggerLogoutEvent());
            } else {
              _logger.severe("Failed to initialize collections: $error");
            }
          }),
    );
    final collections = await _db.getCollections();
    for (final collection in collections) {
      _collectionIDToCollections[collection.id] = collection;
    }
  }

  Future<Collection> getOrCreateImportantCollection() async {
    final collections = await getCollections();
    for (final collection in collections) {
      if (collection.type == CollectionType.favorites) {
        return collection;
      }
    }
    _logger.info(
      "No favorites collection found, creating important collection.",
    );
    final collection = await createCollection(
      "Important",
      type: CollectionType.favorites,
    );
    return collection;
  }

  Future<void> removeFromCollection(
    int collectionId,
    List<EnteFile> files,
  ) async {
    if (files.isEmpty) {
      _logger.info("No files to remove");
      return;
    }

    try {
      await _apiClient.removeFromCollection(collectionId, files);

      Bus.instance.fire(CollectionsUpdatedEvent('files_removed'));

      await sync();
    } catch (e, stackTrace) {
      _logger.severe(
        "Failed to remove files from collection: $e",
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<void> move(
    List<EnteFile> files,
    Collection from,
    Collection to, {
    bool runSync = true,
  }) async {
    if (files.isEmpty) {
      _logger.info("No files to move");
      return;
    }

    try {
      // Call API to move files on server
      await _apiClient.move(files, from, to);

      // Update collectionID for all files
      for (final file in files) {
        file.collectionID = to.id;
      }

      // Write the destination row first so local key material and offline state
      // stay attached to the moved file before the source mapping is removed.
      await _db.addFilesToCollection(to, files);
      await _db.deleteFilesFromCollection(from, files);

      // Let sync update the local state to ensure consistency
      if (runSync) {
        await sync();
      }
    } catch (e, stackTrace) {
      _logger.severe("Failed to move files: $e", e, stackTrace);
      rethrow;
    }
  }

  Future<void> trashCollection(
    BuildContext? context,
    Collection collection, {
    bool keepFiles = true,
  }) async {
    if (keepFiles) {
      await trashCollectionKeepingFiles(context, collection);
    } else {
      await trashCollectionWithFiles(collection);
    }
  }

  Future<void> trashCollectionKeepingFiles(
    BuildContext? context,
    Collection collection,
  ) async {
    try {
      final files = await _db.getFilesInCollection(collection);

      if (files.isNotEmpty) {
        await moveFilesFromCurrentCollection(
          context != null && context.mounted ? context : null,
          collection,
          files,
        );
      }

      await _apiClient.trashCollection(collection, keepFiles: true);
      await sync();
      await TrashService.instance.syncTrash();
    } catch (e) {
      _logger.severe("Failed to trash collection keeping files: $e");
      rethrow;
    }
  }

  Future<void> trashCollectionWithFiles(Collection collection) async {
    try {
      final files = await _db.getFilesInCollection(collection);

      if (files.isNotEmpty) {
        for (final file in files) {
          final fileCollections = await getCollectionsForFile(file);
          for (final fileCollection in fileCollections) {
            await trashFile(file, fileCollection, runSync: false);
          }
        }
      }

      await _apiClient.trashCollection(collection);

      await sync();
      await TrashService.instance.syncTrash();
      Bus.instance.fire(UserDetailsRefreshEvent());
    } catch (e) {
      _logger.severe("Failed to trash collection with files: $e");
      rethrow;
    }
  }

  /// Trash an empty collection directly without moving files.
  /// The server will verify that the collection is actually empty before
  /// deleting. If keepFiles is set as False and the collection is not empty,
  /// then the files in the collection will be moved to trash.
  ///
  /// [isBulkDelete] - During bulk deletion, this event is not fired to avoid
  /// quick refresh of the collection gallery
  Future<void> trashEmptyCollection(
    Collection collection, {
    bool isBulkDelete = false,
  }) async {
    try {
      await _apiClient.trashCollection(
        collection,
        keepFiles: true,
        skipEventFiring: isBulkDelete,
      );
      if (!isBulkDelete) {
        await sync();
        await TrashService.instance.syncTrash();
      }
    } catch (e) {
      _logger.severe("Failed to trash empty collection: $e");
      rethrow;
    }
  }

  Future<void> moveFilesFromCurrentCollection(
    BuildContext? context,
    Collection collection,
    Iterable<EnteFile> files, {
    bool isHidden = false,
  }) async {
    final int currentUserID = Configuration.instance.getUserID()!;
    final isCollectionOwner = collection.owner.id == currentUserID;
    final FilesSplit split = FilesSplit.split(
      files,
      Configuration.instance.getUserID()!,
    );
    if (isCollectionOwner && split.ownedByOtherUsers.isNotEmpty) {
      await _apiClient.removeFromCollection(
        collection.id,
        split.ownedByOtherUsers,
      );
    } else if (!isCollectionOwner && split.ownedByCurrentUser.isNotEmpty) {
      // collection is not owned by the user, just remove files owned
      // by current user and return
      await _apiClient.removeFromCollection(
        collection.id,
        split.ownedByCurrentUser,
      );
      return;
    }

    if (!isCollectionOwner && split.ownedByOtherUsers.isNotEmpty) {
      if (context != null && context.mounted) {
        showShortToast(context, context.l10n.canOnlyRemoveFilesOwnedByYou);
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

    final Map<int, List<EnteFile>> collectionToFilesMap = await _db
        .getAllFilesGroupByCollectionID(uploadedIDs);

    // Find and map the files from current collection to to entries in other
    // collections. This mapping is done to avoid moving all the files to
    // uncategorized during remove from album.
    for (MapEntry<int, List<EnteFile>> entry in collectionToFilesMap.entries) {
      if (!await _isAutoMoveCandidate(
        collection.id,
        entry.key,
        currentUserID,
      )) {
        continue;
      }
      final Collection? targetCollection = await getCollectionByID(entry.key);
      if (targetCollection != null) {
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
    }
    // Move the remaining files to uncategorized collection
    if (pendingAssignMap.isNotEmpty) {
      late final int toCollectionID;

      final Collection uncategorizedCollection =
          await getOrCreateUncategorizedCollection();
      toCollectionID = uncategorizedCollection.id;

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

        _logger.info(
          'skipping moving ${entry.value.length} files to uncategorized collection',
        );
      } else {
        final toCollection = await getCollection(entry.key);
        await move(entry.value, collection, toCollection, runSync: false);
      }
    }
  }

  // This method returns true if the given destination collection is a good
  // target to moving files during file remove or delete collection but keep
  // photos action. Uncategorized or favorite type of collections are not
  // good auto-move candidates. Uncategorized will be fall back for all files
  // which could not be mapped to a potential target collection
  Future<bool> _isAutoMoveCandidate(
    int fromCollectionID,
    toCollectionID,
    int userID,
  ) async {
    if (fromCollectionID == toCollectionID) {
      return false;
    }
    final Collection? targetCollection = await getCollectionByID(
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

  Future<void> setupDefaultCollections() async {
    try {
      if (Configuration.instance.getKey() == null) {
        _logger.warning(
          "Cannot setup default collections - master key not available",
        );
        return;
      }

      _logger.info("Setting up default collections...");

      // Create uncategorized collection if it doesn't exist
      await getOrCreateUncategorizedCollection();

      // Create important (favorites) collection if it doesn't exist
      await getOrCreateImportantCollection();

      // Create Documents collection if it doesn't exist
      await _getOrCreateDocumentsCollection();

      _logger.info("Default collections setup completed.");
    } catch (e, s) {
      _logger.severe("Failed to setup default collections", e, s);
    }
  }

  Future<void> ensureDefaultCollections() async {
    if (!Configuration.instance.hasConfiguredAccount()) {
      _logger.warning(
        "Skipping default collections setup - account not configured",
      );
      return;
    }

    if (!hasCompletedFirstSync()) {
      _logger.info(
        "Skipping default collections setup - first sync not completed yet",
      );
      return;
    }

    final inFlight = _defaultSetupInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final setupFuture = Future<void>.sync(setupDefaultCollections);
    _defaultSetupInFlight = setupFuture.whenComplete(() {
      _defaultSetupInFlight = null;
    });
    await _defaultSetupInFlight;
  }

  Future<Collection> _getOrCreateDocumentsCollection() async {
    final collections = await getCollections();
    for (final collection in collections) {
      if (collection.type == CollectionType.folder &&
          collection.name == "Documents") {
        return collection;
      }
    }
    _logger.info(
      "No Documents collection found, creating Documents collection.",
    );
    return createCollection("Documents", type: CollectionType.folder);
  }

  /// Returns one random collection name that doesn't already exist
  /// If all names are used, returns "Documents"
  Future<String> getRandomUnusedCollectionName() async {
    try {
      final existingCollections = await getCollections();
      final existingNames = existingCollections
          .map((collection) => collection.name?.toLowerCase())
          .where((name) => name != null)
          .toSet();

      final availableNames = _suggestedCollectionNames
          .where((name) => !existingNames.contains(name.toLowerCase()))
          .toList();

      if (availableNames.isEmpty) {
        _logger.info(
          "All suggested collection names are used, returning 'Documents'",
        );
        return "Documents";
      }

      final random = Random();
      final randomName = availableNames[random.nextInt(availableNames.length)];
      _logger.info("Selected random unused collection name");
      return randomName;
    } catch (e) {
      _logger.severe("Failed to get random unused collection name: $e");
      return "Documents";
    }
  }

  Future<Collection> getCollection(int collectionID) async {
    if (_collectionIDToCollections.containsKey(collectionID)) {
      return _collectionIDToCollections[collectionID]!;
    }
    final collection = await _db.getCollection(collectionID);
    _collectionIDToCollections[collectionID] = collection;
    return collection;
  }

  Uint8List getCollectionKey(int collectionID) {
    final collection = _collectionIDToCollections[collectionID];
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection!);
    return collectionKey;
  }

  Future<Uint8List> getFileKey(EnteFile file) async {
    try {
      final collection = await getCollection(file.collectionID!);
      final collectionKey = CryptoHelper.instance.getCollectionKey(collection);

      final fileKey = CryptoHelper.instance.getFileKey(
        file.encryptedKey!,
        file.keyDecryptionNonce!,
        collectionKey,
      );

      _logger.info(
        "Successfully decrypted file key for file (ID: ${file.uploadedFileID})",
      );
      return fileKey;
    } catch (e) {
      _logger.severe("Failed to get file key: $e");
      rethrow;
    }
  }

  // getActiveCollections returns list of collections which are not deleted yet
  List<Collection> getActiveCollections() {
    return _collectionIDToCollections.values
        .toList()
        .where((element) => !element.isDeleted)
        .toList();
  }

  /// Returns Contacts(Users) that are relevant to the account owner.
  /// Note: "User" refers to the account owner in the points below.
  /// This includes:
  /// 	- Collaborators and viewers of collections owned by user
  ///   - Owners of collections shared to user.
  ///   - All collaborators of collections in which user is a collaborator or
  ///     a viewer.
  List<User> getRelevantContacts() {
    final List<User> relevantUsers = [];
    final existingEmails = <String>{};
    final int ownerID = Configuration.instance.getUserID()!;
    final String ownerEmail = Configuration.instance.getEmail()!;
    existingEmails.add(ownerEmail);

    for (final c in getActiveCollections()) {
      // Add collaborators and viewers of collections owned by user
      if (c.owner.id == ownerID) {
        for (final User u in c.sharees) {
          if (u.id != null && u.email.isNotEmpty) {
            if (!existingEmails.contains(u.email)) {
              relevantUsers.add(u);
              existingEmails.add(u.email);
            }
          }
        }
      } else if (c.owner.id != null && c.owner.email.isNotEmpty) {
        // Add owners of collections shared with user
        if (!existingEmails.contains(c.owner.email)) {
          relevantUsers.add(c.owner);
          existingEmails.add(c.owner.email);
        }
        // Add collaborators of collections shared with user where user is a
        // viewer or a collaborator
        for (final User u in c.sharees) {
          if (u.id != null &&
              u.email.isNotEmpty &&
              u.email == ownerEmail &&
              (u.isCollaborator || u.isViewer)) {
            for (final User u in c.sharees) {
              if (u.id != null && u.email.isNotEmpty && u.isCollaborator) {
                if (!existingEmails.contains(u.email)) {
                  relevantUsers.add(u);
                  existingEmails.add(u.email);
                }
              }
            }
            break;
          }
        }
      }
    }

    // Add user's family members
    final cachedUserDetails = UserService.instance.getCachedUserDetails();
    if (cachedUserDetails?.familyData?.members?.isNotEmpty ?? false) {
      for (final member in cachedUserDetails!.familyData!.members!) {
        if (!existingEmails.contains(member.email)) {
          relevantUsers.add(User(email: member.email));
          existingEmails.add(member.email);
        }
      }
    }
    return relevantUsers;
  }

  String getPublicUrl(Collection c) {
    final PublicURL url = c.publicURLs.firstOrNull!;
    final Uri publicUrl = Uri.parse(url.url);

    final cKey = getCollectionKey(c.id);
    final String collectionKey = Base58Encode(cKey);
    final String urlValue = "${publicUrl.toString()}#$collectionKey";
    return urlValue;
  }

  void clearCache() {
    _collectionIDToCollections.clear();
    _defaultSetupInFlight = null;
  }

  // Methods for managing collection cache
  void updateCollectionCache(Collection collection) {
    _collectionIDToCollections[collection.id] = collection;
  }

  void removeFromCache(int collectionId) {
    _collectionIDToCollections.remove(collectionId);
  }

  Collection? getFromCache(int collectionId) {
    return _collectionIDToCollections[collectionId];
  }
}
