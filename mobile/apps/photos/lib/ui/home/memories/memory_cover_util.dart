import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/module/download/file.dart";

// The index inside a memory's file list that should be shown first to the
// user: the first unseen file, or the one after the most recently seen if all
// have been seen (wrapping to 0 once the last one was seen).
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

// Cap on how many memory covers to warm on a single pass. Sized against a
// typical above-the-fold strip; prevents runaway bandwidth when there is a
// large backlog of unseen memories.
const int kMemoryCoverWarmCap = 20;

// Sequentially warm the "cover" file of each memory so a subsequent tap
// opens to a full original instead of a thumbnail. Routes through [getFile],
// which internally handles remote download, local asset resolution (including
// iCloud-optimized fetch on iOS), and cache hits. Best-effort: swallows
// per-file errors and skips videos. [stillActive] is checked between files
// so the caller can cancel on unmount or a newer pass.
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
