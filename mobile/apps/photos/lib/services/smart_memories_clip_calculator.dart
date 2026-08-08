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
      final scoredFiles = <({EnteFile file, int fileID, double similarity})>[];
      for (final file in allFiles) {
        final fileID = SmartMemoriesService._memoryFileId(
          file,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        if (fileID == null) continue;
        final embedding = fileIDToImageEmbedding[fileID];
        if (embedding == null) continue;
        final similarity = embedding.vector.dot(activityVector);
        if (similarity > SmartMemoriesService._clipMemoryTypeQueryThreshold) {
          scoredFiles.add((file: file, fileID: fileID, similarity: similarity));
        }
      }
      w?.log('comparing embeddings for clipMemoryType $clipMemoryType');
      if (scoredFiles.length < 10) return null;
      scoredFiles.sort((a, b) => b.similarity.compareTo(a.similarity));
      final int limit = min(scoredFiles.length, 50);
      final topCandidates = scoredFiles.take(limit).toList();
      topCandidates.shuffle(Random());
      final selected = <({EnteFile file, int fileID, double similarity})>[];
      final selectedFileIDs = <int>[];
      final selectedCreationTimes = <int>[];
      int skipped = 0;
      for (final candidate in topCandidates) {
        if (selected.length >= 10) break;
        final creationTime = candidate.file.creationTime;
        if (SmartMemoriesService._isTooCloseInTime(
          creationTime,
          selectedCreationTimes,
        )) {
          skipped++;
          continue;
        }
        if (SmartMemoriesService._isNearDuplicate(
              candidate.fileID,
              selectedFileIDs,
              fileIDToImageEmbedding,
            ) &&
            (topCandidates.length - skipped) > 10) {
          skipped++;
          continue;
        }
        selected.add(candidate);
        selectedFileIDs.add(candidate.fileID);
        if (creationTime != null) {
          selectedCreationTimes.add(creationTime);
        }
      }
      selected.sort((a, b) => b.similarity.compareTo(a.similarity));
      return ClipMemory(
        selected
            .map((candidate) => Memory.fromFile(candidate.file, seenTimes))
            .toList(),
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
