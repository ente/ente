import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class CollectionResyncStore {
  CollectionResyncStore(this._preferences);

  final SharedPreferences _preferences;

  String _key(int collectionID) => 'collection_full_resync_$collectionID';

  int? generation(int collectionID) => _preferences.getInt(_key(collectionID));

  Future<void> request(int collectionID) async {
    final next = max(
      DateTime.now().microsecondsSinceEpoch,
      (generation(collectionID) ?? 0) + 1,
    );
    if (!await _preferences.setInt(_key(collectionID), next)) {
      throw StateError('Could not request album resync');
    }
  }

  Future<void> complete(int collectionID, int completedGeneration) async {
    if (generation(collectionID) == completedGeneration) {
      if (!await _preferences.remove(_key(collectionID))) {
        throw StateError('Could not complete album resync');
      }
    }
  }
}
