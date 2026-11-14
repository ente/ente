import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:locker/services/collections/models/collection.dart';

class SelectedCollections extends ChangeNotifier {
  final collections = <Collection>{};

  void toggleSelection(Collection collectionToToggle) {
    final Collection? alreadySelected = collections.firstWhereOrNull(
      (element) => element.id == collectionToToggle.id,
    );
    if (alreadySelected != null) {
      collections.remove(alreadySelected);
    } else {
      collections.add(collectionToToggle);
    }
    notifyListeners();
  }

  void select(Set<Collection> collectionsToSelect) {
    collections.addAll(collectionsToSelect);
    notifyListeners();
  }

  bool isCollectionSelected(Collection collection) {
    return collections.any((element) => element.id == collection.id);
  }

  void clearAll() {
    if (collections.isEmpty) return;
    collections.clear();
    notifyListeners();
  }

  void retainSelection(Iterable<Collection> availableCollections) {
    if (collections.isEmpty) return;
    final selected = availableCollections.where(collections.contains).toSet();
    if (selected.length == collections.length &&
        selected.every((c) => identical(collections.lookup(c), c))) {
      return;
    }
    collections
      ..clear()
      ..addAll(selected);
    notifyListeners();
  }

  bool get hasSelections => collections.isNotEmpty;

  int get count => collections.length;
}
