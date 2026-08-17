import "dart:developer" as dev show log;
import "dart:math" show Random, max;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:ml_linalg/vector.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/location_service.dart";

enum SelectionDistribution { none, timeBuckets, yearRoundRobin }

enum SelectionPick { ranked, geographicFarthest }

enum SelectionSort { chronological, reverseChronological }

class SelectionConfig {
  final int targetSize;
  final bool isLocalGalleryMode;
  final Map<int, EmbeddingVector> fileIDToImageEmbedding;

  final Map<int, double> scores;

  final SelectionDistribution distribution;
  final SelectionPick pick;
  final SelectionSort sort;

  // Fraction of each bucket to retain; 0.3 means 30%.
  final double? preNarrowTopPercent;

  final bool skipDuplicateCheckOnFirstRound;

  const SelectionConfig({
    required this.targetSize,
    required this.isLocalGalleryMode,
    required this.fileIDToImageEmbedding,
    required this.scores,
    required this.distribution,
    required this.pick,
    required this.sort,
    this.preNarrowTopPercent,
    this.skipDuplicateCheckOnFirstRound = false,
  });
}

class PhotoSelector {
  static const clipSimilarImageThreshold = 0.80;
  static const minimumMemoryTimeGap = Duration(minutes: 10);

  static Future<List<Memory>> select(
    List<Memory> memories,
    SelectionConfig config,
  ) async {
    if (memories.length < config.targetSize) return memories;
    if (memories.length == config.targetSize &&
        config.distribution != SelectionDistribution.yearRoundRobin) {
      return memories;
    }

    final List<Memory> result;
    switch (config.distribution) {
      case SelectionDistribution.none:
        result = _selectFlat(memories, config);
      case SelectionDistribution.timeBuckets:
        result = _selectTimeBuckets(memories, config);
      case SelectionDistribution.yearRoundRobin:
        result = _selectYearRoundRobin(memories, config);
    }

    return _sortResult(result, config.sort);
  }

  static List<Memory> _selectFlat(
    List<Memory> memories,
    SelectionConfig config,
  ) {
    final fileCount = memories.length;
    memories.sort((a, b) {
      final aID = memoryFileIdFromMemory(
        a,
        isLocalGalleryMode: config.isLocalGalleryMode,
      );
      final bID = memoryFileIdFromMemory(
        b,
        isLocalGalleryMode: config.isLocalGalleryMode,
      );
      return (config.scores[bID] ?? 0.0).compareTo(config.scores[aID] ?? 0.0);
    });

    final selected = <Memory>[memories.first];
    final selectedCreationTimes = <int>[];
    final firstCreationTime = memories.first.file.creationTime;
    if (firstCreationTime != null) {
      selectedCreationTimes.add(firstCreationTime);
    }
    int skipped = 0;

    for (final mem in memories.sublist(1)) {
      if (selected.length >= config.targetSize) break;
      if (!_passesFilters(
        mem,
        selected,
        selectedCreationTimes,
        config,
        fileCount: fileCount,
        skipped: skipped,
      )) {
        skipped++;
        continue;
      }
      selected.add(mem);
      final ct = mem.file.creationTime;
      if (ct != null) selectedCreationTimes.add(ct);
    }

    return selected;
  }

