import 'dart:async';

import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/library_sharing/library_sharing_recipient.dart';
import 'package:photos/services/library_sharing_service.dart';

const librarySharingTestRecipient = LibrarySharingRecipient(
  userID: 42,
  email: 'friend@example.com',
  displayName: 'Friend',
);

class FakeLibrarySharingRepository implements LibrarySharingRepository {
  FakeLibrarySharingRepository(this.albums, {this.loadGate});

  final List<Collection> albums;
  final Map<int, Object> shareFailures = {};
  final List<int> sharedIDs = [];
  final List<int> unsharedIDs = [];
  final List<CollectionParticipantRole> sharedRoles = [];
  final Set<int> automaticSharingBlockedIDs = {};
  Completer<void>? shareGate;
  Completer<List<Collection>>? loadGate;
  Object? loadFailure;
  bool automaticSharingEnabled = false;

  @override
  Future<List<Collection>> getEligibleAlbums() async {
    final gate = loadGate;
    if (gate != null) {
      return gate.future;
    }
    final failure = loadFailure;
    if (failure != null) {
      throw failure;
    }
    return albums;
  }

  @override
  Future<Set<int>> shareAlbums({
    required LibrarySharingRecipient recipient,
    required Map<int, CollectionParticipantRole> roles,
  }) async {
    await shareGate?.future;
    final failedIDs = <int>{};
    for (final entry in roles.entries) {
      sharedIDs.add(entry.key);
      sharedRoles.add(entry.value);
      if (shareFailures.containsKey(entry.key)) {
        failedIDs.add(entry.key);
        continue;
      }
      final collection = albums.firstWhere((album) => album.id == entry.key);
      collection.sharees.removeWhere((sharee) => sharee.id == recipient.userID);
      collection.sharees.add(
        User(
          id: recipient.userID,
          email: recipient.email,
          role: entry.value.toStringVal(),
        ),
      );
    }
    return failedIDs;
  }

  @override
  Future<Set<int>> unshareAlbums({
    required int recipientUserID,
    required List<int> collectionIDs,
  }) async {
    for (final id in collectionIDs) {
      unsharedIDs.add(id);
      albums
          .firstWhere((album) => album.id == id)
          .sharees
          .removeWhere((sharee) => sharee.id == recipientUserID);
    }
    return const {};
  }

  @override
  Future<bool> isAutomaticSharingEnabled(int recipientUserID) async =>
      automaticSharingEnabled;

  @override
  Future<EnableAutomaticSharingResult> enableAutomaticSharing({
    required LibrarySharingRecipient recipient,
    required CollectionParticipantRole role,
  }) async {
    final failures = await shareAlbums(
      recipient: recipient,
      roles: {
        for (final album in albums)
          if (librarySharingRoleFor(album, recipient.userID) == null &&
              !automaticSharingBlockedIDs.contains(album.id))
            album.id: role,
      },
    );
    automaticSharingEnabled = failures.isEmpty;
    return (
      failedIDs: failures,
      previouslyUnsharedIDs: automaticSharingBlockedIDs,
    );
  }

  @override
  Future<void> disableAutomaticSharing(int recipientUserID) async {
    automaticSharingEnabled = false;
  }
}

Collection librarySharingTestAlbum(
  int id, {
  CollectionParticipantRole? recipientRole,
  CollectionType type = CollectionType.album,
}) {
  return Collection(
    id,
    User(id: 1, email: 'owner@example.com'),
    '',
    null,
    'Album $id',
    null,
    null,
    type,
    CollectionAttributes(),
    [
      if (recipientRole != null)
        User(
          id: librarySharingTestRecipient.userID,
          email: librarySharingTestRecipient.email,
          role: recipientRole.toStringVal(),
        ),
    ],
    [],
    id,
  );
}
