import 'package:locker/services/collections/models/collection.dart';

class CollectionSortUtil {
  static void sortCollections(List<Collection> collections) {
    collections.sort((a, b) {
      if (a.type == CollectionType.favorites &&
          b.type != CollectionType.favorites) {
        return -1;
      }
      if (b.type == CollectionType.favorites &&
          a.type != CollectionType.favorites) {
        return 1;
      }
      final nameA = a.name ?? a.name ?? '';
      final nameB = b.name ?? b.name ?? '';
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });
  }

  static List<Collection> getSortedCollections(List<Collection> collections) {
    final sortedList = List<Collection>.from(collections);
    sortCollections(sortedList);
    return sortedList;
  }

  static List<Collection> filterAndSortCollections(
    List<Collection> collections,
    int userID,
  ) {
    final filtered = collections
        .where(
          (c) => c.type != CollectionType.uncategorized || !c.isOwner(userID),
        )
        .toList();
    sortCollections(filtered);
    return filtered;
  }

  static int compareCollections(Collection a, Collection b) {
    if (a.type == CollectionType.favorites &&
        b.type != CollectionType.favorites) {
      return -1;
    }
    if (b.type == CollectionType.favorites &&
        a.type != CollectionType.favorites) {
      return 1;
    }
    final nameA = a.name ?? a.name ?? '';
    final nameB = b.name ?? b.name ?? '';
    return nameA.toLowerCase().compareTo(nameB.toLowerCase());
  }

  static int compareCollectionsWithFavoritesPriority(
    Collection a,
    Collection b,
    bool ascending,
  ) {
    if (a.type == CollectionType.favorites &&
        b.type != CollectionType.favorites) {
      return -1;
    }
    if (b.type == CollectionType.favorites &&
        a.type != CollectionType.favorites) {
      return 1;
    }
    return ascending ? compareCollections(a, b) : compareCollections(b, a);
  }

  static int compareCollectionsByDateWithFavoritesPriority(
    Collection a,
    Collection b,
    bool ascending,
  ) {
    if (a.type == CollectionType.favorites &&
        b.type != CollectionType.favorites) {
      return -1;
    }
    if (b.type == CollectionType.favorites &&
        a.type != CollectionType.favorites) {
      return 1;
    }
    final dateA = DateTime.fromMicrosecondsSinceEpoch(a.updationTime);
    final dateB = DateTime.fromMicrosecondsSinceEpoch(b.updationTime);
    return ascending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
  }
}
