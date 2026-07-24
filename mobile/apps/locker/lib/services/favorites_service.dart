import 'dart:async';

import 'package:ente_events/event_bus.dart';
import 'package:locker/events/collections_updated_event.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/files/sync/models/file.dart';
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
          // When collections are updated, refresh our cache
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
    // Use cache for better performance
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
    final collectionID = await _getOrCreateFavoriteCollectionID();

    final List<EnteFile> files = [file];
    if (file.uploadedFileID == null) {
      _logger.severe("Cannot favorite file without uploadedFileID");
      throw AssertionError("Can only favorite uploaded items");
    } else {
      final collection = await _collectionService.getCollectionByID(
        collectionID,
      );

      await _collectionService.addToCollection(collection!, files[0]);
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
    final collectionID = await _getOrCreateFavoriteCollectionID();
    if (favFlag) {
      final collection = await _collectionService.getCollectionByID(
        collectionID,
      );
      for (final file in files) {
        await _collectionService.addToCollection(collection!, file);
      }
    } else {
      final Collection? favCollection = await getFavoritesCollection();
      for (final file in files) {
        // Get current collections for file
        final currentCollections = await _collectionService
            .getCollectionsForFile(file);

        // If file is in multiple collections, move it to the first non-favorite one
        // Otherwise, move to uncategorized
        Collection? targetCollection;
        for (final col in currentCollections) {
          if (col.id != favCollection!.id) {
            targetCollection = col;
            break;
          }
        }

        // If no other collection found, move to uncategorized
        targetCollection ??= await _collectionService
            .getOrCreateUncategorizedCollection();

        await _collectionService.move([file], favCollection!, targetCollection);
      }
    }
    _updateFavoriteFilesCache(files, favFlag: favFlag);
  }

  Future<void> removeFromFavorites(EnteFile file) async {
    final inUploadID = file.uploadedFileID;
    if (inUploadID == null) {
      // Do nothing, ignore
    } else {
      final Collection? favCollection = await getFavoritesCollection();

      // The file might be part of another collection. For unfav, we need to
      // move file from the fav collection.
      if (file.ownerID != _config.getUserID() &&
          file.hash != null &&
          _cachedFavFileHashes.containsKey(file.hash!)) {
        final favFiles = await _db.getFilesInCollection(favCollection!);
        final favFile = favFiles.firstWhere(
          (f) => f.uploadedFileID == _cachedFavFileHashes[file.hash!],
          orElse: () => file,
        );
        file = favFile;
      }

      if (file.collectionID != favCollection!.id) {
        final favFiles = await _db.getFilesInCollection(favCollection);
        final favFile = favFiles.firstWhere(
          (f) => f.uploadedFileID == file.uploadedFileID,
          orElse: () => file,
        );
        file = favFile;
      }

      // Get current collections for file
      final currentCollections = await _collectionService.getCollectionsForFile(
        file,
      );

      // If file is in multiple collections, move it to the first non-favorite one
      // Otherwise, move to uncategorized
      Collection? targetCollection;
      for (final col in currentCollections) {
        if (col.id != favCollection.id) {
          targetCollection = col;
          break;
        }
      }

      // If no other collection found, move to uncategorized
      targetCollection ??= await _collectionService
          .getOrCreateUncategorizedCollection();

      await _collectionService.move([file], favCollection, targetCollection);
    }

    _updateFavoriteFilesCache([file], favFlag: false);
  }

  Future<Collection?> getFavoritesCollection() async {
    if (_cachedFavoritesCollectionID == null) {
      final collections = await _collectionService.getCollections();

      for (final collection in collections) {
        if (collection.owner.id == _config.getUserID() &&
            collection.type == CollectionType.favorites) {
          _cachedFavoritesCollectionID = collection.id;
          return collection;
        }
      }
      return null;
    }

    return _collectionService.getCollectionByID(_cachedFavoritesCollectionID!);
  }

  Future<int?> getFavoriteCollectionID() async {
    final collection = await getFavoritesCollection();
    return collection?.id;
  }

  Future<int> _getOrCreateFavoriteCollectionID() async {
    if (_cachedFavoritesCollectionID != null) {
      return _cachedFavoritesCollectionID!;
    }

    final collection = await _collectionService
        .getOrCreateImportantCollection();
    _cachedFavoritesCollectionID = collection.id;

    return collection.id;
  }
}
