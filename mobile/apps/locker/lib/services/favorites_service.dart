import 'dart:async';

import 'package:ente_events/event_bus.dart';
import 'package:locker/events/collections_updated_event.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/utils/collection_list_util.dart';
import 'package:logging/logging.dart';

class FavoritesService {
  late Configuration _config;

  late CollectionService _collectionService;
  late LockerDB _db;
  int? _cachedFavoritesCollectionID;
  final Set<int> _cachedFavUploadedIDs = {};
  final Map<String, int> _cachedFavFileHashes = {};
  late StreamSubscription<CollectionsUpdatedEvent>
  _collectionUpdatesSubscription;

  FavoritesService._privateConstructor();

  static FavoritesService instance = FavoritesService._privateConstructor();

  final _logger = Logger("FavoritesService");

  Future<void> init() async {
    _config = Configuration.instance;
    _collectionService = CollectionService.instance;
    _db = LockerDB.instance;
    _collectionUpdatesSubscription = Bus.instance
        .on<CollectionsUpdatedEvent>()
        .listen((event) {
          _warmUpCache();
        });
    await _warmUpCache();
  }

  void dispose() {
    _collectionUpdatesSubscription.cancel();
  }

  Future<void> _warmUpCache() async {
    final favCollection = await getFavoritesCollection();
    if (favCollection != null) {
      final favoriteFiles = await _db.getFilesInCollection(favCollection);

      _cachedFavUploadedIDs.clear();
      _cachedFavFileHashes.clear();

      for (final file in favoriteFiles) {
        if (file.uploadedFileID != null) {
          _cachedFavUploadedIDs.add(file.uploadedFileID!);
          if (file.hash != null) {
            _cachedFavFileHashes[file.hash!] = file.uploadedFileID!;
          }
        }
      }
    } else {
      clearCache();
    }
  }

  bool hasFavorites() {
    return _cachedFavUploadedIDs.isNotEmpty;
  }

  void clearCache() {
    _cachedFavoritesCollectionID = null;
    _cachedFavUploadedIDs.clear();
    _cachedFavFileHashes.clear();
  }

  bool isFavoriteCache(EnteFile file, {bool checkOnlyAlbum = false}) {
    if (file.collectionID != null &&
        _cachedFavoritesCollectionID != null &&
        file.collectionID == _cachedFavoritesCollectionID) {
      return true;
    }
    if (checkOnlyAlbum) {
      return false;
    }
    if (file.uploadedFileID != null) {
      bool isFav = false;
      if (file.ownerID != _config.getUserID() && file.hash != null) {
        isFav = _cachedFavFileHashes.containsKey(file.hash!);
      } else {
        isFav = _cachedFavUploadedIDs.contains(file.uploadedFileID);
      }
      return isFav;
    }
    return false;
  }

  Future<bool> isFavorite(EnteFile file) async {
    if (file.uploadedFileID != null) {
      bool isFav = false;
      if (file.ownerID != _config.getUserID() && file.hash != null) {
        isFav = _cachedFavFileHashes.containsKey(file.hash!);
      } else {
        isFav = _cachedFavUploadedIDs.contains(file.uploadedFileID);
      }
      return isFav;
    }
    return false;
  }

  void _updateFavoriteFilesCache(
    List<EnteFile> files, {
    required bool favFlag,
  }) {
    final Set<int> updatedIDs = {};
    final Map<String, int> hashes = {};
    for (var file in files) {
      if (file.uploadedFileID != null) {
        updatedIDs.add(file.uploadedFileID!);
        if (file.hash != null) {
          hashes[file.hash!] = file.uploadedFileID!;
        }
      }
    }

    if (favFlag) {
      _cachedFavUploadedIDs.addAll(updatedIDs);
      _cachedFavFileHashes.addAll(hashes);
    } else {
      _cachedFavUploadedIDs.removeAll(updatedIDs);
      for (var hash in hashes.keys) {
        _cachedFavFileHashes.remove(hash);
      }
    }
  }

