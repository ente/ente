import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/gateways/collections/models/collection_share.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/metadata/common_keys.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/entity_service.dart';
import 'package:photos/services/library_sharing_service.dart';
import 'package:photos/services/library_sharing_store.dart';

import '../ui/sharing/library_sharing_test_helpers.dart';

void main() {
  test('batches automatic shares and shares uncategorized as viewer', () async {
    final albums = [
      for (var id = 1; id <= 100; id++) librarySharingTestAlbum(id),
      librarySharingTestAlbum(101, type: CollectionType.uncategorized),
    ];
    final fixture = await _Fixture.create(albums, blockedIDs: {100, 101});

    final result = await fixture.service.enableAutomaticSharing(
      recipient: librarySharingTestRecipient,
      role: CollectionParticipantRole.admin,
    );

    expect(result.failedIDs, isEmpty);
    expect(result.previouslyUnsharedIDs, {100, 101});
    expect(fixture.collectionsService.shareBatchSizes, [100, 1]);
    expect(
      fixture.collectionsService.sharedRoles[101],
      CollectionParticipantRole.viewer,
    );
    final config = await fixture.readConfig();
    expect(config.addedAutomatically.length, 99);
    expect(config.unsharedBefore, {100, 101});
  });

  test('hidden automatic shares remain until explicitly unshared', () async {
    final album = librarySharingTestAlbum(1);
    final fixture = await _Fixture.create([album]);
    await fixture.service.enableAutomaticSharing(
      recipient: librarySharingTestRecipient,
      role: CollectionParticipantRole.viewer,
    );

    album.mMdVersion = 1;
    album.mMdEncodedJson = '{"visibility":$hiddenVisibility}';
    await fixture.service.reconcile();

    var config = await fixture.readConfig();
    expect(config.hidden, {album.id});
    expect(config.addedAutomatically, {album.id});
    expect(album.sharees, isNotEmpty);

    await fixture.service.unshareAlbumFromAll(album);

    config = await fixture.readConfig();
    expect(config.addedAutomatically, isEmpty);
    expect(config.unsharedBefore, {album.id});
    expect(album.sharees, isEmpty);

    album.mMdEncodedJson = '{"visibility":$visibleVisibility}';
    await fixture.service.reconcile();

    config = await fixture.readConfig();
    expect(config.hidden, {album.id});
    expect(config.addedAutomatically, isEmpty);
    expect(album.sharees, isEmpty);
  });

  test(
    'stops automatic sharing when the recipient leaves the family',
    () async {
      final albums = [librarySharingTestAlbum(1)];
      final fixture = await _Fixture.create(
        albums,
        activeFamilyMemberUserIDs: {librarySharingTestRecipient.userID},
      );
      await fixture.service.enableAutomaticSharing(
        recipient: librarySharingTestRecipient,
        role: CollectionParticipantRole.viewer,
      );

      fixture.userService.activeFamilyMemberUserIDs = {};
      albums.add(librarySharingTestAlbum(2));
      await fixture.service.reconcile();

      expect(
        await fixture.service.isAutomaticSharingEnabled(
          librarySharingTestRecipient.userID,
        ),
        isFalse,
      );
      expect(albums.first.sharees, isNotEmpty);
      expect(albums.last.sharees, isEmpty);
    },
  );

  test('does not reconcile after a concurrent remote disable', () async {
    final album = librarySharingTestAlbum(1);
    final fixture = await _Fixture.create([album]);
    fixture.store._config = LibrarySharingConfig(
      recipientUserID: librarySharingTestRecipient.userID,
      enabled: true,
      defaultRole: CollectionParticipantRole.viewer,
    );
    fixture.store.disableOnNextWrite = true;

    await fixture.service.reconcile();

    expect(album.sharees, isEmpty);
  });

  test('stops bulk sharing on a recipient identity mismatch', () async {
    final albums = [
      for (var id = 1; id <= 101; id++) librarySharingTestAlbum(id),
    ];
    final fixture = await _Fixture.create(
      albums,
      shareError: RecipientIdentityMismatchError(),
    );

    await expectLater(
      fixture.service.enableAutomaticSharing(
        recipient: librarySharingTestRecipient,
        role: CollectionParticipantRole.viewer,
      ),
      throwsA(isA<RecipientIdentityMismatchError>()),
    );

    expect(fixture.collectionsService.shareBatchSizes, [100]);
  });

  test(
    'refreshes only for ineligible recipients and disables after removal',
    () async {
      final albums = [librarySharingTestAlbum(1)];
      final fixture = await _Fixture.create(
        albums,
        activeFamilyMemberUserIDs: {librarySharingTestRecipient.userID},
      );
      await fixture.service.enableAutomaticSharing(
        recipient: librarySharingTestRecipient,
        role: CollectionParticipantRole.viewer,
      );
      albums.addAll([
        for (var id = 2; id <= 102; id++) librarySharingTestAlbum(id),
      ]);

      fixture.collectionsService.shareError = StateError('ordinary failure');
      await fixture.service.reconcile();
      expect(fixture.userService.userDetailsFetches, 0);

      fixture.collectionsService.shareError =
          AutomaticShareRecipientNotEligibleError();
      fixture.userService.refreshedActiveFamilyMemberUserIDs = {
        librarySharingTestRecipient.userID,
      };
      await fixture.service.reconcile();
      expect(fixture.userService.userDetailsFetches, 1);
      expect(await fixture.isAutomaticSharingEnabled(), isTrue);

      fixture.userService.userDetailsError = StateError('refresh failed');
      await fixture.service.reconcile();
      expect(fixture.userService.userDetailsFetches, 2);
      expect(await fixture.isAutomaticSharingEnabled(), isTrue);

      fixture.userService.userDetailsError = null;
      fixture.userService.refreshedActiveFamilyMemberUserIDs = {};
      await fixture.service.reconcile();
      expect(fixture.userService.userDetailsFetches, 3);
      expect(await fixture.isAutomaticSharingEnabled(), isFalse);
      expect(albums.last.sharees, isEmpty);
    },
  );
}

