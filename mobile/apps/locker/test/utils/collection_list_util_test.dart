import 'package:ente_sharing/models/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/utils/collection_list_util.dart';

Collection collection(
  int id,
  int ownerID,
  CollectionType type,
  String? name,
) => Collection(
  id,
  User(id: ownerID, email: '$ownerID@example.com'),
  '',
  null,
  name,
  null,
  null,
  type,
  CollectionAttributes(),
  [if (ownerID != 1) User(id: 1, email: '1@example.com', role: 'COLLABORATOR')],
  const [],
  0,
);

void main() {
  for (final (type, name) in const [
    (CollectionType.favorites, null),
    (CollectionType.folder, 'Documents'),
  ]) {
    group('$type default', () {
      final foreign = collection(1, 2, type, name);
      final owned = collection(2, 1, type, name ?? 'Renamed favorite');
      final wrongType = collection(3, 1, CollectionType.uncategorized, name);

      Collection? select(Iterable<Collection> collections) =>
          findOwnedCollection(collections, ownerID: 1, type: type, name: name);

      test(
        'selects the owned match over an incoming collaborator collection',
        () {
          expect(foreign.canAdd(1), isTrue);
          expect(select([foreign, wrongType, owned]), same(owned));
        },
      );

      test('returns no match when only an incoming collection exists', () {
        expect(select([foreign]), isNull);
      });
    });
  }

  test('Documents requires its exact folder name', () {
    expect(
      findOwnedCollection(
        [collection(1, 1, CollectionType.folder, 'Other')],
        ownerID: 1,
        type: CollectionType.folder,
        name: 'Documents',
      ),
      isNull,
    );
  });
}
