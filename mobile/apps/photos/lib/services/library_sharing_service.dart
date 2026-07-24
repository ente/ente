import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/metadata/common_keys.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/settings/local_settings.dart';

abstract interface class LibrarySharingRepository {
  Future<List<Collection>> getEligibleAlbums();

  Future<String?> getPublicKey(String email);

  Future<void> shareAlbum({
    required Collection collection,
    required String email,
    required String publicKey,
    required CollectionParticipantRole role,
  });

  Future<void> unshareAlbum({
    required Collection collection,
    required int recipientUserID,
    required String email,
  });
}

class LibrarySharingService implements LibrarySharingRepository {
  LibrarySharingService({
    CollectionsService? collectionsService,
    UserService? userService,
  }) : _collectionsService = collectionsService ?? CollectionsService.instance,
       _userService = userService ?? UserService.instance;

  final CollectionsService _collectionsService;
  final UserService _userService;

  @override
  Future<List<Collection>> getEligibleAlbums() async {
    final userID = Configuration.instance.getUserID();
    if (userID == null) {
      return const [];
    }

    final albums = _collectionsService
        .getCollectionsForUI(includeUncategorized: false)
        .where((collection) => isEligibleAlbum(collection, userID))
        .toList();
    await _sortByAlbumPreferences(albums);
    return albums;
  }

  static bool isEligibleAlbum(Collection collection, int ownerID) {
    final isHidden =
        collection.isDefaultHidden() ||
        collection.mMdVersion > 0 &&
            collection.magicMetadata.visibility == hiddenVisibility;
    final isShareableAlbum =
        collection.type == CollectionType.album ||
        collection.type == CollectionType.folder ||
        collection.type == CollectionType.favorites;
    return !collection.isDeleted &&
        collection.isOwner(ownerID) &&
        !isHidden &&
        isShareableAlbum &&
        !collection.isQuickLinkCollection();
  }

  @override
  Future<String?> getPublicKey(String email) =>
      _userService.getPublicKey(email);

  @override
  Future<void> shareAlbum({
    required Collection collection,
    required String email,
    required String publicKey,
    required CollectionParticipantRole role,
  }) async {
    await _collectionsService.share(collection.id, email, publicKey, role);
  }

  @override
  Future<void> unshareAlbum({
    required Collection collection,
    required int recipientUserID,
    required String email,
  }) async {
    try {
      await _collectionsService.unshare(collection.id, email);
    } on DioException catch (error, stackTrace) {
      if (error.response?.statusCode != 404) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      try {
        final sharees = await _collectionsService.refreshSharees(collection.id);
        if (!sharees.any((sharee) => sharee.id == recipientUserID)) {
          return;
        }
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Map<int, int>> sharedAlbumCounts(Set<int> recipientUserIDs) async {
    if (recipientUserIDs.isEmpty) {
      return const {};
    }
    return countSharedAlbums(await getEligibleAlbums(), recipientUserIDs);
  }

  static Map<int, int> countSharedAlbums(
    Iterable<Collection> albums,
    Set<int> recipientUserIDs,
  ) {
    final counts = {for (final userID in recipientUserIDs) userID: 0};
    for (final album in albums) {
      for (final sharee in album.sharees) {
        final shareeID = sharee.id;
        if (shareeID != null && counts.containsKey(shareeID)) {
          counts[shareeID] = counts[shareeID]! + 1;
        }
      }
    }
    return counts;
  }

  Future<void> _sortByAlbumPreferences(List<Collection> albums) async {
    final sortKey = localSettings.albumSortKey();
    final sortDirection = localSettings.albumSortDirection();
    Map<int, int> newestPhotoTimeByCollectionID = const {};
    if (sortKey == AlbumSortKey.newestPhoto) {
      newestPhotoTimeByCollectionID = await _collectionsService
          .getCollectionIDToNewestFileTime();
    }

    albums.sort((first, second) {
      final comparison = switch (sortKey) {
        AlbumSortKey.albumName => compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        ),
        AlbumSortKey.newestPhoto =>
          (newestPhotoTimeByCollectionID[second.id] ?? 0).compareTo(
            newestPhotoTimeByCollectionID[first.id] ?? 0,
          ),
        AlbumSortKey.lastUpdated => second.updationTime.compareTo(
          first.updationTime,
        ),
      };
      return sortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });
  }
}