class _Fixture {
  const _Fixture(
    this.service,
    this.collectionsService,
    this.store,
    this.userService,
  );

  final LibrarySharingService service;
  final _FakeCollectionsService collectionsService;
  final _MemoryLibrarySharingStore store;
  final _FakeUserService userService;

  static Future<_Fixture> create(
    List<Collection> albums, {
    Set<int> blockedIDs = const {},
    Set<int>? activeFamilyMemberUserIDs,
    Object? shareError,
  }) async {
    final collectionsService = _FakeCollectionsService(
      albums,
      blockedIDs,
      shareError,
    );
    final store = _MemoryLibrarySharingStore();
    final userService = _FakeUserService(activeFamilyMemberUserIDs);
    return _Fixture(
      LibrarySharingService(
        collectionsService: collectionsService,
        userService: userService,
        configuration: _FakeConfiguration(),
        store: store,
      ),
      collectionsService,
      store,
      userService,
    );
  }

  Future<LibrarySharingConfig> readConfig() async =>
      (await store.read(1, librarySharingTestRecipient.userID))!;

  Future<bool> isAutomaticSharingEnabled() =>
      service.isAutomaticSharingEnabled(librarySharingTestRecipient.userID);
}

class _MemoryLibrarySharingStore extends LibrarySharingEntityStore {
  _MemoryLibrarySharingStore() : super(_MockEntityService());

  LibrarySharingConfig? _config;
  bool disableOnNextWrite = false;

  @override
  Future<void> sync() async {}

  @override
  Future<LibrarySharingConfig?> read(
    int ownerUserID,
    int recipientUserID,
  ) async => _config?.recipientUserID == recipientUserID ? _config : null;

  @override
  Future<List<LibrarySharingConfig>> readAll(int ownerUserID) async => [
    ?_config,
  ];

  @override
  Future<LibrarySharingConfig> write(
    int ownerUserID,
    LibrarySharingConfig config,
  ) async {
    if (disableOnNextWrite) {
      config = config.copyWith(enabled: false);
      disableOnNextWrite = false;
    }
    _config = config;
    return config;
  }
}

class _MockEntityService extends Mock implements EntityService {}

