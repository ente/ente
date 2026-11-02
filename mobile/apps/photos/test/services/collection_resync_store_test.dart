import 'package:flutter_test/flutter_test.dart';
import 'package:photos/services/collection_resync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'full resync survives old cursor writes, restart and stale completion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = CollectionResyncStore(preferences);
      await store.request(42);
      final first = store.generation(42)!;

      await preferences.setInt('collection_sync_time_42', 999);
      final restarted = CollectionResyncStore(preferences);
      expect(restarted.generation(42), first);

      await restarted.request(42);
      final latest = restarted.generation(42)!;
      expect(latest, greaterThan(first));
      await restarted.complete(42, first);
      expect(restarted.generation(42), latest);

      await restarted.request(43);
      await restarted.complete(42, latest);
      expect(restarted.generation(42), isNull);
      expect(restarted.generation(43), isNotNull);
      expect(preferences.getInt('collection_sync_time_42'), 999);
    },
  );
}
