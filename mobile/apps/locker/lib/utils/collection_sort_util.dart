import 'package:locker/services/collections/models/collection.dart';

/// Utility class for sorting collections with consistent logic across the app
class CollectionSortUtil {
  /// Sorts collections with Important (favorites) collection first, then alphabetically by name
  static void sortCollections(List<Collection> collections) {
    collections.sort((a, b) {
      // Important collection (favorites) should come first
      if (a.type == CollectionType.favorites &&
          b.type != CollectionType.favorites) {
        return -1;
      }
      if (b.type == CollectionType.favorites &&
          a.type != CollectionType.favorites) {
        return 1;
      }
      // For other collections, sort alphabetically by name
      final nameA = a.name ?? a.name ?? '';
      final nameB = b.name ?? b.name ?? '';
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });
  }

  /// Returns a new sorted list of collections with Important (favorites) first
  static List<Collection> getSortedCollections(List<Collection> collections) {
    final sortedList = List<Collection>.from(collections);
    sortCollections(sortedList);
    return sortedList;
  }

  /// Filters out the user's uncategorized collection and sorts the rest.
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

  /// Compares two collections for sorting, prioritizing Important collection
  /// Returns -1 if a should come before b, 1 if b should come before a, 0 if equal
  static int compareCollections(Collection a, Collection b) {
    // Important collection (favorites) should come first
    if (a.type == CollectionType.favorites &&
        b.type != CollectionType.favorites) {
      return -1;
    }
    if (b.type == CollectionType.favorites &&
        a.type != CollectionType.favorites) {
      return 1;
    }
    // For other collections, sort alphabetically by name
    final nameA = a.name ?? a.name ?? '';
    final nameB = b.name ?? b.name ?? '';
    return nameA.toLowerCase().compareTo(nameB.toLowerCase());
  }

  /// Compares two collections for sorting with Important always first regardless of sort direction
  /// Used for table sorting where Important should always be first
  static int compareCollectionsWithFavoritesPriority(
    Collection a,
    Collection b,
    bool ascending,
  ) {
    // Important collection (favorites) should always come first regardless of sort direction
    if (a.type == CollectionType.favorites &&
        b.type != CollectionType.favorites) {
      return -1;
    }
    if (b.type == CollectionType.favorites &&
        a.type != CollectionType.favorites) {
      return 1;
    }
    // For other collections, use normal comparison
    return ascending ? compareCollections(a, b) : compareCollections(b, a);
  }

  /// Compares two collections for date sorting with Important always first regardless of sort direction
  /// Used for table sorting where Important should always be first
  static int compareCollectionsByDateWithFavoritesPriority(
    Collection a,
    Collection b,
    bool ascending,
  ) {
    // Important collection (favorites) should always come first regardless of sort direction
    if (a.type == CollectionType.favorites &&
        b.type != CollectionType.favorites) {
      return -1;
    }
    if (b.type == CollectionType.favorites &&
        a.type != CollectionType.favorites) {
      return 1;
    }
    // For other collections, sort by modification time
    final dateA = DateTime.fromMicrosecondsSinceEpoch(a.updationTime);
    final dateB = DateTime.fromMicrosecondsSinceEpoch(b.updationTime);
    return ascending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
  }
}
