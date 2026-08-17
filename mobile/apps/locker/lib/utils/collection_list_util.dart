import 'package:locker/services/collections/models/collection.dart';

List<Collection> uniqueCollectionsById(List<Collection> collections) {
  final seenIds = <int>{};
  return collections.where((collection) => seenIds.add(collection.id)).toList();
}

Collection? findUserUncategorizedCollection(
  Iterable<Collection> collections,
  int userID,
) {
  for (final collection in collections) {
    if (collection.type == CollectionType.uncategorized &&
        collection.isOwner(userID)) {
      return collection;
    }
  }
  return null;
}
