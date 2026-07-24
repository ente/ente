import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';

import 'library_sharing_test_helpers.dart';

void main() {
  test('derives existing and mixed roles by recipient user ID', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
      librarySharingTestAlbum(
        2,
        recipientRole: CollectionParticipantRole.admin,
      ),
      librarySharingTestAlbum(3),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );

    await controller.load();
    expect(controller.isFirstTime, isFalse);
    expect(controller.activeRoleFor(1), CollectionParticipantRole.viewer);
    expect(controller.activeRoleFor(3), isNull);

    controller.enterManageMode();
    controller.toggleSelection(repository.albums[0]);
    controller.toggleSelection(repository.albums[1]);
    expect(controller.selectedRole, isNull);
  });

  test('separates shared management from the unshared album picker', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
      librarySharingTestAlbum(2),
      librarySharingTestAlbum(
        3,
        recipientRole: CollectionParticipantRole.admin,
      ),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );

    await controller.load();
    expect(controller.visibleAlbums.map((album) => album.id), [1, 3]);

    controller.enterAddMode();
    expect(controller.isAddingAlbums, isTrue);
    expect(controller.visibleAlbums.map((album) => album.id), [2]);
    controller.selectAll();
    expect(controller.selectedIDs, {2});

    controller.exitSelectionMode();
    expect(controller.visibleAlbums.map((album) => album.id), [1, 3]);

    controller.enterManageMode();
    expect(controller.isAddingAlbums, isFalse);
    expect(controller.visibleAlbums.map((album) => album.id), [1, 3]);
    controller.selectAll();
    expect(controller.selectedIDs, {1, 3});
  });

  test('returns to the overview when manage selection becomes empty', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();

    controller.enterManageMode();
    controller.toggleSelection(repository.albums.single);
    controller.toggleSelection(repository.albums.single);
    expect(controller.isSelecting, isFalse);

    controller.enterManageMode();
    controller.selectAll();
    controller.clearSelection();
    expect(controller.isSelecting, isFalse);
  });

  test('shares a new album and returns to the shared overview', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
      librarySharingTestAlbum(2),
      librarySharingTestAlbum(3),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterAddMode();
    controller.toggleSelection(repository.albums[1]);
    controller.setRoleForSelection(CollectionParticipantRole.collaborator);

    expect(await controller.applySelection(), isTrue);
    expect(repository.publicKeyRequests, 1);
    expect(repository.sharedIDs, [2]);
    expect(controller.activeRoleFor(1), CollectionParticipantRole.viewer);
    expect(controller.activeRoleFor(2), CollectionParticipantRole.collaborator);
    expect(controller.selectedIDs, isEmpty);
    expect(controller.isSelecting, isFalse);
    expect(controller.visibleAlbums.map((album) => album.id), [1, 2]);
  });

  test('retains only failed albums for an exact retry', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(1),
      librarySharingTestAlbum(2),
      librarySharingTestAlbum(
        3,
        recipientRole: CollectionParticipantRole.admin,
      ),
    ])..shareFailures[2] = StateError('failed');
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterAddMode();
    controller.selectAll();

    expect(await controller.applySelection(), isFalse);
    expect(controller.selectedIDs, {2});
    expect(controller.failedCount, 1);
    expect(controller.activeRoleFor(1), CollectionParticipantRole.admin);
    expect(controller.activeRoleFor(2), isNull);

    repository.shareFailures.clear();
    expect(await controller.applySelection(), isTrue);
    expect(repository.sharedIDs, [1, 2, 2]);
  });

  test('updates the role of a selected existing share', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
      librarySharingTestAlbum(2),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterManageMode();
    controller.toggleSelection(repository.albums[0]);
    controller.setRoleForSelection(CollectionParticipantRole.collaborator);

    expect(await controller.applySelection(), isTrue);
    expect(repository.sharedIDs, [1]);
    expect(controller.activeRoleFor(1), CollectionParticipantRole.collaborator);
    expect(controller.visibleAlbums.map((album) => album.id), [1]);
  });

  test('drops selections that no longer belong to the active mode', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(1),
      librarySharingTestAlbum(
        2,
        recipientRole: CollectionParticipantRole.viewer,
      ),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterAddMode();
    controller.toggleSelection(repository.albums[0]);

    await repository.shareAlbum(
      collection: repository.albums[0],
      email: librarySharingTestRecipient.email,
      publicKey: 'public-key',
      role: CollectionParticipantRole.viewer,
    );
    await controller.load();

    expect(controller.selectedIDs, isEmpty);
    expect(controller.visibleAlbums, isEmpty);
  });

  test('stops sharing only selected active shares', () async {
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.admin,
      ),
      librarySharingTestAlbum(2),
    ]);
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.enterManageMode();
    controller.selectAll();

    expect(controller.selectedActiveShareCount, 1);
    expect(await controller.stopSharingSelected(), isTrue);
    expect(repository.unsharedIDs, [1]);
    expect(controller.activeRoleFor(1), isNull);
    expect(controller.isFirstTime, isTrue);
  });

  test('freezes selection and roles while a batch is running', () async {
    final gate = Completer<void>();
    final repository = FakeLibrarySharingRepository([
      librarySharingTestAlbum(1),
      librarySharingTestAlbum(2),
    ])..shareGate = gate;
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );
    await controller.load();
    controller.toggleSelection(repository.albums[0]);

    final apply = controller.applySelection();
    expect(controller.isMutating, isTrue);
    controller.toggleSelection(repository.albums[1]);
    controller.selectAll();
    controller.setRoleForSelection(CollectionParticipantRole.viewer);

    expect(controller.selectedIDs, {1});
    expect(controller.stagedRoleFor(1), CollectionParticipantRole.admin);

    gate.complete();
    expect(await apply, isTrue);
    expect(repository.sharedRoles, [CollectionParticipantRole.admin]);
  });

  test(
    'does not retry successful writes when the local refresh fails',
    () async {
      final repository = FakeLibrarySharingRepository([
        librarySharingTestAlbum(1),
      ]);
      final controller = LibrarySharingController(
        recipient: librarySharingTestRecipient,
        repository: repository,
      );
      await controller.load();
      controller.selectAll();
      repository.loadFailure = StateError('refresh failed');

      expect(await controller.applySelection(), isTrue);
      expect(controller.selectedIDs, isEmpty);
      expect(controller.activeRoleFor(1), CollectionParticipantRole.admin);
      expect(repository.sharedIDs, [1]);
    },
  );

  test('can be disposed while an album load is in flight', () async {
    final loadGate = Completer<List<Collection>>();
    final repository = FakeLibrarySharingRepository(const [])
      ..loadGate = loadGate;
    final controller = LibrarySharingController(
      recipient: librarySharingTestRecipient,
      repository: repository,
    );

    final load = controller.load();
    controller.dispose();
    loadGate.complete(const []);

    await expectLater(load, completes);
  });
}
