import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';

class SelectedPeople extends ChangeNotifier {
  final personIds = <String>{};

  void toggleSelection(String personID) {
    final String? alreadySelected = personIds.firstWhereOrNull(
      (element) => element == personID,
    );
    if (alreadySelected != null) {
      personIds.remove(alreadySelected);
    } else {
      personIds.add(personID);
    }
    notifyListeners();
  }

  void select(Set<String> personToSelect) {
    personIds.addAll(personToSelect);
    notifyListeners();
  }

  void unSelect(Set<String> peopleToUnselect, {bool skipNotify = false}) {
    personIds.removeWhere((personID) => peopleToUnselect.contains(personID));
    if (!skipNotify) {
      notifyListeners();
    }
  }

  bool isPersonSelected(String personId) {
    return personIds.any((element) => element == personId);
  }

  void clearAll() {
    personIds.clear();
    notifyListeners();
  }
}