class _FakeCollectionsService extends Mock implements CollectionsService {
  _FakeCollectionsService(this.albums, this.blockedIDs, this.shareError);

  final List<Collection> albums;
  final Set<int> blockedIDs;
  Object? shareError;
  final List<int> shareBatchSizes = [];
  final Map<int, CollectionParticipantRole> sharedRoles = {};

  @override
  List<Collection> getCollectionsForUI({
    bool includedShared = false,
    bool includeCollab = false,
    bool includeUncategorized = false,
  }) => albums;

  @override
  Future<List<Collection>> orderCollectionsForAlbums(
    Iterable<Collection> collections,
  ) async => collections.toList().reversed.toList();

  @override
  List<Collection> getActiveCollections() => albums;

  @override
  Future<Map<int, CollectionShareStatus>> shareBulk({
    required int recipientUserID,
    required String recipientEmail,
    required String publicKey,
    required Map<int, CollectionParticipantRole> roles,
    required CollectionShareSource source,
  }) async {
    shareBatchSizes.add(roles.length);
    if (shareError != null) {
      throw shareError!;
    }
    sharedRoles.addAll(roles);
    for (final entry in roles.entries) {
      if (blockedIDs.contains(entry.key)) {
        continue;
      }
      albums
          .firstWhere((album) => album.id == entry.key)
          .sharees
          .add(
            User(
              id: recipientUserID,
              email: recipientEmail,
              role: entry.value.toStringVal(),
            ),
          );
    }
    return {
      for (final collectionID in roles.keys)
        collectionID: blockedIDs.contains(collectionID)
            ? CollectionShareStatus.blockedPreviousRemoval
            : CollectionShareStatus.shared,
    };
  }

  @override
  Future<Map<int, CollectionShareStatus>> unshareBulk({
    required int recipientUserID,
    required List<int> collectionIDs,
    required CollectionShareSource source,
  }) async {
    for (final id in collectionIDs) {
      albums
          .firstWhere((album) => album.id == id)
          .sharees
          .removeWhere((sharee) => sharee.id == recipientUserID);
    }
    return {for (final id in collectionIDs) id: CollectionShareStatus.unshared};
  }

  @override
  Collection? getCollectionByID(int collectionID) =>
      albums.firstWhere((album) => album.id == collectionID);
}

class _FakeUserService extends Mock implements UserService {
  _FakeUserService(this.activeFamilyMemberUserIDs);

  Set<int>? activeFamilyMemberUserIDs;
  Set<int>? refreshedActiveFamilyMemberUserIDs;
  Object? userDetailsError;
  int userDetailsFetches = 0;

  @override
  Future<String?> getPublicKey(String email) async => 'public-key';

  @override
  List<UserSuggestion> getRelevantContacts() => [
    UserSuggestion(
      librarySharingTestRecipient.email,
      userID: librarySharingTestRecipient.userID,
    ),
  ];

  @override
  UserDetails? getCachedUserDetails() {
    final userIDs = activeFamilyMemberUserIDs;
    return userIDs == null ? null : _FakeUserDetails(userIDs);
  }

  @override
  Future<UserDetails> getUserDetailsV2({
    bool memoryCount = true,
    bool shouldCache = true,
  }) async {
    userDetailsFetches++;
    if (userDetailsError != null) {
      throw userDetailsError!;
    }
    final userIDs =
        refreshedActiveFamilyMemberUserIDs ??
        activeFamilyMemberUserIDs ??
        const {};
    activeFamilyMemberUserIDs = userIDs;
    return _FakeUserDetails(userIDs);
  }
}

class _FakeUserDetails extends Mock implements UserDetails {
  _FakeUserDetails(Set<int> activeFamilyMemberUserIDs)
    : familyData = FamilyData(
        [
          for (final userID in activeFamilyMemberUserIDs)
            FamilyMember(
              '$userID@example.com',
              0,
              '$userID',
              userID,
              false,
              FamilyMemberStatus.accepted,
              null,
            ),
        ],
        0,
        0,
        0,
      );

  @override
  final FamilyData familyData;
}

class _FakeConfiguration extends Mock implements Configuration {
  @override
  int? getUserID() => 1;
}
