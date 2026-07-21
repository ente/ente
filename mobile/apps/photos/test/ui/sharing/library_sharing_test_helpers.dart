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
  Completer<void>? shareGate;
  Completer<List<Collection>>? loadGate;
  Object? loadFailure;
  int publicKeyRequests = 0;

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
  Future<String?> getPublicKey(String email) async {
    publicKeyRequests++;
    return 'public-key';
  }

  @override
  Future<void> shareAlbum({
    required Collection collection,
    required String email,
    required String publicKey,
    required CollectionParticipantRole role,
  }) async {
    sharedIDs.add(collection.id);
    sharedRoles.add(role);
    await shareGate?.future;
    final failure = shareFailures[collection.id];
    if (failure != null) {
      throw failure;
    }
    collection.sharees.removeWhere(
      (sharee) => sharee.id == librarySharingTestRecipient.userID,
    );
    collection.sharees.add(
      User(
        id: librarySharingTestRecipient.userID,
        email: email,
        role: role.toStringVal(),
      ),
    );
  }

  @override
  Future<void> unshareAlbum({
    required Collection collection,
    required int recipientUserID,
    required String email,
  }) async {
    unsharedIDs.add(collection.id);
    collection.sharees.removeWhere((sharee) => sharee.id == recipientUserID);
  }
}

Collection librarySharingTestAlbum(
  int id, {
  CollectionParticipantRole? recipientRole,
  int ownerID = 1,
  CollectionType type = CollectionType.album,
  bool isDeleted = false,
}) {
  return Collection(
    id,
    User(id: ownerID, email: 'owner@example.com'),
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
    isDeleted: isDeleted,
  );
}
