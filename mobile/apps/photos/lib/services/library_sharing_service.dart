import 'package:dio/dio.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/collections_service.dart';

const librarySharingRoles = [
  CollectionParticipantRole.viewer,
  CollectionParticipantRole.collaborator,
  CollectionParticipantRole.admin,
];

CollectionParticipantRole? librarySharingRoleFor(
  Collection collection,
  int userID,
) {
  for (final sharee in collection.sharees) {
    if (sharee.id == userID) {
      final role = CollectionParticipantRoleExtn.fromString(sharee.role);
      return librarySharingRoles.contains(role) ? role : null;
    }
  }
  return null;
}

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
    final albums = _eligibleAlbums().toList();
    await _collectionsService.sortCollectionsByAlbumPreferences(albums);
    return albums;
  }

  static bool _isEligibleAlbum(Collection collection) {
    final isShareableAlbum =
        collection.type == CollectionType.album ||
        collection.type == CollectionType.folder ||
        collection.type == CollectionType.favorites;
    return isShareableAlbum && !collection.isQuickLinkCollection();
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
      // A 404 is idempotent only if fresh sharees confirm they are absent.
      try {
        final sharees = await _collectionsService.refreshSharees(collection.id);
        if (!sharees.any((sharee) => sharee.id == recipientUserID)) {
          return;
        }
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Map<int, int> sharedAlbumCounts(Set<int> recipientUserIDs) {
    if (recipientUserIDs.isEmpty) {
      return const {};
    }
    final counts = {for (final userID in recipientUserIDs) userID: 0};
    for (final album in _eligibleAlbums()) {
      for (final userID in recipientUserIDs) {
        if (librarySharingRoleFor(album, userID) != null) {
          counts[userID] = counts[userID]! + 1;
        }
      }
    }
    return counts;
  }

  Iterable<Collection> _eligibleAlbums() => _collectionsService
      .getCollectionsForUI(includeUncategorized: false)
      .where(_isEligibleAlbum);
}
