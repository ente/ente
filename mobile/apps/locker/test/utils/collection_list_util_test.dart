import "package:ente_sharing/models/user.dart";
import "package:flutter_test/flutter_test.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/utils/collection_list_util.dart";

void main() {
  test("keeps distinct uncategorized collections", () {
    final ownCollection = _uncategorizedCollection(1, 10);
    final sharedCollection = _uncategorizedCollection(2, 20);

    expect(
      uniqueCollectionsById([
        sharedCollection,
        ownCollection,
        sharedCollection,
      ]),
      [sharedCollection, ownCollection],
    );
  });

  test("finds the uncategorized collection owned by the user", () {
    final sharedCollection = _uncategorizedCollection(1, 20);
    final ownCollection = _uncategorizedCollection(2, 10);

    expect(
      findUserUncategorizedCollection([sharedCollection, ownCollection], 10),
      ownCollection,
    );
  });
}

Collection _uncategorizedCollection(int id, int ownerID) => Collection(
  id,
  User(id: ownerID, email: "owner@example.com"),
  "",
  null,
  "Uncategorized",
  null,
  null,
  CollectionType.uncategorized,
  CollectionAttributes(),
  const [],
  const [],
  0,
);
