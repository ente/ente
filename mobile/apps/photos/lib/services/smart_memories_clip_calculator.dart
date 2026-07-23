part of "smart_memories_service.dart";

class ClipMemoriesCalculator {
  static Future<List<ClipMemory>> compute(
    Iterable<EnteFile> allFiles,
    DateTime currentTime,
    List<ClipShownLog> shownClip, {
    bool surfaceAll = false,
    required bool isLocalGalleryMode,
    required Map<int, int> seenTimes,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Map<ClipMemoryType, Vector> clipMemoryTypeVectors,
  }) async {
    final w = (kDebugMode ? EnteWatch('getClipResults') : null)?..start();
    final List<ClipMemory> clipResults = [];
    if (allFiles.isEmpty) return [];
    final nowInMicroseconds = currentTime.microsecondsSinceEpoch;
    final windowEnd = currentTime
        .add(kMemoriesUpdateFrequency)
        .microsecondsSinceEpoch;
    w?.log('allFiles setup');

    ClipMemory? buildClipMemory(ClipMemoryType clipMemoryType) {
      final Vector? activityVector = clipMemoryTypeVectors[clipMemoryType];
      if (activityVector == null) {
        dev.log("No vector for clipMemoryType $clipMemoryType");
        return null;
      }
      final Map<int, double> similarities = {};
      for (final entry in fileIDToImageEmbedding.entries) {
        similarities[entry.key] = entry.value.vector.dot(activityVector);
      }
      w?.log('comparing embeddings for clipMemoryType $clipMemoryType');
      final List<EnteFile> clipFiles = [];
      for (final file in allFiles) {
        final memoryFileID = SmartMemoriesService._memoryFileId(
          file,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        if (memoryFileID == null) continue;
        final similarity = similarities[memoryFileID];
        if (similarity == null) continue;
        if (similarity > SmartMemoriesService._clipMemoryTypeQueryThreshold) {
          clipFiles.add(file);
        }
      }
      if (clipFiles.length < 10) return null;
      clipFiles.sort((a, b) {
        final int bFileID = SmartMemoriesService._memoryFileId(
          b,
          isLocalGalleryMode: isLocalGalleryMode,
        )!;
        final int aFileID = SmartMemoriesService._memoryFileId(
          a,
          isLocalGalleryMode: isLocalGalleryMode,
        )!;
        return similarities[bFileID]!.compareTo(similarities[aFileID]!);
      });
      final int limit = min(clipFiles.length, 50);
      final List<EnteFile> topCandidates = clipFiles.take(limit).toList();
      topCandidates.shuffle(Random());
      final List<EnteFile> selected = [];
      final selectedFileIDs = <int>[];
      final selectedCreationTimes = <int>[];
      int skipped = 0;
      for (final file in topCandidates) {
        if (selected.length >= 10) break;
        final fileID = SmartMemoriesService._memoryFileId(
          file,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        if (fileID == null) continue;
        final creationTime = file.creationTime;
        if (SmartMemoriesService._isTooCloseInTime(
          creationTime,
          selectedCreationTimes,
        )) {
          skipped++;
          continue;
        }
        if (SmartMemoriesService._isNearDuplicate(
              fileID,
              selectedFileIDs,
              fileIDToImageEmbedding,
            ) &&
            (topCandidates.length - skipped) > 10) {
          skipped++;
          continue;
        }
        selected.add(file);
        selectedFileIDs.add(fileID);
        if (creationTime != null) {
          selectedCreationTimes.add(creationTime);
        }
      }
      selected.sort((a, b) {
        final int bFileID = SmartMemoriesService._memoryFileId(
          b,
          isLocalGalleryMode: isLocalGalleryMode,
        )!;
        final int aFileID = SmartMemoriesService._memoryFileId(
          a,
          isLocalGalleryMode: isLocalGalleryMode,
        )!;
        return similarities[bFileID]!.compareTo(similarities[aFileID]!);
      });
      return ClipMemory(
        selected.map((f) => Memory.fromFile(f, seenTimes)).toList(),
        nowInMicroseconds,
        windowEnd,
        clipMemoryType,
      );
    }

    if (surfaceAll) {
      for (final clipMemoryType in ClipMemoryType.values) {
        final clipMemory = buildClipMemory(clipMemoryType);
        if (clipMemory != null) clipResults.add(clipMemory);
      }
      return clipResults;
    }

    final List<ClipMemoryType> rotationOrder = [...ClipMemoryType.values]
      ..shuffle();
    final List<ClipMemoryType> eligibleClipTypes = [];

    clipMemoriesLoop:
    for (final clipMemoryType in rotationOrder) {
      for (final shownLog in shownClip) {
        if (shownLog.clipMemoryType != clipMemoryType) continue;
        final shownDate = DateTime.fromMicrosecondsSinceEpoch(
          shownLog.lastTimeShown,
        );
        final bool seenRecently =
            currentTime.difference(shownDate) < kClipShowTimeout;
        if (seenRecently) continue clipMemoriesLoop;
      }
      eligibleClipTypes.add(clipMemoryType);
    }

    for (final clipMemoryType in eligibleClipTypes) {
      final clipMemory = buildClipMemory(clipMemoryType);
      if (clipMemory == null) continue;
      clipResults.add(clipMemory);
      break;
    }

    return clipResults;
  }
}