  static List<Memory> _selectTimeBuckets(
    List<Memory> memories,
    SelectionConfig config,
  ) {
    final sorted = memories.where((m) => m.file.creationTime != null).toList()
      ..sort((a, b) => a.file.creationTime!.compareTo(b.file.creationTime!));

    if (sorted.length < config.targetSize) return sorted;

    final minCreationTime = sorted.first.file.creationTime!;
    final maxCreationTime = sorted.last.file.creationTime!;
    if (minCreationTime == maxCreationTime) {
      return _selectFlat(sorted, config);
    }

    // Divide the full chronological range into equal time buckets so dense
    // periods do not dominate multiple buckets just because they have more
    // photos.
    final int numBuckets = config.targetSize;
    final int totalRange = maxCreationTime - minCreationTime + 1;
    final List<List<Memory>> buckets = List.generate(
      numBuckets,
      (_) => <Memory>[],
    );
    for (final mem in sorted) {
      final creationTime = mem.file.creationTime!;
      final bucketIndex =
          ((creationTime - minCreationTime) * numBuckets ~/ totalRange).clamp(
            0,
            numBuckets - 1,
          );
      buckets[bucketIndex].add(mem);
    }

    final finalSelection = <Memory>[];
    for (final bucket in buckets) {
      final bucketFileIDs = bucket
          .map(
            (m) => memoryFileIdFromMemory(
              m,
              isLocalGalleryMode: config.isLocalGalleryMode,
            ),
          )
          .whereType<int>()
          .toSet();
      final bucketVectors = getEmbeddingsForFileIDs(
        config.fileIDToImageEmbedding,
        bucketFileIDs,
      );
      // Score narrowing is unreliable when fewer than half have embeddings.
      final bool littleEmbeddings = bucketVectors.length < bucket.length * 0.5;

      bucket.sort((a, b) {
        final aID = memoryFileIdFromMemory(
          a,
          isLocalGalleryMode: config.isLocalGalleryMode,
        );
        final bID = memoryFileIdFromMemory(
          b,
          isLocalGalleryMode: config.isLocalGalleryMode,
        );
        return (config.scores[bID] ?? 0.0).compareTo(config.scores[aID] ?? 0.0);
      });

      List<Memory> candidates;
      if (!littleEmbeddings && config.preNarrowTopPercent != null) {
        final keep = max(
          bucket.length * config.preNarrowTopPercent!,
          1,
        ).toInt();
        candidates = bucket.take(keep).toList();
      } else {
        candidates = bucket;
      }

      if (candidates.isEmpty) {
        dev.log('No candidates in bucket');
        continue;
      }

      if (finalSelection.isNotEmpty) {
        final filteredCandidates = excludeNearDuplicates(
          candidates,
          finalSelection,
          config.fileIDToImageEmbedding,
          isLocalGalleryMode: config.isLocalGalleryMode,
        );
        if (filteredCandidates.isNotEmpty) {
          candidates = filteredCandidates;
        }
        candidates = excludeTooCloseInTime(candidates, finalSelection);
      }
      if (candidates.isEmpty) continue;

      final winner = _pickCandidate(candidates, finalSelection, config.pick);
      finalSelection.add(winner);
    }

    if (finalSelection.length >= config.targetSize) {
      return finalSelection;
    }

    final selectedFileIDs = finalSelection
        .map(
          (mem) => memoryFileIdFromMemory(
            mem,
            isLocalGalleryMode: config.isLocalGalleryMode,
          ),
        )
        .whereType<int>()
        .toSet();
    final remaining =
        sorted.where((mem) {
          final fileID = memoryFileIdFromMemory(
            mem,
            isLocalGalleryMode: config.isLocalGalleryMode,
          );
          return fileID == null || !selectedFileIDs.contains(fileID);
        }).toList()..sort((a, b) {
          final aID = memoryFileIdFromMemory(
            a,
            isLocalGalleryMode: config.isLocalGalleryMode,
          );
          final bID = memoryFileIdFromMemory(
            b,
            isLocalGalleryMode: config.isLocalGalleryMode,
          );
          return (config.scores[bID] ?? 0.0).compareTo(
            config.scores[aID] ?? 0.0,
          );
        });

    for (final candidate in remaining) {
      if (finalSelection.length >= config.targetSize) break;
      final filteredCandidates = excludeNearDuplicates(
        [candidate],
        finalSelection,
        config.fileIDToImageEmbedding,
        isLocalGalleryMode: config.isLocalGalleryMode,
      );
      if (filteredCandidates.isEmpty) continue;
      final timeFiltered = excludeTooCloseInTime(
        filteredCandidates,
        finalSelection,
      );
      if (timeFiltered.isEmpty) continue;
      finalSelection.add(timeFiltered.first);
    }

    return finalSelection;
  }

