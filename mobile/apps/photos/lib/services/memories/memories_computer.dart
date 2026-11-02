import "package:photos/models/base_location.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/smart_memory.dart";

class MemoriesResult {
  final List<SmartMemory> memories;
  final List<BaseLocation> baseLocations;
  final bool failed;

  MemoriesResult(this.memories, this.baseLocations, {this.failed = false});

  MemoriesResult.failed()
    : memories = const <SmartMemory>[],
      baseLocations = const <BaseLocation>[],
      failed = true;

  bool get isEmpty => memories.isEmpty;
}

abstract interface class MemoriesComputer {
  Future<bool> isMlReady();

  Future<({MemoriesResult current, MemoriesResult next})> computeCurrentAndNext(
    DateTime current,
    DateTime next,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  });

  Future<MemoriesResult> computeAll(
    DateTime now,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  });

  Future<List<SmartMemory>> computeSimple();
}
