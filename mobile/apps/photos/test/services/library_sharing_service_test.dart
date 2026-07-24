import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/metadata/collection_magic.dart';
import 'package:photos/models/metadata/common_keys.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/library_sharing_service.dart';

import '../ui/sharing/library_sharing_test_helpers.dart';

void main() {
  group('LibrarySharingService.isEligibleAlbum', () {
    test('includes ordinary archived albums owned by the current user', () {
      final archived = librarySharingTestAlbum(1)..mMdVersion = 1;
      archived.magicMetadata = CollectionMagicMetadata(
        visibility: archiveVisibility,
      );

      expect(LibrarySharingService.isEligibleAlbum(archived, 1), isTrue);
    });

    test('includes owned folders and Favorites shown in Albums', () {
      expect(
        LibrarySharingService.isEligibleAlbum(
          librarySharingTestAlbum(1, type: CollectionType.folder),
          1,
        ),
        isTrue,
      );
      expect(
        LibrarySharingService.isEligibleAlbum(
          librarySharingTestAlbum(2, type: CollectionType.favorites),
          1,
        ),
        isTrue,
      );
    });

    test(
      'excludes hidden, unsupported, quick-link, incoming, and deleted albums',
      () {
        final hidden = librarySharingTestAlbum(1)..mMdVersion = 1;
        hidden.magicMetadata = CollectionMagicMetadata(
          visibility: hiddenVisibility,
        );
        final quickLink = librarySharingTestAlbum(2)..mMdVersion = 1;
        quickLink.magicMetadata = CollectionMagicMetadata(
          visibility: visibleVisibility,
          subType: subTypeSharedFilesCollection,
        );

        expect(LibrarySharingService.isEligibleAlbum(hidden, 1), isFalse);
        expect(LibrarySharingService.isEligibleAlbum(quickLink, 1), isFalse);
        expect(
          LibrarySharingService.isEligibleAlbum(
            librarySharingTestAlbum(3, type: CollectionType.uncategorized),
            1,
          ),
          isFalse,
        );
        expect(
          LibrarySharingService.isEligibleAlbum(
            librarySharingTestAlbum(4, type: CollectionType.unknown),
            1,
          ),
          isFalse,
        );
        expect(
          LibrarySharingService.isEligibleAlbum(
            librarySharingTestAlbum(5, ownerID: 2),
            1,
          ),
          isFalse,
        );
        expect(
          LibrarySharingService.isEligibleAlbum(
            librarySharingTestAlbum(6, isDeleted: true),
            1,
          ),
          isFalse,
        );
      },
    );
  });

  test('counts shares by immutable recipient user ID', () {
    final first = librarySharingTestAlbum(1)
      ..sharees.add(User(id: 42, email: 'old@example.com'));
    final second = librarySharingTestAlbum(2)
      ..sharees.add(User(id: 42, email: 'new@example.com'));
    final emailOnly = librarySharingTestAlbum(3)
      ..sharees.add(User(email: 'new@example.com'));

    expect(
      LibrarySharingService.countSharedAlbums(
        [first, second, emailOnly],
        {42, 43},
      ),
      {42: 2, 43: 0},
    );
  });

  group('LibrarySharingService.unshareAlbum', () {
    late _MockCollectionsService collectionsService;
    late LibrarySharingService service;
    late Collection album;

    setUp(() {
      collectionsService = _MockCollectionsService();
      service = LibrarySharingService(collectionsService: collectionsService);
      album = librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      );
    });

    test('accepts an already-absent recipient after a not-found response', () {
      final error = _dioException(404);
      collectionsService.unshareHandler = (_, _) => Future.error(error);
      collectionsService.refreshShareesHandler = (_) async => const <User>[];

      expect(
        service.unshareAlbum(
          collection: album,
          recipientUserID: librarySharingTestRecipient.userID,
          email: librarySharingTestRecipient.email,
        ),
        completes,
      );
    });

    test('preserves non-idempotent unshare failures', () async {
      final error = _dioException(500);
      collectionsService.unshareHandler = (_, _) => Future.error(error);

      await expectLater(
        service.unshareAlbum(
          collection: album,
          recipientUserID: librarySharingTestRecipient.userID,
          email: librarySharingTestRecipient.email,
        ),
        throwsA(same(error)),
      );
      expect(collectionsService.refreshShareesCalls, 0);
    });

    test('preserves not-found when the recipient is still present', () async {
      final error = _dioException(404);
      collectionsService.unshareHandler = (_, _) => Future.error(error);
      collectionsService.refreshShareesHandler = (_) async => [
        User(
          id: librarySharingTestRecipient.userID,
          email: librarySharingTestRecipient.email,
        ),
      ];

      await expectLater(
        service.unshareAlbum(
          collection: album,
          recipientUserID: librarySharingTestRecipient.userID,
          email: librarySharingTestRecipient.email,
        ),
        throwsA(same(error)),
      );
    });
  });
}

class _MockCollectionsService extends Mock implements CollectionsService {
  late Future<List<User>> Function(int collectionID, String email)
  unshareHandler;
  Future<List<User>> Function(int collectionID)? refreshShareesHandler;
  int refreshShareesCalls = 0;

  @override
  Future<List<User>> unshare(int collectionID, String email) =>
      unshareHandler(collectionID, email);

  @override
  Future<List<User>> refreshSharees(int collectionID) {
    refreshShareesCalls++;
    return refreshShareesHandler?.call(collectionID) ??
        Future.value(const <User>[]);
  }
}

DioException _dioException(int statusCode) {
  final requestOptions = RequestOptions(path: '/collections/unshare');
  return DioException(
    requestOptions: requestOptions,
    response: Response(requestOptions: requestOptions, statusCode: statusCode),
  );
}
