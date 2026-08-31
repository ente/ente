import "dart:async";
import "dart:developer" as dev show log;
import "dart:math" show Random, max, min;

import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart" show kDebugMode, visibleForTesting;
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:ml_linalg/vector.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/memories_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/locale.dart";
import "package:photos/models/base_location.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/filler_memory.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/on_this_day_memory.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/smart_memory_constants.dart";
import "package:photos/models/memories/time_memory.dart";
import "package:photos/models/memories/trip_memory.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/language_service.dart";
import "package:photos/services/location_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/memories/memories_computation_context.dart";
import "package:photos/services/memories/photo_selector.dart";
import "package:photos/services/search_service.dart";

part "smart_memories_clip_calculator.dart";
part "memories/memory_file_index.dart";
part "smart_memories_people_calculator.dart";
part "smart_memories_time_calculator.dart";
part "smart_memories_trip_calculator_v2.dart";

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

typedef _PreparedMemoriesData = ({
  List<PersonEntity> persons,
  Map<String, String> faceIDsToPersonID,
  Map<int, EmbeddingVector> fileIDToImageEmbedding,
  MemoryFileIndex fileIndex,
  TripMemoriesAnalysis tripAnalysis,
});

class SmartMemoriesService {
  final _logger = Logger("SmartMemoriesService");
  MemoriesDB get _memoriesDB => isLocalGalleryMode
      ? MemoriesDB.localGalleryInstance
      : MemoriesDB.instance;

  static const _clipSimilarImageThreshold =
      PhotoSelector.clipSimilarImageThreshold;
  static const _clipActivityQueryThreshold = 0.20;
  static const _clipMemoryTypeQueryThreshold = 0.225;
  static const _minimumMemoryTimeGap = PhotoSelector.minimumMemoryTimeGap;

  static const yearsBefore = 30;

  static const minimumMemoryLength = 5;
  static const _maximumUnnamedPeopleClusters = 10;
  static const _maximumUnnamedPeopleGroupSize = 6;
  static const _minimumUnnamedPeopleWithMePhotos = minimumMemoryLength;
  static const _minimumUnnamedPeopleNonGroupPhotos = minimumMemoryLength;
  static const _minimumUnnamedPeopleNonConsecutiveDays = 4;
  static const _minimumNamedPeopleBeforeDisablingUnnamedFallback = 5;
  static const _unnamedClusterPersonIDPrefix = "cluster:";
  static const _debugForceUnnamedClustersOnly = false;

  SmartMemoriesService();

  Future<
    ({
      Set<String> assignedClusterIDs,
      Map<String, int> clusterIdToFaceCount,
      Map<String, Iterable<String>> clusterIdToFaceIDs,
    })
  >
  _loadUnnamedClusterData({
    required MLDataDB mlDataDB,
    required List<PersonEntity> allPersons,
    required bool shouldLoadUnnamedClusterData,
    required TimeLogger t,
  }) async {
    if (!shouldLoadUnnamedClusterData) {
      _logger.info('Skipping unnamed cluster data load (fallback disabled) $t');
      return (
        assignedClusterIDs: <String>{},
        clusterIdToFaceCount: <String, int>{},
        clusterIdToFaceIDs: <String, Iterable<String>>{},
      );
    }

    final allPersonIDs = allPersons
        .map((person) => person.remoteID)
        .toList(growable: false);
    final assignedClusterIDs = allPersonIDs.isEmpty
        ? <String>{}
        : await mlDataDB.getPersonsClusterIDs(allPersonIDs);
    _logger.info('assignedClusterIDs has ${assignedClusterIDs.length} $t');
    final clusterIdToFaceCount = await mlDataDB.clusterIdToFaceCount();
    _logger.info(
      'clusterIdToFaceCount has ${clusterIdToFaceCount.length} entries $t',
    );
    final clusterIdToFaceIDs = await mlDataDB.getAllClusterIdToFaceIDs();
    _logger.info(
      'clusterIdToFaceIDs has ${clusterIdToFaceIDs.length} entries $t',
    );
    return (
      assignedClusterIDs: assignedClusterIDs,
      clusterIdToFaceCount: clusterIdToFaceCount,
      clusterIdToFaceIDs: clusterIdToFaceIDs,
    );
  }

  Future<MemoriesResult> calcSmartMemories(
    DateTime now,
    MemoriesCache oldCache, {
    bool debugSurfaceAll = false,
    required bool mlEnabled,
  }) async {
    try {
      final TimeLogger t = TimeLogger(context: "calcMemories");
      _logger.info(
        'calcMemories called with time: $now at ${DateTime.now()} '
        '(mlEnabled: $mlEnabled) $t',
      );
      final computationContext = await _loadComputationContext(
        now,
        oldCache,
        debugSurfaceAll: debugSurfaceAll,
        mlEnabled: mlEnabled,
        timeLogger: t,
      );

      final local = await getLocale();
      final languageCode = local?.languageCode ?? "en";
      final s = await LanguageService.locals;

      _logger.info('get locale and S $t');
      final memoriesResult =
          await Computer.shared().compute(
                _allMemoriesCalculations,
                param: computationContext.toIsolateArgs(),
              )
              as MemoriesResult;
      _logger.info(
        '${memoriesResult.memories.length} memories computed in computer $t',
      );
      return _finalizeMemoriesResult(memoriesResult, s, languageCode, t);
    } catch (e, s) {
      _logger.severe("Error calculating smart memories", e, s);
      return _fallbackAfterCalculationError();
    }
  }