  static List<Memory> _selectYearRoundRobin(
    List<Memory> memories,
    SelectionConfig config,
  ) {
    final fileCount = memories.length;

    final yearToFiles = <int, List<Memory>>{};
    for (final mem in memories) {
      final year = DateTime.fromMicrosecondsSinceEpoch(
        mem.file.creationTime!,
      ).year;
      yearToFiles.putIfAbsent(year, () => []).add(mem);
    }

    for (final yearFiles in yearToFiles.values) {
      yearFiles.sort((a, b) {
        final aID = memoryFileIdFromMemory(
          a,
          isLocalGalleryMode: config.isLocalGalleryMode,
        );
        final bID = memoryFileIdFromMemory(
          b,
          isLocalGalleryMode: config.isLocalGalleryMode,
        );
        return (config.scores[bID] ?? 0.0).compareTo(config.scores[aID] ?? 0.0);
      });
    }

    final years = yearToFiles.keys.toList()..sort((a, b) => b.compareTo(a));

    final selected = <Memory>[];
    final selectedCreationTimes = <int>[];
    int round = 0;
    int skipped = 0;

    outerLoop:
    while (selected.length + skipped < fileCount) {
      for (final year in years) {
        final yearFiles = yearToFiles[year]!;
        if (yearFiles.isEmpty) continue;
        final candidate = yearFiles.removeAt(0);
        final creationTime = candidate.file.creationTime;

        if (isTooCloseInTime(creationTime, selectedCreationTimes)) {
          skipped++;
          continue;
        }

        // On round 0 skip duplicate check to guarantee year representation.
        final bool checkDuplicates =
            !(config.skipDuplicateCheckOnFirstRound && round == 0);
        if (checkDuplicates && (fileCount - skipped) > config.targetSize) {
          final candID = memoryFileIdFromMemory(
            candidate,
            isLocalGalleryMode: config.isLocalGalleryMode,
          );
          final clip = candID == null
              ? null
              : config.fileIDToImageEmbedding[candID];
          if (clip != null) {
            bool isDuplicate = false;
            for (final sel in selected) {
              final selID = memoryFileIdFromMemory(
                sel,
                isLocalGalleryMode: config.isLocalGalleryMode,
              );
              final selClip = selID == null
                  ? null
                  : config.fileIDToImageEmbedding[selID];
              if (selClip == null) continue;
              if (clip.vector.dot(selClip.vector) > clipSimilarImageThreshold) {
                isDuplicate = true;
                break;
              }
            }
            if (isDuplicate) {
              skipped++;
              continue;
            }
          }
        }

        selected.add(candidate);
        if (creationTime != null) selectedCreationTimes.add(creationTime);
        if (selected.length >= config.targetSize ||
            selected.length + skipped >= fileCount) {
          break outerLoop;
        }
      }
      round++;
      if (round > fileCount) break;
    }

    return selected;
  }

  static Memory _pickCandidate(
    List<Memory> candidates,
    List<Memory> alreadySelected,
    SelectionPick pick,
  ) {
    if (candidates.length == 1 || alreadySelected.isEmpty) {
      return candidates.first;
    }

    switch (pick) {
      case SelectionPick.ranked:
        return candidates.first;

      case SelectionPick.geographicFarthest:
        double globalMaxMinDistance = 0;
        int bestIdx = 0;
        for (var i = 0; i < candidates.length; i++) {
          final mem = candidates[i];
          double minDistance = double.infinity;
          for (final selected in alreadySelected) {
            if (selected.file.location == null || mem.file.location == null) {
              continue;
            }
            final distance = calculateDistance(
              mem.file.location!,
              selected.file.location!,
            );
            if (distance < minDistance) {
              minDistance = distance;
            }
          }
          if (minDistance > globalMaxMinDistance) {
            globalMaxMinDistance = minDistance;
            bestIdx = i;
          }
        }
        return candidates[bestIdx];
    }
  }

