import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/library_sharing_service.dart';

import '../ui/sharing/library_sharing_test_helpers.dart';

void main() {
  test('sharedAlbumCounts ignores unsupported participant roles', () {
    final collectionsService = _MockCollectionsService();
    final supportedAlbum = librarySharingTestAlbum(
      1,
      recipientRole: CollectionParticipantRole.viewer,
    );
    final unsupportedAlbum = librarySharingTestAlbum(
      2,
      recipientRole: CollectionParticipantRole.viewer,
    );
    unsupportedAlbum.sharees.single.role = 'EDITOR';
    collectionsService.collectionsForUI = [supportedAlbum, unsupportedAlbum];

    expect(
      LibrarySharingService(
        collectionsService: collectionsService,
      ).sharedAlbumCounts({librarySharingTestRecipient.userID}),
      {librarySharingTestRecipient.userID: 1},
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
  List<Collection> collectionsForUI = const [];
  late Future<List<User>> Function(int collectionID, String email)
  unshareHandler;
  Future<List<User>> Function(int collectionID)? refreshShareesHandler;
  int refreshShareesCalls = 0;

  @override
  List<Collection> getCollectionsForUI({
    bool includedShared = false,
    bool includeCollab = false,
    bool includeUncategorized = false,
  }) => collectionsForUI;

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