  Future<({MemoriesResult current, MemoriesResult next})>
  calcCurrentAndNextSmartMemories(
    DateTime current,
    DateTime next,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  }) async {
    try {
      final TimeLogger t = TimeLogger(context: "calcCurrentAndNextMemories");
      _logger.info(
        'calcCurrentAndNextMemories called with times: $current and $next at '
        '${DateTime.now()} (mlEnabled: $mlEnabled) $t',
      );
      final computationContext = await _loadComputationContext(
        current,
        oldCache,
        debugSurfaceAll: false,
        mlEnabled: mlEnabled,
        timeLogger: t,
      );

      final local = await getLocale();
      final languageCode = local?.languageCode ?? "en";
      final s = await LanguageService.locals;
      _logger.info('get locale and S $t');

      final args = computationContext.toIsolateArgs()..["next"] = next;
      final results =
          (await Computer.shared().compute(
                    _allMemoriesCalculationsForPeriods,
                    param: args,
                  )
                  as List)
              .cast<MemoriesResult>();
      final currentResult = await _finalizeMemoriesResult(
        results[0],
        s,
        languageCode,
        t,
      );
      final nextResult = await _finalizeMemoriesResult(
        results[1],
        s,
        languageCode,
        t,
      );
      _logger.info(
        '${currentResult.memories.length} current and '
        '${nextResult.memories.length} next memories computed in computer $t',
      );
      return (current: currentResult, next: nextResult);
    } catch (e, s) {
      _logger.severe("Error calculating current and next smart memories", e, s);
      final currentResult = await _fallbackAfterCalculationError();
      if (currentResult.failed) {
        return (current: currentResult, next: MemoriesResult.failed());
      }
      return (
        current: currentResult,
        next: await _fallbackAfterCalculationError(),
      );
    }
  }

  Future<MemoriesResult> _finalizeMemoriesResult(
    MemoriesResult memoriesResult,
    StringsLocalizations s,
    String languageCode,
    TimeLogger t,
  ) async {
    try {
      if (isLocalGalleryMode && memoriesResult.isEmpty) {
        _logger.severe(
          "Smart memories returned empty in local gallery mode, falling back to simple memories",
        );
        final fallbackMemories = await calcSimpleMemories();
        return MemoriesResult(fallbackMemories, <BaseLocation>[]);
      }
      if (memoriesResult.failed) {
        return memoriesResult;
      }
      for (final memory in memoriesResult.memories) {
        memory.title = memory.createTitle(s, languageCode);
      }
      _logger.info('titles created for all memories $t');
      return memoriesResult;
    } catch (e, s) {
      _logger.severe("Error finalizing smart memories", e, s);
      return _fallbackAfterCalculationError();
    }
  }

  Future<MemoriesResult> _fallbackAfterCalculationError() async {
    if (isLocalGalleryMode) {
      try {
        _logger.warning(
          "Falling back to simple memories after smart memories failure in local gallery mode",
        );
        final fallbackMemories = await calcSimpleMemories();
        return MemoriesResult(fallbackMemories, <BaseLocation>[]);
      } catch (fallbackError, fallbackStackTrace) {
        _logger.severe(
          "Offline fallback to simple memories failed",
          fallbackError,
          fallbackStackTrace,
        );
      }
    }
    return MemoriesResult.failed();
  }

  Future<MemoriesComputationContext> _loadComputationContext(
    DateTime now,
    MemoriesCache oldCache, {
    required bool debugSurfaceAll,
    required bool mlEnabled,
    required TimeLogger timeLogger,
  }) async {
    final allFileIdsToFile = await _getFilesAndMapForMemories(
      useLocalIntIds: isLocalGalleryMode,
      requireLocalId: isLocalGalleryMode,
    );
    _logger.info("All files length: ${allFileIdsToFile.length} $timeLogger");

    final collectionIDsToExclude = await getCollectionIDsToExclude();
    _logger.info(
      'collectionIDsToExclude length: ${collectionIDsToExclude.length} '
      '$timeLogger',
    );

    final seenTimes = await _memoriesDB.getSeenTimes();
    _logger.info('seenTimes has ${seenTimes.length} entries $timeLogger');

    final mlDataDB = isLocalGalleryMode
        ? MLDataDB.localGalleryInstance
        : MLDataDB.instance;
    final allPersons = (!mlEnabled || isLocalGalleryMode)
        ? const <PersonEntity>[]
        : await PersonService.instance.getPersons();
    final persons = allPersons
        .where((person) => !person.data.hideFromMemories)
        .toList();
    _logger.info(
      'gotten all ${persons.length} persons after filtering $timeLogger',
    );
    final bool unnamedPeopleFallbackEnabled =
        mlEnabled && localSettings.showLocalGalleryModeOption;
    final amountOfNonIgnoredPersons = persons
        .where((person) => !person.data.isIgnored)
        .length;
    final canUseUnnamedFallback =
        unnamedPeopleFallbackEnabled &&
        (isLocalGalleryMode ||
            amountOfNonIgnoredPersons <
                _minimumNamedPeopleBeforeDisablingUnnamedFallback);
    final shouldLoadUnnamedClusterData =
        unnamedPeopleFallbackEnabled &&
        (canUseUnnamedFallback ||
            debugSurfaceAll ||
            _debugForceUnnamedClustersOnly);
    final unnamedClusterData = await _loadUnnamedClusterData(
      mlDataDB: mlDataDB,
      allPersons: allPersons,
      shouldLoadUnnamedClusterData: shouldLoadUnnamedClusterData,
      t: timeLogger,
    );

    final currentUserEmail = isLocalGalleryMode
        ? null
        : Configuration.instance.getEmail();
    _logger.info('currentUserEmail: $currentUserEmail $timeLogger');

    final citySearchIndex = await locationService.getCitySearchIndex(
      allFileIdsToFile.values,
    );
    _logger.info(
      'matched ${citySearchIndex.assignments.length} files to cities $timeLogger',
    );

    final Map<int, List<FaceWithoutEmbedding>> fileIdToFaces = mlEnabled
        ? await mlDataDB.getFileIDsToFacesWithoutEmbedding()
        : <int, List<FaceWithoutEmbedding>>{};
    _logger.info(
      'fileIdToFaces has ${fileIdToFaces.length} entries $timeLogger',
    );

    final allImageEmbeddings = mlEnabled
        ? await mlDataDB.getAllClipVectors()
        : const <EmbeddingVector>[];
    _logger.info(
      'allImageEmbeddings has ${allImageEmbeddings.length} entries '
      '$timeLogger',
    );

    final Vector clipPositiveTextVector;
    final Map<PeopleActivity, Vector> clipPeopleActivityVectors;
    final Map<ClipMemoryType, Vector> clipMemoryTypeVectors;
    if (mlEnabled) {
      _logger.info('Loading text embeddings via cache service');
      clipPositiveTextVector = Vector.fromList(
        await textEmbeddingsCacheService.getEmbedding(
          "Photo of a precious and nostalgic memory radiating warmth, vibrant energy, or quiet beauty — alive with color, light, or emotion",
        ),
      );

      clipPeopleActivityVectors = <PeopleActivity, Vector>{};
      for (final activity in PeopleActivity.values) {
        final query = activityQuery(activity);
        clipPeopleActivityVectors[activity] = Vector.fromList(
          await textEmbeddingsCacheService.getEmbedding(query),
        );
      }

      clipMemoryTypeVectors = <ClipMemoryType, Vector>{};
      for (final memoryType in ClipMemoryType.values) {
        final query = clipQuery(memoryType);
        clipMemoryTypeVectors[memoryType] = Vector.fromList(
          await textEmbeddingsCacheService.getEmbedding(query),
        );
      }
      _logger.info('Text embeddings loaded via cache service');
    } else {
      _logger.info('ML disabled, skipping text embedding loads');
      clipPositiveTextVector = Vector.fromList(const [0.0]);
      clipPeopleActivityVectors = const <PeopleActivity, Vector>{};
      clipMemoryTypeVectors = const <ClipMemoryType, Vector>{};
    }

    _logger.info(
      'all data fetched $timeLogger at ${DateTime.now()}, to computer',
    );
    return MemoriesComputationContext(
      allFileIdsToFile: allFileIdsToFile,
      collectionIDsToExclude: collectionIDsToExclude,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      now: now,
      oldCache: oldCache,
      debugSurfaceAll: debugSurfaceAll,
      canUseUnnamedFallback: canUseUnnamedFallback,
      seenTimes: seenTimes,
      persons: persons,
      currentUserEmail: currentUserEmail,
      citySearchIndex: citySearchIndex,
      fileIdToFaces: fileIdToFaces,
      clusterIdToFaceCount: unnamedClusterData.clusterIdToFaceCount,
      clusterIdToFaceIDs: unnamedClusterData.clusterIdToFaceIDs,
      assignedClusterIDs: unnamedClusterData.assignedClusterIDs,
      allImageEmbeddings: allImageEmbeddings,
      clipPositiveTextVector: clipPositiveTextVector,
      clipPeopleActivityVectors: clipPeopleActivityVectors,
      clipMemoryTypeVectors: clipMemoryTypeVectors,
    );
  }

  static List<EmbeddingVector> _getEmbeddingsForFileIDs(
    Map<int, EmbeddingVector> fileIDToImageEmbedding,
    Set<int> fileIDs,
  ) => PhotoSelector.getEmbeddingsForFileIDs(fileIDToImageEmbedding, fileIDs);

  static bool _isNearDuplicate(
    int fileID,
    Iterable<int> selectedFileIDs,
    Map<int, EmbeddingVector> fileIDToImageEmbedding, {
    double similarityThreshold = _clipSimilarImageThreshold,
  }) => PhotoSelector.isNearDuplicate(
    fileID,
    selectedFileIDs,
    fileIDToImageEmbedding,
    similarityThreshold: similarityThreshold,
  );

  static int? _memoryFileId(
    EnteFile file, {
    required bool isLocalGalleryMode,
  }) =>
      PhotoSelector.memoryFileId(file, isLocalGalleryMode: isLocalGalleryMode);

  static int? _memoryFileIdFromMemory(
    Memory memory, {
    required bool isLocalGalleryMode,
  }) => PhotoSelector.memoryFileIdFromMemory(
    memory,
    isLocalGalleryMode: isLocalGalleryMode,
  );

  static bool _isTooCloseInTime(
    int? creationTime,
    Iterable<int> selectedCreationTimes, {
    Duration minGap = _minimumMemoryTimeGap,
  }) => PhotoSelector.isTooCloseInTime(
    creationTime,
    selectedCreationTimes,
    minGap: minGap,
  );

  static List<Memory> _filterNearDuplicates(
    List<Memory> memories,
    Map<int, EmbeddingVector> fileIDToImageEmbedding, {
    int? minKeep,
    required bool isLocalGalleryMode,
    double similarityThreshold = _clipSimilarImageThreshold,
  }) => PhotoSelector.filterNearDuplicates(
    memories,
    fileIDToImageEmbedding,
    minKeep: minKeep,
    isLocalGalleryMode: isLocalGalleryMode,
    similarityThreshold: similarityThreshold,
  );

  static List<Memory> _filterByTimeSpacing(
    List<Memory> memories, {
    Duration minGap = _minimumMemoryTimeGap,
  }) => PhotoSelector.filterByTimeSpacing(memories, minGap: minGap);

  static List<PeopleMemoryCandidate> _buildUnnamedClusterCandidates({
    required Map<String, int> clusterIdToFaceCount,
    required Map<String, Iterable<String>> clusterIdToFaceIDs,
    required Set<String> assignedClusterIDs,
    required Map<int, EnteFile> allFileIdsToFile,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Set<int>? meFileIDs,
    required bool isMeAssigned,
    required Map<int, int> seenTimes,
    required int nowInMicroseconds,
    required int windowEnd,
    required bool isLocalGalleryMode,
    required PeopleSelectionBuilder selectionBuilder,
  }) {
    if (clusterIdToFaceCount.isEmpty || clusterIdToFaceIDs.isEmpty) {
      return <PeopleMemoryCandidate>[];
    }
    if (isMeAssigned && (meFileIDs == null || meFileIDs.isEmpty)) {
      return <PeopleMemoryCandidate>[];
    }
    final sortedUnassignedClusters =
        clusterIdToFaceCount.entries
            .where((entry) => !assignedClusterIDs.contains(entry.key))
            .toList(growable: false)
          ..sort((a, b) => b.value.compareTo(a.value));
    // Wrap the selection builder to move the photo with the fewest faces to
    // the front, so the cover thumbnail clearly shows who the memory is about.
    Future<List<Memory>> coverOptimizedBuilder(List<Memory> memories) async {
      final selected = await selectionBuilder(memories);
      if (selected.length <= 1) return selected;
      int bestIdx = 0;
      int bestFaceCount =
          fileIdToFaces[_memoryFileIdFromMemory(
                selected[0],
                isLocalGalleryMode: isLocalGalleryMode,
              )]
              ?.length ??
          999;
      for (int i = 1; i < selected.length; i++) {
        final faceCount =
            fileIdToFaces[_memoryFileIdFromMemory(
                  selected[i],
                  isLocalGalleryMode: isLocalGalleryMode,
                )]
                ?.length ??
            999;
        if (faceCount < bestFaceCount) {
          bestFaceCount = faceCount;
          bestIdx = i;
        }
      }
      if (bestIdx == 0) return selected;
      return [
        selected[bestIdx],
        ...selected.sublist(0, bestIdx),
        ...selected.sublist(bestIdx + 1),
      ];
    }

    final unnamedCandidates = <PeopleMemoryCandidate>[];
    for (final entry in sortedUnassignedClusters) {
      if (unnamedCandidates.length >= _maximumUnnamedPeopleClusters) break;
      final clusterID = entry.key;
      final faceIDs = clusterIdToFaceIDs[clusterID];
      if (faceIDs == null || faceIDs.isEmpty) continue;

      final clusterFileIDs = <int>{};
      for (final faceID in faceIDs) {
        clusterFileIDs.add(getFileIdFromFaceId(faceID));
      }
      if (clusterFileIDs.isEmpty) continue;

      final nonGroupFiles = <EnteFile>[];
      final nonGroupCreationTimes = <int>[];
      int overlapWithMeInNonGroupFiles = 0;
      for (final fileID in clusterFileIDs) {
        final facesInPhoto = fileIdToFaces[fileID]?.length ?? 0;
        if (facesInPhoto == 0 ||
            facesInPhoto > _maximumUnnamedPeopleGroupSize) {
          continue;
        }
        final file = allFileIdsToFile[fileID];
        if (file == null || file.creationTime == null) continue;
        nonGroupFiles.add(file);
        nonGroupCreationTimes.add(file.creationTime!);
        if (isMeAssigned && meFileIDs!.contains(fileID)) {
          overlapWithMeInNonGroupFiles++;
        }
      }
      if (isMeAssigned &&
          overlapWithMeInNonGroupFiles < _minimumUnnamedPeopleWithMePhotos) {
        continue;
      }
      if (nonGroupFiles.length < _minimumUnnamedPeopleNonGroupPhotos) {
        continue;
      }
      final nonConsecutiveDays = _countNonConsecutiveDays(
        nonGroupCreationTimes,
      );
      if (nonConsecutiveDays < _minimumUnnamedPeopleNonConsecutiveDays) {
        continue;
      }

      unnamedCandidates.add(
        PeopleMemoryCandidate(
          personID: "$_unnamedClusterPersonIDPrefix$clusterID",
          personName: null,
          type: PeopleMemoryType.spotlight,
          rawMemories: nonGroupFiles
              .map((file) => Memory.fromFile(file, seenTimes))
              .toList(growable: false),
          firstDateToShow: nowInMicroseconds,
          lastDateToShow: windowEnd,
          selectionBuilder: coverOptimizedBuilder,
          isUnnamedCluster: true,
        ),
      );
    }
    return unnamedCandidates;
  }

  static int _countNonConsecutiveDays(Iterable<int> creationTimes) {
    if (creationTimes.isEmpty) return 0;
    final uniqueDays =
        creationTimes
            .map((timestamp) => timestamp - (timestamp % microSecondsInDay))
            .toSet()
            .toList(growable: false)
          ..sort();
    if (uniqueDays.isEmpty) return 0;
    int count = 1;
    int previousDay = uniqueDays.first;
    for (final day in uniqueDays.skip(1)) {
      if (day - previousDay > microSecondsInDay) {
        count++;
      }
      previousDay = day;
    }
    return count;
  }

  static Map<String, int> _latestShownTimeByPersonID(
    Iterable<PeopleShownLog> shownPeople,
  ) {
    final latestShownTimeByPersonID = <String, int>{};
    for (final shownLog in shownPeople) {
      final oldValue = latestShownTimeByPersonID[shownLog.personID];
      if (oldValue == null || shownLog.lastTimeShown > oldValue) {
        latestShownTimeByPersonID[shownLog.personID] = shownLog.lastTimeShown;
      }
    }
    return latestShownTimeByPersonID;
  }

  static List<PeopleMemoryCandidate> _orderUnnamedCandidatesByRecencyAndRandom({
    required Iterable<PeopleMemoryCandidate> candidates,
    required Iterable<PeopleShownLog> shownPeople,
    required DateTime currentTime,
    required Duration shownPersonTimeout,
  }) {
    final remaining = candidates.toList(growable: true);
    if (remaining.length <= 1) return remaining;
    final random = Random();
    final latestShownTimeByPersonID = _latestShownTimeByPersonID(shownPeople);
    final nowInMicroseconds = currentTime.microsecondsSinceEpoch;
    final unseenWeight = max(1, shownPersonTimeout.inDays * 2);
    final orderedCandidates = <PeopleMemoryCandidate>[];
    while (remaining.isNotEmpty) {
      final weights = <int>[];
      int totalWeight = 0;
      for (final candidate in remaining) {
        final latestShownTime = latestShownTimeByPersonID[candidate.personID];
        final weight = latestShownTime == null
            ? unseenWeight
            : max(
                1,
                (nowInMicroseconds - latestShownTime) ~/ microSecondsInDay,
              );
        weights.add(weight);
        totalWeight += weight;
      }
      var chosenWeight = random.nextInt(totalWeight);
      int chosenIndex = 0;
      for (; chosenIndex < weights.length; chosenIndex++) {
        chosenWeight -= weights[chosenIndex];
        if (chosenWeight < 0) break;
      }
      orderedCandidates.add(remaining.removeAt(chosenIndex));
    }
    return orderedCandidates;
  }

  static bool _wasPersonShownRecently({
    required String personID,
    required Iterable<PeopleShownLog> shownPeople,
    required DateTime currentTime,
    required Duration shownPersonTimeout,
  }) {
    for (final shownLog in shownPeople) {
      if (shownLog.personID != personID) continue;
      final shownDate = DateTime.fromMicrosecondsSinceEpoch(
        shownLog.lastTimeShown,
      );
      if (currentTime.difference(shownDate) < shownPersonTimeout) {
        return true;
      }
    }
    return false;
  }

  Future<Map<int, EnteFile>> _getFilesAndMapForMemories({
    bool useGeneratedIds = false,
    bool requireLocalId = false,
    bool useLocalIntIds = false,
  }) async {
    final allFilesFromSearchService = await SearchService.instance
        .getAllFilesForSearch();
    final archivedOrHiddenCollectionIDs = CollectionsService.instance
        .archivedOrHiddenCollectionIds();
    final excludedUploadFileIDs = <int>{};
    if (archivedOrHiddenCollectionIDs.isNotEmpty) {
      final filesInArchivedCollections = await FilesDB.instance
          .getAllFilesFromCollections(archivedOrHiddenCollectionIDs);
      for (final archivedFile in filesInArchivedCollections) {
        final archivedUploadID = archivedFile.uploadedFileID;
        if (archivedUploadID != null && archivedUploadID != -1) {
          excludedUploadFileIDs.add(archivedUploadID);
        }
      }
    }
    final candidateFiles = <EnteFile>[];
    for (final file in allFilesFromSearchService) {
      final localId = file.localID;
      final hasLocalId = localId != null && localId.isNotEmpty;
      if (requireLocalId && !hasLocalId) {
        continue;
      }
      final hasId = useLocalIntIds
          ? hasLocalId
          : useGeneratedIds
          ? file.generatedID != null &&
                (file.uploadedFileID != null || hasLocalId)
          : file.uploadedFileID != null;
      if (hasId && file.creationTime != null) {
        if (excludedUploadFileIDs.contains(file.uploadedFileID)) {
          continue;
        }
        if (file.magicMetadata.visibility == archiveVisibility ||
            file.magicMetadata.visibility == hiddenVisibility) {
          continue;
        }
        final collectionID = file.collectionID;
        if (collectionID != null &&
            archivedOrHiddenCollectionIDs.contains(collectionID)) {
          continue;
        }
        candidateFiles.add(file);
      }
    }
    final Map<String, int> localIdToIntId = useLocalIntIds
        ? await OfflineFilesDB.instance.ensureLocalIntIds(
            candidateFiles
                .map((file) => file.localID)
                .whereType<String>()
                .where((id) => id.isNotEmpty),
          )
        : <String, int>{};
    final allFileIdsToFile = <int, EnteFile>{};
    for (final file in candidateFiles) {
      final localIntId = useLocalIntIds ? localIdToIntId[file.localID] : null;
      final mappedFile = localIntId != null
          ? file.copyWith(generatedID: localIntId)
          : file;
      final key = useLocalIntIds
          ? localIntId
          : useGeneratedIds
          ? mappedFile.generatedID
          : mappedFile.uploadedFileID;
      if (key != null) {
        allFileIdsToFile[key] = mappedFile;
      }
    }
    return allFileIdsToFile;
  }

  static Future<MemoriesResult> _allMemoriesCalculations(
    Map<String, dynamic> args,
  ) async {
    try {
      final computationContext = MemoriesComputationContext.fromIsolateArgs(
        args,
      );
      return _calculateMemories(
        computationContext,
        _prepareMemoriesData(computationContext),
      );
    } catch (e, s) {
      dev.log("Error in _allMemoriesCalculations \n Error:$e \n Stacktrace:$s");
      return MemoriesResult.failed();
    }
  }

  static Future<List<MemoriesResult>> _allMemoriesCalculationsForPeriods(
    Map<String, dynamic> args,
  ) async {
    try {
      final computationContext = MemoriesComputationContext.fromIsolateArgs(
        args,
      );
      final preparedData = _prepareMemoriesData(computationContext);
      final currentResult = await _calculateMemories(
        computationContext,
        preparedData,
      );
      if (currentResult.failed && !computationContext.isLocalGalleryMode) {
        return <MemoriesResult>[currentResult, MemoriesResult.failed()];
      }
      final nextCache = _cacheWithCurrentTrips(
        computationContext.oldCache,
        currentResult,
        computationContext.now,
      );
      final nextResult = await _calculateMemories(
        computationContext,
        preparedData,
        period: args["next"] as DateTime,
        periodCache: nextCache,
      );
      return <MemoriesResult>[currentResult, nextResult];
    } catch (e, s) {
      dev.log(
        "Error in _allMemoriesCalculationsForPeriods "
        "\n Error:$e \n Stacktrace:$s",
      );
      return <MemoriesResult>[MemoriesResult.failed(), MemoriesResult.failed()];
    }
  }

  static _PreparedMemoriesData _prepareMemoriesData(
    MemoriesComputationContext computationContext,
  ) {
    final persons = computationContext.persons
        .where((person) => !person.data.hideFromMemories)
        .toList();
    final faceIDsToPersonID = <String, String>{};
    for (final person in persons) {
      for (final cluster in person.data.assigned) {
        for (final faceID in cluster.faces) {
          faceIDsToPersonID[faceID] = person.remoteID;
        }
      }
    }
    final fileIDToImageEmbedding = <int, EmbeddingVector>{};
    for (final embedding in computationContext.allImageEmbeddings) {
      fileIDToImageEmbedding[embedding.fileID] = embedding;
    }
    final fileIndex = MemoryFileIndex(
      computationContext.allFileIdsToFile.values,
    );
    final tripAnalysis = TripMemoriesCalculatorV2.analyze(
      fileIndex.files,
      computationContext.allFileIdsToFile,
      isLocalGalleryMode: computationContext.isLocalGalleryMode,
      seenTimes: computationContext.seenTimes,
      citySearchIndex: computationContext.citySearchIndex,
    );
    return (
      persons: persons,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      fileIndex: fileIndex,
      tripAnalysis: tripAnalysis,
    );
  }

  static MemoriesCache _cacheWithCurrentTrips(
    MemoriesCache oldCache,
    MemoriesResult currentResult,
    DateTime current,
  ) {
    return MemoriesCache(
      toShowMemories: <ToShowMemory>[
        ...oldCache.toShowMemories,
        ...currentResult.memories.whereType<TripMemory>().map(
          (memory) => ToShowMemory.fromSmartMemory(memory, current),
        ),
      ],
      peopleShownLogs: oldCache.peopleShownLogs,
      clipShownLogs: oldCache.clipShownLogs,
      tripsShownLogs: oldCache.tripsShownLogs,
      baseLocations: oldCache.baseLocations,
    );
  }

  static Future<MemoriesResult> _calculateMemories(
    MemoriesComputationContext computationContext,
    _PreparedMemoriesData preparedData, {
    DateTime? period,
    MemoriesCache? periodCache,
  }) async {
    try {
      final TimeLogger t = TimeLogger(context: "_allMemoriesCalculations");
      final Map<int, EnteFile> allFileIdsToFile =
          computationContext.allFileIdsToFile;
      final Set<int> collectionIDsToExclude =
          computationContext.collectionIDsToExclude;
      final bool isLocalGalleryMode = computationContext.isLocalGalleryMode;
      final bool mlEnabled = computationContext.mlEnabled;
      final DateTime now = period ?? computationContext.now;
      final MemoriesCache oldCache = periodCache ?? computationContext.oldCache;
      final bool debugSurfaceAll = computationContext.debugSurfaceAll;
      final bool canUseUnnamedFallback =
          computationContext.canUseUnnamedFallback;
      final Map<int, int> seenTimes = computationContext.seenTimes;
      final List<PersonEntity> persons = preparedData.persons;
      final String? currentUserEmail = computationContext.currentUserEmail;
      final CitySearchIndex citySearchIndex =
          computationContext.citySearchIndex;
      final Map<int, List<FaceWithoutEmbedding>> fileIdToFaces =
          computationContext.fileIdToFaces;
      final Map<String, int> clusterIdToFaceCount =
          computationContext.clusterIdToFaceCount;
      final Map<String, Iterable<String>> clusterIdToFaceIDs =
          computationContext.clusterIdToFaceIDs;
      final Set<String> assignedClusterIDs =
          computationContext.assignedClusterIDs;
      final Vector clipPositiveTextVector =
          computationContext.clipPositiveTextVector;
      final Map<PeopleActivity, Vector> clipPeopleActivityVectors =
          computationContext.clipPeopleActivityVectors;
      final Map<ClipMemoryType, Vector> clipMemoryTypeVectors =
          computationContext.clipMemoryTypeVectors;
      dev.log('All arguments (direct data) unwrapped $t');
      final faceIDsToPersonID = preparedData.faceIDsToPersonID;
      final fileIDToImageEmbedding = preparedData.fileIDToImageEmbedding;
      dev.log('arguments from indirect data calculated $t');
      dev.log('starting actual memory calculations ${DateTime.now()}');
      dev.log("All files length at start: ${allFileIdsToFile.length} $t");
      // Some memory types need every file, so track used files by ID instead of
      // removing them from the source map.
      final fullSourceFiles = allFileIdsToFile.values;
      final fileIndex = preparedData.fileIndex;
      final usedMemoryFileIds = <int>{};

      final List<SmartMemory> memories = [];

      final onThisDayMemories = await _getOnThisDayResults(
        TimeMemoriesCalculator._filesForHistoricalWindow(fileIndex, now),
        now,
        seenTimes: seenTimes,
        collectionIDsToExclude: collectionIDsToExclude,
      );
      _markUsedMemories(
        usedMemoryFileIds,
        onThisDayMemories,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      memories.addAll(onThisDayMemories);
      dev.log(
        "All files length after on this day: "
        "${_remainingFilesCount(allFileIdsToFile, usedMemoryFileIds)} $t",
      );

      if (mlEnabled) {
        final peopleMemories = await _getPeopleResults(
          allFileIdsToFile,
          now,
          oldCache.peopleShownLogs,
          surfaceAll: debugSurfaceAll,
          seenTimes: seenTimes,
          persons: persons,
          isLocalGalleryMode: isLocalGalleryMode,
          canUseUnnamedFallback: canUseUnnamedFallback,
          currentUserEmail: currentUserEmail,
          fileIdToFaces: fileIdToFaces,
          clusterIdToFaceCount: clusterIdToFaceCount,
          clusterIdToFaceIDs: clusterIdToFaceIDs,
          assignedClusterIDs: assignedClusterIDs,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          clipPositiveTextVector: clipPositiveTextVector,
          clipPeopleActivityVectors: clipPeopleActivityVectors,
        );
        _markUsedMemories(
          usedMemoryFileIds,
          peopleMemories,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        memories.addAll(peopleMemories);
        dev.log(
          "All files length after people: "
          "${_remainingFilesCount(allFileIdsToFile, usedMemoryFileIds)} $t",
        );
      } else {
        dev.log('ML disabled, skipping people memories $t');
      }

      final (tripMemories, bases) = await _surfaceTrips(
        tripAnalysis: preparedData.tripAnalysis,
        allFileIdsToFile: allFileIdsToFile,
        currentTime: now,
        shownTrips: oldCache.tripsShownLogs,
        surfaceAll: debugSurfaceAll,
        cachedTripMemories: oldCache.toShowMemories,
        isLocalGalleryMode: isLocalGalleryMode,
        mlEnabled: mlEnabled,
        seenTimes: seenTimes,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
        citySearchIndex: citySearchIndex,
      );
      _markUsedMemories(
        usedMemoryFileIds,
        tripMemories,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      memories.addAll(tripMemories);
      dev.log(
        "All files length after trips: "
        "${_remainingFilesCount(allFileIdsToFile, usedMemoryFileIds)} $t",
      );

      if (mlEnabled) {
        final clipMemories = await _getClipResults(
          fullSourceFiles,
          now,
          oldCache.clipShownLogs,
          surfaceAll: debugSurfaceAll,
          isLocalGalleryMode: isLocalGalleryMode,
          seenTimes: seenTimes,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          clipMemoryTypeVectors: clipMemoryTypeVectors,
        );
        _markUsedMemories(
          usedMemoryFileIds,
          clipMemories,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        memories.addAll(clipMemories);
        dev.log(
          "All files length after clip memories: "
          "${_remainingFilesCount(allFileIdsToFile, usedMemoryFileIds)} $t",
        );
      } else {
        dev.log('ML disabled, skipping clip memories $t');
      }

      final timeFiles = _collectAvailableCandidates(
        TimeMemoriesCalculator._filesForTimeMemories(fileIndex, now),
        usedMemoryFileIds,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      final timeMemories = await _onThisDayOrWeekResults(
        timeFiles,
        now,
        recentSourceFiles: TimeMemoriesCalculator._filesForRecentTimeMemories(
          fileIndex,
          now,
        ),
        totalAvailableFileCount: _remainingFilesCount(
          allFileIdsToFile,
          usedMemoryFileIds,
        ),
        isLocalGalleryMode: isLocalGalleryMode,
        mlEnabled: mlEnabled,
        seenTimes: seenTimes,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
      );
      _markUsedMemories(
        usedMemoryFileIds,
        timeMemories,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      memories.addAll(timeMemories);
      dev.log(
        "All files length after time: "
        "${_remainingFilesCount(allFileIdsToFile, usedMemoryFileIds)} $t",
      );

      final fillerFiles = _collectAvailableCandidates(
        TimeMemoriesCalculator._filesForHistoricalWindow(fileIndex, now),
        usedMemoryFileIds,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      final fillerMemories = await _getFillerResults(
        fillerFiles,
        now,
        seenTimes: seenTimes,
      );
      _markUsedMemories(
        usedMemoryFileIds,
        fillerMemories,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      memories.addAll(fillerMemories);
      dev.log(
        "All files length after filler: "
        "${_remainingFilesCount(allFileIdsToFile, usedMemoryFileIds)} $t",
      );
      dev.log('finished actual memory calculations ${DateTime.now()}');
      return MemoriesResult(memories, bases);
    } catch (e, s) {
      dev.log("Error in _allMemoriesCalculations \n Error:$e \n Stacktrace:$s");
      return MemoriesResult.failed();
    }
  }

  Future<List<SmartMemory>> calcSimpleMemories() async {
    final now = DateTime.now();
    final allFileIdsToFile = await _getFilesAndMapForMemories(
      useLocalIntIds: isLocalGalleryMode,
      requireLocalId: isLocalGalleryMode,
    );
    final fileIndex = MemoryFileIndex(allFileIdsToFile.values);
    final usedMemoryFileIds = <int>{};
    final seenTimes = await _memoriesDB.getSeenTimes();
    final collectionIDsToExclude = await getCollectionIDsToExclude();
    final localIdToIntId = isLocalGalleryMode
        ? await OfflineFilesDB.instance.ensureLocalIntIds(
            allFileIdsToFile.values
                .map((file) => file.localID)
                .whereType<String>()
                .where((id) => id.isNotEmpty),
          )
        : <String, int>{};

    final List<SmartMemory> memories = [];

    final onThisDayMemories = await _getOnThisDayResults(
      TimeMemoriesCalculator._filesForHistoricalWindow(fileIndex, now),
      now,
      seenTimes: seenTimes,
      collectionIDsToExclude: collectionIDsToExclude,
      localIdToIntId: localIdToIntId,
    );
    if (onThisDayMemories.isNotEmpty &&
        onThisDayMemories.first.shouldShowNow()) {
      memories.add(onThisDayMemories.first);
      _markUsedMemories(usedMemoryFileIds, [
        onThisDayMemories.first,
      ], isLocalGalleryMode: isLocalGalleryMode);
    }

    final fillerFiles = _collectAvailableCandidates(
      TimeMemoriesCalculator._filesForHistoricalWindow(fileIndex, now),
      usedMemoryFileIds,
      isLocalGalleryMode: isLocalGalleryMode,
    );
    final fillerMemories = await _getFillerResults(
      fillerFiles,
      now,
      seenTimes: seenTimes,
      localIdToIntId: localIdToIntId,
    );
    memories.addAll(fillerMemories);

    final local = await getLocale();
    final languageCode = local?.languageCode ?? "en";
    final s = await LanguageService.locals;

    _logger.info('get locale and S');
    for (final memory in memories) {
      memory.title = memory.createTitle(s, languageCode);
    }
    return memories;
  }

  static List<EnteFile> _collectAvailableCandidates(
    Iterable<EnteFile> candidates,
    Set<int> usedMemoryFileIds, {
    required bool isLocalGalleryMode,
  }) {
    final availableFiles = <EnteFile>[];
    for (final file in candidates) {
      final fileID = _memoryFileId(
        file,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      if (fileID != null && usedMemoryFileIds.contains(fileID)) {
        continue;
      }
      availableFiles.add(file);
    }
    return availableFiles;
  }

  static int _remainingFilesCount(
    Map<int, EnteFile> allFileIdsToFile,
    Set<int> usedMemoryFileIds,
  ) {
    return allFileIdsToFile.length - usedMemoryFileIds.length;
  }

  static void _markUsedMemories(
    Set<int> usedMemoryFileIds,
    Iterable<SmartMemory> memories, {
    required bool isLocalGalleryMode,
  }) {
    for (final memory in memories) {
      for (final fileMemory in memory.memories) {
        final fileId = _memoryFileIdFromMemory(
          fileMemory,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        if (fileId != null) {
          usedMemoryFileIds.add(fileId);
        }
      }
    }
  }

  static Future<List<PeopleMemory>> _getPeopleResults(
    Map<int, EnteFile> allFileIdsToFile,
    DateTime currentTime,
    List<PeopleShownLog> shownPeople, {
    bool surfaceAll = false,
    required Map<int, int> seenTimes,
    required List<PersonEntity> persons,
    required bool isLocalGalleryMode,
    required bool canUseUnnamedFallback,
    String? currentUserEmail,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, int> clusterIdToFaceCount,
    required Map<String, Iterable<String>> clusterIdToFaceIDs,
    required Set<String> assignedClusterIDs,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required Map<PeopleActivity, Vector> clipPeopleActivityVectors,
  }) async {
    return PeopleMemoriesCalculator.compute(
      allFileIdsToFile,
      currentTime,
      shownPeople,
      surfaceAll: surfaceAll,
      seenTimes: seenTimes,
      persons: persons,
      isLocalGalleryMode: isLocalGalleryMode,
      canUseUnnamedFallback: canUseUnnamedFallback,
      currentUserEmail: currentUserEmail,
      fileIdToFaces: fileIdToFaces,
      clusterIdToFaceCount: clusterIdToFaceCount,
      clusterIdToFaceIDs: clusterIdToFaceIDs,
      assignedClusterIDs: assignedClusterIDs,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
      clipPeopleActivityVectors: clipPeopleActivityVectors,
    );
  }

  static Future<List<ClipMemory>> _getClipResults(
    Iterable<EnteFile> allFiles,
    DateTime currentTime,
    List<ClipShownLog> shownClip, {
    bool surfaceAll = false,
    required bool isLocalGalleryMode,
    required Map<int, int> seenTimes,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Map<ClipMemoryType, Vector> clipMemoryTypeVectors,
  }) async {
    return ClipMemoriesCalculator.compute(
      allFiles,
      currentTime,
      shownClip,
      surfaceAll: surfaceAll,
      isLocalGalleryMode: isLocalGalleryMode,
      seenTimes: seenTimes,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipMemoryTypeVectors: clipMemoryTypeVectors,
    );
  }

  static Future<(List<TripMemory>, List<BaseLocation>)> _surfaceTrips({
    required TripMemoriesAnalysis tripAnalysis,
    required Map<int, EnteFile> allFileIdsToFile,
    required DateTime currentTime,
    required List<TripsShownLog> shownTrips,
    bool surfaceAll = false,
    required Iterable<ToShowMemory> cachedTripMemories,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required CitySearchIndex citySearchIndex,
  }) async {
    return TripMemoriesCalculatorV2.surface(
      tripAnalysis,
      allFileIdsToFile,
      currentTime,
      shownTrips,
      surfaceAll: surfaceAll,
      cachedTripMemories: cachedTripMemories,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      seenTimes: seenTimes,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
      citySearchIndex: citySearchIndex,
    );
  }

  static Future<List<TimeMemory>> _onThisDayOrWeekResults(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    required Iterable<EnteFile> recentSourceFiles,
    required int totalAvailableFileCount,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) async {
    return TimeMemoriesCalculator.computeTimeMemories(
      allFiles,
      currentTime,
      recentSourceFiles: recentSourceFiles,
      totalAvailableFileCount: totalAvailableFileCount,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      seenTimes: seenTimes,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
    );
  }

  static Future<List<FillerMemory>> _getFillerResults(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    required Map<int, int> seenTimes,
    Map<String, int>? localIdToIntId,
  }) async {
    return TimeMemoriesCalculator.computeFillerMemories(
      allFiles,
      currentTime,
      seenTimes: seenTimes,
      localIdToIntId: localIdToIntId,
    );
  }

  Future<Set<int>> getCollectionIDsToExclude() async {
    if (isLocalGalleryMode) {
      return <int>{};
    }
    final collections = CollectionsService.instance.getCollectionsForUI();

    const excludedNames = {
      'screenshot',
      'whatsapp',
      'telegram',
      'download',
      'facebook',
      'instagram',
      'messenger',
      'twitter',
      'reddit',
      'discord',
      'signal',
      'viber',
      'wechat',
      'line',
      'meme',
      'internet',
      'saved images',
      'document',
    };

    final excludedCollectionIDs = Set<int>.from(
      CollectionsService.instance.archivedOrHiddenCollectionIds(),
    );
    collectionLoop:
    for (final collection in collections) {
      final collectionName = collection.displayName.toLowerCase();
      for (final excludedName in excludedNames) {
        if (collectionName.contains(excludedName)) {
          excludedCollectionIDs.add(collection.id);
          continue collectionLoop;
        }
      }
    }

    return excludedCollectionIDs;
  }

  static Future<List<OnThisDayMemory>> _getOnThisDayResults(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    required Map<int, int> seenTimes,
    required Set<int> collectionIDsToExclude,
    Map<String, int>? localIdToIntId,
  }) async {
    return TimeMemoriesCalculator.computeOnThisDayMemories(
      allFiles,
      currentTime,
      seenTimes: seenTimes,
      collectionIDsToExclude: collectionIDsToExclude,
      localIdToIntId: localIdToIntId,
    );
  }

  static Future<String> getDateFormattedLocale({
    required int creationTime,
  }) async {
    final locale = await getLocale();

    return getDateFormatted(
      creationTime: creationTime,
      languageCode: locale!.languageCode,
    );
  }

  static String getDateFormatted({
    required int creationTime,
    BuildContext? context,
    String? languageCode,
  }) {
    return DateFormat.yMMMd(
      context != null
          ? Localizations.localeOf(context).languageCode
          : languageCode ?? "en",
    ).format(DateTime.fromMicrosecondsSinceEpoch(creationTime));
  }

  static int? _seenTimeKeyForFile(
    EnteFile file,
    Map<String, int>? localIdToIntId,
  ) {
    if (localIdToIntId == null) return null;
    final localId = file.localID;
    if (localId == null || localId.isEmpty) return null;
    return localIdToIntId[localId];
  }

  static String? _tryFindLocationName(
    List<Memory> memories,
    CitySearchIndex citySearchIndex, {
    bool base = false,
    Set<String> excludedCountryNames = const {},
  }) {
    final locationContext = _getLocationNameContext(memories, citySearchIndex);
    if (locationContext == null) return null;

    final files = locationContext.files;
    final results = locationContext.results;
    final biggestPlace = locationContext.biggestPlace;

    if (results[biggestPlace]!.length > files.length / 2) {
      return biggestPlace.city;
    }
    if (results.length > 2 &&
        results.keys.map((city) => city.country).toSet().length == 1 &&
        !base &&
        !_isExcludedCountryName(biggestPlace.country, excludedCountryNames)) {
      return biggestPlace.country;
    }
    return null;
  }

  static String? _tryFindCountryName(
    List<Memory> memories,
    CitySearchIndex citySearchIndex,
  ) {
    final locationContext = _getLocationNameContext(memories, citySearchIndex);
    return locationContext?.biggestPlace.country;
  }

  static ({
    List<EnteFile> files,
    Map<City, List<EnteFile>> results,
    City biggestPlace,
  })?
  _getLocationNameContext(
    List<Memory> memories,
    CitySearchIndex citySearchIndex,
  ) {
    final files = Memory.filesFromMemories(memories);
    final results = citySearchIndex.match(files);
    final List<City> sortedByResultCount = results.keys.toList()
      ..sort((a, b) => results[b]!.length.compareTo(results[a]!.length));
    if (sortedByResultCount.isEmpty) return null;

    return (
      files: files,
      results: results,
      biggestPlace: sortedByResultCount.first,
    );
  }

  static bool _isExcludedCountryName(
    String countryName,
    Set<String> excludedCountryNames,
  ) {
    final normalizedCountry = _normalizePlaceName(countryName);
    return normalizedCountry.isNotEmpty &&
        excludedCountryNames.contains(normalizedCountry);
  }

  static String _normalizePlaceName(String placeName) {
    return placeName.trim().toLowerCase();
  }

  static Future<List<Memory>> _bestSelectionPeople(
    List<Memory> memories, {
    int? prefferedSize,
    required bool isLocalGalleryMode,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) => PhotoSelector.bestSelectionPeople(
    memories,
    prefferedSize: prefferedSize,
    isLocalGalleryMode: isLocalGalleryMode,
    fileIDToImageEmbedding: fileIDToImageEmbedding,
    clipPositiveTextVector: clipPositiveTextVector,
  );

  static Future<List<Memory>> _bestSelection(
    List<Memory> memories, {
    int? prefferedSize,
    SelectionDistribution? distributionOverride,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) => PhotoSelector.bestSelection(
    memories,
    prefferedSize: prefferedSize,
    distributionOverride: distributionOverride,
    isLocalGalleryMode: isLocalGalleryMode,
    mlEnabled: mlEnabled,
    fileIdToFaces: fileIdToFaces,
    faceIDsToPersonID: faceIDsToPersonID,
    fileIDToImageEmbedding: fileIDToImageEmbedding,
    clipPositiveTextVector: clipPositiveTextVector,
  );
}