  static bool _passesFilters(
    Memory mem,
    List<Memory> selected,
    List<int> selectedCreationTimes,
    SelectionConfig config, {
    required int fileCount,
    required int skipped,
  }) {
    final creationTime = mem.file.creationTime;
    if (isTooCloseInTime(creationTime, selectedCreationTimes)) {
      return false;
    }
    final memFileID = memoryFileIdFromMemory(
      mem,
      isLocalGalleryMode: config.isLocalGalleryMode,
    );
    final clip = memFileID == null
        ? null
        : config.fileIDToImageEmbedding[memFileID];
    if (clip != null && (fileCount - skipped) > config.targetSize) {
      for (final selMem in selected) {
        final selID = memoryFileIdFromMemory(
          selMem,
          isLocalGalleryMode: config.isLocalGalleryMode,
        );
        final selClip = selID == null
            ? null
            : config.fileIDToImageEmbedding[selID];
        if (selClip == null) continue;
        if (clip.vector.dot(selClip.vector) > clipSimilarImageThreshold) {
          return false;
        }
      }
    }
    return true;
  }

  static List<Memory> _sortResult(List<Memory> memories, SelectionSort sort) {
    switch (sort) {
      case SelectionSort.chronological:
        memories.sort(
          (a, b) => a.file.creationTime!.compareTo(b.file.creationTime!),
        );
      case SelectionSort.reverseChronological:
        memories.sort(
          (a, b) => b.file.creationTime!.compareTo(a.file.creationTime!),
        );
    }
    return memories;
  }