  Future<void> addToFavorites(EnteFile file) async {
    final favCollection = await _getOrCreateFavoriteCollection();

    final List<EnteFile> files = [file];
    if (file.uploadedFileID == null) {
      _logger.severe("Cannot favorite file without uploadedFileID");
      throw AssertionError("Can only favorite uploaded items");
    } else {
      await _collectionService.addToCollection(favCollection, files[0]);
    }

    _updateFavoriteFilesCache(files, favFlag: true);

    _collectionService.sync().ignore();
  }

  Future<void> updateFavorites(List<EnteFile> files, bool favFlag) async {
    final int currentUserID = Configuration.instance.getUserID()!;
    if (files.any((f) => f.uploadedFileID == null)) {
      throw AssertionError("Can only favorite uploaded items");
    }
    if (files.any((f) => f.ownerID != currentUserID)) {
      throw AssertionError("Can not favorite files owned by others");
    }
    final favCollection = await _getOrCreateFavoriteCollection();
    if (favFlag) {
      for (final file in files) {
        await _collectionService.addToCollection(favCollection, file);
      }
    } else {
      for (final file in files) {
        final currentCollections = await _collectionService
            .getCollectionsForFile(file);

        Collection? targetCollection;
        for (final col in currentCollections) {
          if (col.id != favCollection.id) {
            targetCollection = col;
            break;
          }
        }

        targetCollection ??= await _collectionService
            .getOrCreateUncategorizedCollection();

        await _collectionService.move([file], favCollection, targetCollection);
      }
    }
    _updateFavoriteFilesCache(files, favFlag: favFlag);
  }

  Future<void> removeFromFavorites(EnteFile file) async {
    final inUploadID = file.uploadedFileID;
    if (inUploadID == null) {
    } else {
      final Collection? favCollection = await getFavoritesCollection();
      if (favCollection == null) {
        _updateFavoriteFilesCache([file], favFlag: false);
        return;
      }

      if (file.ownerID != _config.getUserID() &&
          file.hash != null &&
          _cachedFavFileHashes.containsKey(file.hash!)) {
        final favFiles = await _db.getFilesInCollection(favCollection);
        final favFile = favFiles.firstWhere(
          (f) => f.uploadedFileID == _cachedFavFileHashes[file.hash!],
          orElse: () => file,
        );
        file = favFile;
      }

      if (file.collectionID != favCollection.id) {
        final favFiles = await _db.getFilesInCollection(favCollection);
        final favFile = favFiles.firstWhere(
          (f) => f.uploadedFileID == file.uploadedFileID,
          orElse: () => file,
        );
        file = favFile;
      }

      final currentCollections = await _collectionService.getCollectionsForFile(
        file,
      );

      Collection? targetCollection;
      for (final col in currentCollections) {
        if (col.id != favCollection.id) {
          targetCollection = col;
          break;
        }
      }

      targetCollection ??= await _collectionService
          .getOrCreateUncategorizedCollection();

      await _collectionService.move([file], favCollection, targetCollection);
    }

    _updateFavoriteFilesCache([file], favFlag: false);
  }

  Future<Collection?> getFavoritesCollection() async {
    final userID = _config.getUserID();
    if (userID == null) {
      clearCache();
      return null;
    }
    final cachedID = _cachedFavoritesCollectionID;
    if (cachedID != null) {
      final cachedCollection = await _collectionService.getCollectionByID(
        cachedID,
      );
      if (cachedCollection != null &&
          !cachedCollection.isDeleted &&
          cachedCollection.isOwner(userID) &&
          cachedCollection.type == CollectionType.favorites) {
        return cachedCollection;
      }
      clearCache();
    }

    final collections = await _collectionService.getCollections();
    final collection = findOwnedCollection(
      collections,
      ownerID: userID,
      type: CollectionType.favorites,
    );
    _cachedFavoritesCollectionID = collection?.id;
    return collection;
  }

  Future<int?> getFavoriteCollectionID() async {
    final collection = await getFavoritesCollection();
    return collection?.id;
  }

  Future<Collection> _getOrCreateFavoriteCollection() async {
    final existingCollection = await getFavoritesCollection();
    if (existingCollection != null) {
      return existingCollection;
    }

    final collection = await _collectionService
        .getOrCreateImportantCollection();
    _cachedFavoritesCollectionID = collection.id;

    return collection;
  }
}
