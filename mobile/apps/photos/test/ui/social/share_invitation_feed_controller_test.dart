import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection_invitation.dart";
import "package:photos/ui/social/widgets/share_invitation_feed_controller.dart";

void main() {
  final invitation = CollectionInvitation(
    collectionID: 10,
    inviter: User(id: 1, email: "alice@example.com"),
    albumName: "Summer",
    sharedAt: 20,
  );

  test(
    "only a successful load while continuously visible marks seen",
    () async {
      var pending = Completer<List<CollectionInvitation>?>();
      final seen = <List<CollectionInvitation>>[];
      final controller = ShareInvitationFeedController(
        load: () => pending.future,
        markSeen: (snapshot) async => seen.add(snapshot.toList()),
      );

      final hiddenLoad = controller.refresh();
      controller.setVisible(true);
      pending.complete([invitation]);
      await hiddenLoad;
      expect(seen, isEmpty);

      pending = Completer<List<CollectionInvitation>?>();
      final interruptedLoad = controller.refresh();
      controller.setVisible(false);
      controller.setVisible(true);
      pending.complete([invitation]);
      await interruptedLoad;
      expect(seen, isEmpty);

      pending = Completer<List<CollectionInvitation>?>();
      final visibleLoad = controller.refresh();
      expect(seen, isEmpty);
      pending.complete([invitation]);
      await visibleLoad;
      expect(seen, [
        [invitation],
      ]);
    },
  );

  test(
    "failed and unsupported loads do not count as an empty snapshot",
    () async {
      var fail = true;
      List<CollectionInvitation>? response;
      final seen = <List<CollectionInvitation>>[];
      final controller = ShareInvitationFeedController(
        load: () async {
          if (fail) throw StateError("offline");
          return response;
        },
        markSeen: (snapshot) async => seen.add(snapshot.toList()),
      )..setVisible(true);

      await expectLater(controller.refresh(), throwsStateError);
      fail = false;
      await controller.refresh();
      expect(seen, isEmpty);

      response = [];
      await controller.refresh();
      expect(seen, [<CollectionInvitation>[]]);
    },
  );
}