  static Future<List<Memory>> bestSelectionPeople(
    List<Memory> memories, {
    int? prefferedSize,
    required bool isLocalGalleryMode,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) async {
    try {
      final w = (kDebugMode ? EnteWatch('getPeopleResults') : null)?..start();
      final int targetSize = prefferedSize ?? 10;
      if (memories.length <= targetSize) return memories;

      final Map<int, double> scores = {};
      for (final mem in memories) {
        final fileID = memoryFileIdFromMemory(
          mem,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        if (fileID == null) continue;

        final embedding = fileIDToImageEmbedding[fileID];
        if (embedding == null) continue;

        scores[fileID] = embedding.vector.dot(clipPositiveTextVector);
      }

      final result = await select(
        memories,
        SelectionConfig(
          targetSize: targetSize,
          isLocalGalleryMode: isLocalGalleryMode,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          scores: scores,
          distribution: SelectionDistribution.timeBuckets,
          pick: SelectionPick.geographicFarthest,
          sort: SelectionSort.reverseChronological,
          preNarrowTopPercent: 0.3,
        ),
      );

      dev.log(
        'People memories selection done, returning ${result.length} memories',
      );
      w?.log('People memories selection done');
      return result;
    } catch (e, s) {
      dev.log('Error in bestSelectionPeople $e \n $s');
      return [];
    }
  }

  static Future<List<Memory>> bestSelection(
    List<Memory> memories, {
    int? prefferedSize,
    SelectionDistribution? distributionOverride,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) async {
    final fileCount = memories.length;
    int targetSize = prefferedSize ?? 10;
    if (fileCount <= targetSize) return memories;

    if (!mlEnabled) {
      return _bestSelectionNoMl(
        memories,
        targetSize: targetSize,
        isLocalGalleryMode: isLocalGalleryMode,
        distributionOverride: distributionOverride,
      );
    }

    // Pre-compute combined score: face count * 1000 + CLIP nostalgia.
    // This replicates the original two-level stable sort (faces primary,
    // CLIP secondary) as a single numeric score.
    final Map<int, double> scores = {};
    for (final mem in memories) {
      final fileID = memoryFileIdFromMemory(
        mem,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      if (fileID == null) continue;

      final embedding = fileIDToImageEmbedding[fileID];
      final clipScore = embedding != null
          ? embedding.vector.dot(clipPositiveTextVector)
          : 0.0;

      int faceCount = 0;
      final faces = fileIdToFaces[fileID];
      if (faces != null) {
        for (final face in faces) {
          if (faceIDsToPersonID.containsKey(face.faceID)) {
            faceCount += 10;
          } else {
            faceCount += 1;
          }
        }
      }

      scores[fileID] = faceCount * 1000.0 + clipScore;
    }

    if (distributionOverride != null) {
      return select(
        memories,
        SelectionConfig(
          targetSize: targetSize,
          isLocalGalleryMode: isLocalGalleryMode,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          scores: scores,
          distribution: distributionOverride,
          pick: SelectionPick.ranked,
          sort: SelectionSort.chronological,
        ),
      );
    }

    final allYears = memories.map((e) {
      return DateTime.fromMicrosecondsSinceEpoch(e.file.creationTime!).year;
    }).toSet();

    if (allYears.length <= 1) {
      return select(
        memories,
        SelectionConfig(
          targetSize: targetSize,
          isLocalGalleryMode: isLocalGalleryMode,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          scores: scores,
          distribution: SelectionDistribution.none,
          pick: SelectionPick.ranked,
          sort: SelectionSort.chronological,
        ),
      );
    } else {
      if (prefferedSize == null && (allYears.length * 2) > 10) {
        targetSize = allYears.length * 3;
        if (fileCount < targetSize) return memories;
      }

      return select(
        memories,
        SelectionConfig(
          targetSize: targetSize,
          isLocalGalleryMode: isLocalGalleryMode,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          scores: scores,
          distribution: SelectionDistribution.yearRoundRobin,
          pick: SelectionPick.ranked,
          sort: SelectionSort.chronological,
          skipDuplicateCheckOnFirstRound: true,
        ),
      );
    }
  }

  static List<Memory> _bestSelectionNoMl(
    List<Memory> memories, {
    required int targetSize,
    required bool isLocalGalleryMode,
    SelectionDistribution? distributionOverride,
  }) {
    final withCreationTime = memories
        .where((m) => m.file.creationTime != null)
        .toList();
    if (withCreationTime.length <= targetSize) return withCreationTime;

    final random = Random();
    final allYears = withCreationTime
        .map(
          (e) => DateTime.fromMicrosecondsSinceEpoch(e.file.creationTime!).year,
        )
        .toSet();

    int effectiveTargetSize = targetSize;
    final List<Memory> sortedChronologically;

    if (distributionOverride == SelectionDistribution.timeBuckets ||
        (distributionOverride == null && allYears.length <= 1)) {
      sortedChronologically = List<Memory>.from(withCreationTime)
        ..sort((a, b) => a.file.creationTime!.compareTo(b.file.creationTime!));
      return _pickAcrossTimeBuckets(
        sortedChronologically,
        targetSize: effectiveTargetSize,
        random: random,
      );
    }

    if (distributionOverride == null && (allYears.length * 2) > 10) {
      effectiveTargetSize = allYears.length * 3;
      if (withCreationTime.length < effectiveTargetSize) {
        return withCreationTime;
      }
    }

    final yearToFiles = <int, List<Memory>>{};
    for (final mem in withCreationTime) {
      final year = DateTime.fromMicrosecondsSinceEpoch(
        mem.file.creationTime!,
      ).year;
      yearToFiles.putIfAbsent(year, () => []).add(mem);
    }
    for (final yearFiles in yearToFiles.values) {
      yearFiles.shuffle(random);
    }
    final years = yearToFiles.keys.toList()..sort((a, b) => b.compareTo(a));

    final selected = <Memory>[];
    final selectedCreationTimes = <int>[];
    final fileCount = withCreationTime.length;
    int skipped = 0;

    outerLoop:
    while (selected.length + skipped < fileCount) {
      for (final year in years) {
        final yearFiles = yearToFiles[year]!;
        if (yearFiles.isEmpty) continue;
        final candidate = yearFiles.removeAt(0);
        final creationTime = candidate.file.creationTime;
        if (isTooCloseInTime(creationTime, selectedCreationTimes)) {
          skipped++;
          continue;
        }
        selected.add(candidate);
        if (creationTime != null) selectedCreationTimes.add(creationTime);
        if (selected.length >= effectiveTargetSize ||
            selected.length + skipped >= fileCount) {
          break outerLoop;
        }
      }
    }

    selected.sort(
      (a, b) => a.file.creationTime!.compareTo(b.file.creationTime!),
    );
    return selected;
  }

  static List<Memory> _pickAcrossTimeBuckets(
    List<Memory> sorted, {
    required int targetSize,
    required Random random,
  }) {
    if (sorted.length <= targetSize) return sorted;
    final minCreationTime = sorted.first.file.creationTime!;
    final maxCreationTime = sorted.last.file.creationTime!;
    if (minCreationTime == maxCreationTime) {
      final shuffled = List<Memory>.from(sorted)..shuffle(random);
      return shuffled.take(targetSize).toList()
        ..sort((a, b) => a.file.creationTime!.compareTo(b.file.creationTime!));
    }
    final int numBuckets = targetSize;
    final int totalRange = maxCreationTime - minCreationTime + 1;
    final List<List<Memory>> buckets = List.generate(
      numBuckets,
      (_) => <Memory>[],
    );
    for (final mem in sorted) {
      final creationTime = mem.file.creationTime!;
      final bucketIndex =
          ((creationTime - minCreationTime) * numBuckets ~/ totalRange).clamp(
            0,
            numBuckets - 1,
          );
      buckets[bucketIndex].add(mem);
    }

    final selected = <Memory>[];
    final selectedCreationTimes = <int>[];
    for (final bucket in buckets) {
      if (bucket.isEmpty) continue;
      bucket.shuffle(random);
      Memory? chosen;
      for (final candidate in bucket) {
        if (!isTooCloseInTime(
          candidate.file.creationTime,
          selectedCreationTimes,
        )) {
          chosen = candidate;
          break;
        }
      }
      if (chosen == null) continue;
      selected.add(chosen);
      final ct = chosen.file.creationTime;
      if (ct != null) selectedCreationTimes.add(ct);
    }

    if (selected.length < targetSize) {
      final selectedSet = selected.toSet();
      for (final mem in sorted) {
        if (selected.length >= targetSize) break;
        if (selectedSet.contains(mem)) continue;
        if (isTooCloseInTime(mem.file.creationTime, selectedCreationTimes)) {
          continue;
        }
        selected.add(mem);
        final ct = mem.file.creationTime;
        if (ct != null) selectedCreationTimes.add(ct);
      }
    }

    selected.sort(
      (a, b) => a.file.creationTime!.compareTo(b.file.creationTime!),
    );
    return selected;
  }

  static List<EmbeddingVector> getEmbeddingsForFileIDs(
    Map<int, EmbeddingVector> fileIDToImageEmbedding,
    Set<int> fileIDs,
  ) {
    final List<EmbeddingVector> embeddings = [];
    for (final fileID in fileIDs) {
      final embedding = fileIDToImageEmbedding[fileID];
      if (embedding != null) embeddings.add(embedding);
    }
    return embeddings;
  }

  static bool isNearDuplicate(
    int fileID,
    Iterable<int> selectedFileIDs,
    Map<int, EmbeddingVector> fileIDToImageEmbedding, {
    double similarityThreshold = clipSimilarImageThreshold,
  }) {
    final candidate = fileIDToImageEmbedding[fileID];
    if (candidate == null) return false;
    for (final selectedID in selectedFileIDs) {
      final selected = fileIDToImageEmbedding[selectedID];
      if (selected == null) continue;
      final similarity = candidate.vector.dot(selected.vector);
      if (similarity > similarityThreshold) {
        return true;
      }
    }
    return false;
  }

  static int? memoryFileId(EnteFile file, {required bool isLocalGalleryMode}) {
    return isLocalGalleryMode ? file.generatedID : file.uploadedFileID;
  }

  static int? memoryFileIdFromMemory(
    Memory memory, {
    required bool isLocalGalleryMode,
  }) {
    return memoryFileId(memory.file, isLocalGalleryMode: isLocalGalleryMode);
  }

  static bool isTooCloseInTime(
    int? creationTime,
    Iterable<int> selectedCreationTimes, {
    Duration minGap = minimumMemoryTimeGap,
  }) {
    if (creationTime == null) return false;
    final minGapMicroseconds = minGap.inMicroseconds;
    for (final selectedTime in selectedCreationTimes) {
      if ((creationTime - selectedTime).abs() < minGapMicroseconds) {
        return true;
      }
    }
    return false;
  }

  static List<Memory> filterNearDuplicates(
    List<Memory> memories,
    Map<int, EmbeddingVector> fileIDToImageEmbedding, {
    int? minKeep,
    required bool isLocalGalleryMode,
    double similarityThreshold = clipSimilarImageThreshold,
  }) {
    if (memories.length < 2) return memories;
    final filtered = <Memory>[];
    final selectedFileIDs = <int>[];
    int skipped = 0;
    final total = memories.length;
    for (final mem in memories) {
      final fileID = memoryFileIdFromMemory(
        mem,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      final bool shouldSkip =
          fileID != null &&
          isNearDuplicate(
            fileID,
            selectedFileIDs,
            fileIDToImageEmbedding,
            similarityThreshold: similarityThreshold,
          ) &&
          (minKeep == null || (total - skipped) > minKeep);
      if (shouldSkip) {
        skipped++;
        continue;
      }
      filtered.add(mem);
      if (fileID != null) {
        selectedFileIDs.add(fileID);
      }
    }
    return filtered;
  }

  static List<Memory> excludeNearDuplicates(
    List<Memory> candidates,
    List<Memory> selected,
    Map<int, EmbeddingVector> fileIDToImageEmbedding, {
    required bool isLocalGalleryMode,
    double similarityThreshold = clipSimilarImageThreshold,
  }) {
    if (selected.isEmpty || candidates.isEmpty) return candidates;
    final selectedFileIDs = selected
        .map(
          (mem) => memoryFileIdFromMemory(
            mem,
            isLocalGalleryMode: isLocalGalleryMode,
          ),
        )
        .whereType<int>()
        .toList(growable: false);
    if (selectedFileIDs.isEmpty) return candidates;
    final filtered = <Memory>[];
    for (final candidate in candidates) {
      final fileID = memoryFileIdFromMemory(
        candidate,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      if (fileID == null ||
          !isNearDuplicate(
            fileID,
            selectedFileIDs,
            fileIDToImageEmbedding,
            similarityThreshold: similarityThreshold,
          )) {
        filtered.add(candidate);
      }
    }
    return filtered;
  }

  static List<Memory> filterByTimeSpacing(
    List<Memory> memories, {
    Duration minGap = minimumMemoryTimeGap,
  }) {
    if (memories.length < 2) return memories;
    final filtered = <Memory>[];
    final selectedCreationTimes = <int>[];
    for (final mem in memories) {
      final creationTime = mem.file.creationTime;
      if (isTooCloseInTime(
        creationTime,
        selectedCreationTimes,
        minGap: minGap,
      )) {
        continue;
      }
      filtered.add(mem);
      if (creationTime != null) {
        selectedCreationTimes.add(creationTime);
      }
    }
    return filtered;
  }

  static List<Memory> excludeTooCloseInTime(
    List<Memory> candidates,
    List<Memory> selected, {
    Duration minGap = minimumMemoryTimeGap,
  }) {
    if (selected.isEmpty || candidates.isEmpty) return candidates;
    final selectedTimes = selected
        .map((mem) => mem.file.creationTime)
        .whereType<int>()
        .toList(growable: false);
    if (selectedTimes.isEmpty) return candidates;
    final filtered = <Memory>[];
    for (final candidate in candidates) {
      if (!isTooCloseInTime(
        candidate.file.creationTime,
        selectedTimes,
        minGap: minGap,
      )) {
        filtered.add(candidate);
      }
    }
    return filtered;
  }
}
