import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/module/download/file.dart";

int getNextMemoryIndex(List<Memory> memories) {
  int lastSeenIndex = 0;
  int lastSeenTimestamp = 0;
  for (var index = 0; index < memories.length; index++) {
    final memory = memories[index];
    if (!memory.isSeen()) {
      return index;
    } else {
      if (memory.seenTime() > lastSeenTimestamp) {
        lastSeenIndex = index;
        lastSeenTimestamp = memory.seenTime();
      }
    }
  }
  if (lastSeenIndex == memories.length - 1) {
    return 0;
  }
  return lastSeenIndex + 1;
}

// Limit warming to above-the-fold covers to avoid runaway downloads.
const int kMemoryCoverWarmCap = 20;

// Warm originals so opening a memory does not fall back to its thumbnail.
Future<void> warmMemoryCovers(
  List<List<Memory>> memoryLists, {
  required bool Function() stillActive,
  int cap = kMemoryCoverWarmCap,
}) async {
  for (final memories in memoryLists.take(cap)) {
    if (!stillActive()) return;
    if (memories.isEmpty) continue;
    final file = memories[getNextMemoryIndex(memories)].file;
    if (file.fileType == FileType.video) continue;
    try {
      await getFile(file);
    } catch (_) {
      // best-effort warming; ignore and move on
    }
  }
}
