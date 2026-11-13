import "package:photos/core/cache/lru_map.dart";
import "package:photos/models/file/file.dart";

final originFetchTracker = OriginFetchTracker();

typedef OriginFetchComparison = ({
  int modificationTimeAtFetch,
  int? observedModificationTime,
  bool shouldSkip,
});

class OriginFetchTracker {
  OriginFetchTracker({int capacity = 200})
    : _modificationTimes = LRUMap(capacity);

  final LRUMap<String, int> _modificationTimes;

  void record({required String? localID, required int? modificationTime}) {
    if (localID == null || modificationTime == null) return;
    _modificationTimes.put(localID, modificationTime);
  }

  bool isUnchangedSinceFetch(EnteFile file) {
    return comparisonFor(file)?.shouldSkip ?? false;
  }

  OriginFetchComparison? comparisonFor(EnteFile file) {
    final localID = file.localID;
    if (localID == null) return null;
    final modificationTimeAtFetch = _modificationTimes.get(localID);
    if (modificationTimeAtFetch == null) return null;
    final observedModificationTime = file.modificationTime;
    return (
      modificationTimeAtFetch: modificationTimeAtFetch,
      observedModificationTime: observedModificationTime,
      shouldSkip: modificationTimeAtFetch == observedModificationTime,
    );
  }
}
