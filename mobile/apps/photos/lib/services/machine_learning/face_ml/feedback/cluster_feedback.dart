import "dart:async";
import 'dart:developer' as dev show log;
import "dart:math" show Random, min;

import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:ml_linalg/linalg.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/models/base/id.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/search_service.dart";

class ClusterSuggestion {
  final PersonEntity person;
  final String clusterIDToMerge;
  final double distancePersonToCluster;
  final bool usedOnlyMeanForSuggestion;
  final List<EnteFile> filesInCluster;
  final List<String> faceIDsInCluster;

  ClusterSuggestion(
    this.person,
    this.clusterIDToMerge,
    this.distancePersonToCluster,
    this.usedOnlyMeanForSuggestion,
    this.filesInCluster,
    this.faceIDsInCluster,
  );
}

class ClusterFeedbackService<T> {
  final Logger _logger = Logger("ClusterFeedbackService");
  final _computer = Computer.shared();
  static const int _allPeopleSuggestionNamedSampleLimit = 20;
  static const int _allPeopleSuggestionVectorResultCount = 120;

  ClusterFeedbackService._privateConstructor();
  late final mlDataDB = MLDataDB.instance;
  // Person entities and person suggestions require an Ente account; keep all
  // suggestion centroid mapping/vector access pinned to the Ente account DB.
  MLDataDB get _mlDataDBForCentroidVectorDb => MLDataDB.instance;
  ClusterCentroidVectorDB get _clusterCentroidVectorDB =>
      ClusterCentroidVectorDB.instance;
  Future<void>? _prepareClusterCentroidVectorDbFuture;

  static final ClusterFeedbackService instance =
      ClusterFeedbackService._privateConstructor();

  static String lastViewedClusterID = '';
  static void setLastViewedClusterID(String clusterID) {
    lastViewedClusterID = clusterID;
  }

  static void resetLastViewedClusterID() {
    lastViewedClusterID = '';
  }

  /// Returns a list of cluster suggestions for a person.
  Future<List<ClusterSuggestion>> getSuggestionForPerson(
    PersonEntity person, {
    bool extremeFilesFirst = true,
  }) async {
    assert(
      !isLocalGalleryMode,
      "Person suggestions require an Ente account and should not run in local gallery mode.",
    );
    if (isLocalGalleryMode) {
      _logger.info(
        "Skipping getSuggestionForPerson in local gallery mode because person suggestions require an Ente account",
      );
      return [];
    }
    _logger.info(
      'getSuggestionForPerson ${kDebugMode ? person.data.name : person.remoteID}',
    );

    try {
      // Get the suggestions for the person using centroids and median
      final startTime = DateTime.now();
      final List<(String, double, bool)> foundSuggestions =
          await _getSuggestions(person);
      final findSuggestionsTime = DateTime.now();
      _logger.info(
        'getSuggestionForPerson `_getSuggestions`: Found ${foundSuggestions.length} suggestions in ${findSuggestionsTime.difference(startTime).inMilliseconds} ms',
      );

      // Get the files for the suggestions
      final suggestionClusterIDs = foundSuggestions.map((e) => e.$1).toSet();
      final Map<int, Set<String>> fileIdToClusterID = await mlDataDB
          .getFileIdToClusterIDSetForCluster(suggestionClusterIDs);
      final clusterIdToFaceIDs = await mlDataDB.getClusterToFaceIDs(
        suggestionClusterIDs,
      );
      final Map<String, List<EnteFile>> clusterIDToFiles = {};
      final allFiles = await SearchService.instance.getAllFilesForSearch();
      for (final f in allFiles) {
        if (!fileIdToClusterID.containsKey(f.uploadedFileID ?? -1)) {
          continue;
        }
        final cluserIds = fileIdToClusterID[f.uploadedFileID ?? -1]!;
        for (final cluster in cluserIds) {
          if (clusterIDToFiles.containsKey(cluster)) {
            clusterIDToFiles[cluster]!.add(f);
          } else {
            clusterIDToFiles[cluster] = [f];
          }
        }
      }

      final List<ClusterSuggestion> finalSuggestions = [];
      for (final clusterSuggestion in foundSuggestions) {
        if (clusterIDToFiles.containsKey(clusterSuggestion.$1)) {
          finalSuggestions.add(
            ClusterSuggestion(
              person,
              clusterSuggestion.$1,
              clusterSuggestion.$2,
              clusterSuggestion.$3,
              clusterIDToFiles[clusterSuggestion.$1]!,
              clusterIdToFaceIDs[clusterSuggestion.$1]!.toList(),
            ),
          );
        }
      }
      final getFilesTime = DateTime.now();

      final sortingStartTime = DateTime.now();
      if (extremeFilesFirst) {
        try {
          await _sortSuggestionsOnDistanceToPerson(person, finalSuggestions);
        } catch (e, s) {
          _logger.severe("Error in sorting suggestions", e, s);
        }
      }
      _logger.info(
        'getSuggestionForPerson post-processing suggestions took ${DateTime.now().difference(findSuggestionsTime).inMilliseconds} ms, of which sorting took ${DateTime.now().difference(sortingStartTime).inMilliseconds} ms and getting files took ${getFilesTime.difference(findSuggestionsTime).inMilliseconds} ms',
      );

      return finalSuggestions;
    } catch (e, s) {
      _logger.severe("Error in getClusterFilesForPersonID", e, s);
      rethrow;
    }
  }

  Future<void> removeFilesFromPerson(
    List<EnteFile> files,
    PersonEntity p,
  ) async {
    try {
      Future<void>? manualAssignmentUpdate;
      // Get file IDs being removed
      final fileIDsToRemove = files
          .map((file) => file.uploadedFileID)
          .whereType<int>()
          .toSet();

      // Check for manually assigned files to remove
      final manualFileIDs = p.data.manuallyAssigned.toSet();
      final manualToRemove = manualFileIDs.intersection(fileIDsToRemove);
      if (manualToRemove.isNotEmpty) {
        _logger.info(
          'Removing ${manualToRemove.length} manually assigned files from person ${p.remoteID}',
        );
        final updatedManual = manualFileIDs.difference(manualToRemove).toList();
        final updatedPerson = p.copyWith(
          data: p.data.copyWith(manuallyAssigned: updatedManual),
        );
        manualAssignmentUpdate = PersonService.instance.updatePerson(
          updatedPerson,
        );
      }

      // Get the relevant faces to be removed
      final faceIDs = await mlDataDB
          .getFaceIDsForPerson(p.remoteID)
          .then((iterable) => iterable.toList());
      faceIDs.retainWhere((faceID) {
        final fileID = getFileIdFromFaceId<int>(faceID);
        return files.any((file) => file.uploadedFileID == fileID);
      });

      // If no faces to remove (might have been only manually assigned files)
      if (faceIDs.isEmpty) {
        if (manualAssignmentUpdate != null) {
          await manualAssignmentUpdate;
        }
        if (manualToRemove.isNotEmpty) {
          Bus.instance.fire(PeopleChangedEvent());
        } else {
          _logger.warning(
            'No faces or manually assigned files found for person ${p.remoteID} that match the given files',
          );
        }
        return;
      }

      final embeddings = await mlDataDB.getFaceEmbeddingMapForFaces(faceIDs);
      if (embeddings.isEmpty) {
        _logger.severe('No embeddings found for faces $faceIDs');
        Bus.instance.fire(PeopleChangedEvent());
        return;
      }

      final fileIDToCreationTime = await FilesDB.instance
          .getFileIDToCreationTime();

      // Re-cluster within the deleted faces
      final clusterResult = await FaceClusteringService.instance
          .predictWithinClusterComputer(
            embeddings,
            fileIDToCreationTime: fileIDToCreationTime,
            distanceThreshold: 0.20,
          );
      if (clusterResult.isEmpty) {
        _logger.severe('No clusters found or something went wrong');
        return;
      }
      final newFaceIdToClusterID = clusterResult.newFaceIdToCluster;

      // Update the deleted faces
      await mlDataDB.forceUpdateClusterIds(newFaceIdToClusterID);
      await mlDataDB.clusterSummaryUpdate(clusterResult.newClusterSummaries);

      // Make sure the deleted faces don't get suggested in the future
      final notClusterIdToPersonId = <String, String>{};
      for (final clusterId in newFaceIdToClusterID.values.toSet()) {
        notClusterIdToPersonId[clusterId] = p.remoteID;
      }
      await mlDataDB.bulkCaptureNotPersonFeedback(notClusterIdToPersonId);

      // Update remote so new sync does not undo this change
      await PersonService.instance.removeFacesFromPerson(
        person: p,
        faceIDs: faceIDs.toSet(),
      );

      if (manualAssignmentUpdate != null) {
        await manualAssignmentUpdate;
      }

      Bus.instance.fire(PeopleChangedEvent());
      return;
    } catch (e, s) {
      _logger.severe("Error in removeFilesFromPerson", e, s);
      rethrow;
    }
  }

  Future<String> removeFaceFromPerson(
    String faceID,
    PersonEntity person,
  ) async {
    try {
      final updatedClusterID = newClusterID();
      final newFaceIdToClusterID = {faceID: updatedClusterID};
      await mlDataDB.forceUpdateClusterIds(newFaceIdToClusterID);

      // Make sure the deleted faces don't get suggested in the future
      final notClusterIdToPersonId = {updatedClusterID: person.remoteID};
      await mlDataDB.bulkCaptureNotPersonFeedback(notClusterIdToPersonId);

      // Update remote so new sync does not undo this change
      await PersonService.instance.removeFacesFromPerson(
        person: person,
        faceIDs: {faceID},
      );

      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.removedFaceFromCluster,
          relevantFaceIDs: [faceID],
          source: person.remoteID,
        ),
      );
      return updatedClusterID;
    } catch (e, s) {
      _logger.severe("Error in removeFaceFromPerson", e, s);
      rethrow;
    }
  }

  Future<void> removeFilesFromCluster(
    List<EnteFile> files,
    String clusterID,
  ) async {
    _logger.info('removeFilesFromCluster called');
    try {
      // Get the relevant faces to be removed
      final faceIDs = await mlDataDB
          .getFaceIDsForCluster(clusterID)
          .then((iterable) => iterable.toList());
      faceIDs.retainWhere((faceID) {
        final fileID = getFileIdFromFaceId<int>(faceID);
        return files.any((file) => file.uploadedFileID == fileID);
      });
      final embeddings = await mlDataDB.getFaceEmbeddingMapForFaces(faceIDs);

      if (faceIDs.isEmpty || embeddings.isEmpty) {
        _logger.severe(
          'No faces or embeddings found for cluster $clusterID that match the given files',
        );
        return;
      }

      final fileIDToCreationTime = await FilesDB.instance
          .getFileIDToCreationTime();

      // Re-cluster within the deleted faces
      final clusterResult = await FaceClusteringService.instance
          .predictWithinClusterComputer(
            embeddings,
            fileIDToCreationTime: fileIDToCreationTime,
            distanceThreshold: 0.20,
          );
      if (clusterResult.isEmpty) {
        _logger.severe('No clusters found or something went wrong');
        return;
      }
      final newFaceIdToClusterID = clusterResult.newFaceIdToCluster;

      // Update the deleted faces
      await mlDataDB.forceUpdateClusterIds(newFaceIdToClusterID);
      await mlDataDB.clusterSummaryUpdate(clusterResult.newClusterSummaries);

      Bus.instance.fire(
        PeopleChangedEvent(
          relevantFiles: files,
          type: PeopleEventType.removedFilesFromCluster,
          source: clusterID,
        ),
      );
      _logger.info('removeFilesFromCluster done');
      return;
    } catch (e, s) {
      _logger.severe("Error in removeFilesFromCluster", e, s);
      rethrow;
    }
  }

  Future<String> removeFaceFromCluster({
    required String faceID,
    String? clusterID,
  }) async {
    try {
      final updatedClusterID = newClusterID();
      final newFaceIdToClusterID = {faceID: updatedClusterID};
      await mlDataDB.forceUpdateClusterIds(newFaceIdToClusterID);

      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.removedFaceFromCluster,
          relevantFaceIDs: [faceID],
          source: clusterID ?? "",
        ),
      );
      return updatedClusterID;
    } catch (e, s) {
      _logger.severe("Error in removeFaceFromCluster", e, s);
      rethrow;
    }
  }

  Future<void> addFacesToCluster(List<String> faceIDs, String clusterID) async {
    final faceIDToClusterID = <String, String>{};
    for (final faceID in faceIDs) {
      faceIDToClusterID[faceID] = clusterID;
    }
    await mlDataDB.forceUpdateClusterIds(faceIDToClusterID);
    Bus.instance.fire(PeopleChangedEvent());
    return;
  }

  Future<List<ClusterSuggestion>> getAllLargePersonSuggestions() async {
    final personsMap = await PersonService.instance.getPersonsMap();
    if (personsMap.isEmpty) return [];
    try {
      final allClusterIdsToCountMapFuture = mlDataDB.clusterIdToFaceCount();
      final personToClusterIDsFuture = mlDataDB.getPersonToClusterIDs();
      final personToRejectedSuggestionsFuture = mlDataDB
          .getPersonToRejectedSuggestions();
      final canUseVectorDbFuture =
          _canUseClusterCentroidVectorDbForSuggestions();
      await Future.wait<Object?>([
        allClusterIdsToCountMapFuture,
        personToClusterIDsFuture,
        personToRejectedSuggestionsFuture,
        canUseVectorDbFuture,
      ], eagerError: false);
      final allClusterIdsToCountMap = await allClusterIdsToCountMapFuture;
      final personToClusterIDs = await personToClusterIDsFuture;
      final personToRejectedSuggestions =
          await personToRejectedSuggestionsFuture;
      final canUseVectorDb = await canUseVectorDbFuture;
      if (!canUseVectorDb) {
        _logger.info(
          "Cluster centroid vector DB unavailable for all-people suggestions, falling back to legacy mean suggestions",
        );
        return _getAllLargePersonSuggestionsLegacy(
          personsMap,
          allClusterIdsToCountMap,
          personToClusterIDs,
          personToRejectedSuggestions,
        );
      }

      final selectedPersonIDs = _selectPersonIDsForAllPeopleSuggestions(
        personsMap,
        personToClusterIDs,
        allClusterIdsToCountMap,
      );
      if (selectedPersonIDs.isEmpty) {
        return [];
      }

      final personIdToClusters = <String, Set<String>>{};
      final selectedPersonClusters = <String>{};
      for (final personID in selectedPersonIDs) {
        final clusters = (personToClusterIDs[personID] ?? const <String>{})
            .where(allClusterIdsToCountMap.containsKey)
            .toSet();
        if (clusters.isEmpty) {
          continue;
        }
        personIdToClusters[personID] = clusters;
        selectedPersonClusters.addAll(clusters);
      }
      if (personIdToClusters.isEmpty) {
        return [];
      }

      final assignedClustersToAnyPerson = <String>{};
      for (final clusters in personToClusterIDs.values) {
        assignedClustersToAnyPerson.addAll(clusters);
      }
      final ignoredClustersForAverages = assignedClustersToAnyPerson.difference(
        selectedPersonClusters,
      );

      final clusterAvg = await _getUpdateClusterAvg(
        allClusterIdsToCountMap,
        ignoredClustersForAverages,
        minClusterSize: 1,
      );
      if (clusterAvg.isEmpty) {
        return [];
      }

      final clusterIDToVectorID = await _mlDataDBForCentroidVectorDb
          .getClusterCentroidVectorIdMap(
            clusterAvg.keys,
            createIfMissing: false,
          );
      if (clusterIDToVectorID.isEmpty) {
        return [];
      }
      final vectorIDToClusterID = {
        for (final entry in clusterIDToVectorID.entries) entry.value: entry.key,
      };

      final personIDToQueryClusters = <String, Set<String>>{};
      final queryVectorIDs = <int>{};
      for (final entry in personIdToClusters.entries) {
        final validClusters = <String>{};
        for (final clusterID in entry.value) {
          if (!clusterAvg.containsKey(clusterID)) {
            continue;
          }
          final vectorID = clusterIDToVectorID[clusterID];
          if (vectorID == null) {
            continue;
          }
          validClusters.add(clusterID);
          queryVectorIDs.add(vectorID);
        }
        if (validClusters.isNotEmpty) {
          personIDToQueryClusters[entry.key] = validClusters;
        }
      }
      if (personIDToQueryClusters.isEmpty || queryVectorIDs.isEmpty) {
        return [];
      }

      late final Map<int, List<(int, double)>> rawMatchesByQueryVectorID;
      try {
        rawMatchesByQueryVectorID = await _clusterCentroidVectorDB
            .bulkSearchApproxClosestCentroidsForKeysWithinDistance(
              queryVectorIDs,
              count: _allPeopleSuggestionVectorResultCount,
              maxDistance: 0.65,
            );
      } catch (e, s) {
        _logger.warning(
          "Batched centroid search failed, falling back to legacy mean suggestions",
          e,
          s,
        );
        return _getAllLargePersonSuggestionsLegacy(
          personsMap,
          allClusterIdsToCountMap,
          personToClusterIDs,
          personToRejectedSuggestions,
        );
      }

      final queryClusterToMatches = <String, List<(String, double)>>{};
      final queryClusterNeedsFallbackSearch = <String, bool>{};
      final queryClustersMissingFromVectorIndex = <String>{};
      for (final queryClusters in personIDToQueryClusters.values) {
        for (final queryClusterID in queryClusters) {
          final queryVectorID = clusterIDToVectorID[queryClusterID];
          if (queryVectorID == null) {
            continue;
          }
          final hasRawMatchesForQuery = rawMatchesByQueryVectorID.containsKey(
            queryVectorID,
          );
          final rawMatches =
              rawMatchesByQueryVectorID[queryVectorID] ??
              const <(int, double)>[];
          if (!hasRawMatchesForQuery) {
            queryClustersMissingFromVectorIndex.add(queryClusterID);
          }
          queryClusterNeedsFallbackSearch[queryClusterID] =
              !hasRawMatchesForQuery ||
              rawMatches.length >= _allPeopleSuggestionVectorResultCount;
          final mappedMatches = <(String, double)>[];
          for (final match in rawMatches) {
            final matchedClusterID = vectorIDToClusterID[match.$1];
            if (matchedClusterID == null) {
              continue;
            }
            mappedMatches.add((matchedClusterID, match.$2));
          }
          queryClusterToMatches[queryClusterID] = mappedMatches;
        }
      }
      if (queryClustersMissingFromVectorIndex.isNotEmpty) {
        _logger.warning(
          "Batched centroid search missed ${queryClustersMissingFromVectorIndex.length} query clusters due to absent vector keys in the index; running filtered fallback for affected clusters",
        );
      }

      final selectedClusterToFaceIDs = await mlDataDB.getClusterToFaceIDs(
        selectedPersonClusters,
      );
      final personIDToFileIDs = <String, Set<int>>{};
      for (final entry in personIDToQueryClusters.entries) {
        final fileIDs = <int>{};
        for (final clusterID in entry.value) {
          final faceIDs =
              selectedClusterToFaceIDs[clusterID] ?? const <String>[];
          for (final faceID in faceIDs) {
            fileIDs.add(getFileIdFromFaceId<int>(faceID));
          }
        }
        personIDToFileIDs[entry.key] = fileIDs;
      }

      final personIDToIgnoredClusters = <String, Set<String>>{};
      for (final entry in personIDToQueryClusters.entries) {
        final ignored = <String>{}
          ..addAll(assignedClustersToAnyPerson)
          ..removeAll(entry.value)
          ..addAll(personToRejectedSuggestions[entry.key] ?? const <String>{});
        personIDToIgnoredClusters[entry.key] = ignored;
      }

      // If the global top-k gets fully consumed by ignored/self clusters,
      // rerun only those starved queries with person-specific filtering.
      final personIDToFallbackQueryClusters = <String, List<String>>{};
      for (final entry in personIDToQueryClusters.entries) {
        final personID = entry.key;
        final personClusters = entry.value;
        final ignoredClusters = personIDToIgnoredClusters[personID]!;
        final fallbackQueryClusters = <String>[];

        for (final queryClusterID in personClusters) {
          final matchesForCluster =
              queryClusterToMatches[queryClusterID] ??
              const <(String, double)>[];
          if (!(queryClusterNeedsFallbackSearch[queryClusterID] ?? false)) {
            continue;
          }
          var hasUsableCandidate = false;
          for (final match in matchesForCluster) {
            final candidateClusterID = match.$1;
            if (ignoredClusters.contains(candidateClusterID) ||
                personClusters.contains(candidateClusterID)) {
              continue;
            }
            if (!clusterAvg.containsKey(candidateClusterID)) {
              continue;
            }
            hasUsableCandidate = true;
            break;
          }
          if (!hasUsableCandidate) {
            fallbackQueryClusters.add(queryClusterID);
          }
        }

        if (fallbackQueryClusters.isNotEmpty) {
          personIDToFallbackQueryClusters[personID] = fallbackQueryClusters;
        }
      }

      if (personIDToFallbackQueryClusters.isNotEmpty) {
        final personIDToAllowedVectorIDs = <String, Set<int>>{};

        Set<int> getAllowedVectorIDs(String personID) {
          final cached = personIDToAllowedVectorIDs[personID];
          if (cached != null) {
            return cached;
          }
          final personClusters = personIDToQueryClusters[personID]!;
          final ignoredClusters = personIDToIgnoredClusters[personID]!;
          final allowedVectorIDs = <int>{};
          for (final entry in clusterIDToVectorID.entries) {
            final clusterID = entry.key;
            if (ignoredClusters.contains(clusterID) ||
                personClusters.contains(clusterID)) {
              continue;
            }
            allowedVectorIDs.add(entry.value);
          }
          personIDToAllowedVectorIDs[personID] = allowedVectorIDs;
          return allowedVectorIDs;
        }

        var fallbackQueryCount = 0;
        for (final entry in personIDToFallbackQueryClusters.entries) {
          final personID = entry.key;
          final allowedVectorIDs = getAllowedVectorIDs(personID);
          if (allowedVectorIDs.isEmpty) {
            continue;
          }

          final queryClusterIDs = <String>[];
          final queryVectors = <List<double>>[];
          for (final queryClusterID in entry.value) {
            final queryVector = clusterAvg[queryClusterID];
            if (queryVector == null) {
              continue;
            }
            queryClusterIDs.add(queryClusterID);
            queryVectors.add(queryVector.toList(growable: false));
          }
          if (queryClusterIDs.isEmpty) {
            continue;
          }

          List<List<(int, double)>> filteredMatchesByQuery;
          try {
            filteredMatchesByQuery = await _clusterCentroidVectorDB
                .bulkSearchApproxClosestCentroidsWithinDistance(
                  queryVectors,
                  allowedVectorIDs,
                  maxDistance: 0.65,
                  count: _allPeopleSuggestionVectorResultCount,
                );
          } catch (e, s) {
            _logger.warning(
              "Filtered centroid fallback search failed for person $personID",
              e,
              s,
            );
            continue;
          }

          final alignedLength = min(
            queryClusterIDs.length,
            filteredMatchesByQuery.length,
          );
          for (var i = 0; i < alignedLength; i++) {
            final queryClusterID = queryClusterIDs[i];
            final filteredMatches = filteredMatchesByQuery[i];
            if (filteredMatches.isEmpty) {
              continue;
            }

            final mappedMatches = <(String, double)>[];
            for (final match in filteredMatches) {
              final matchedClusterID = vectorIDToClusterID[match.$1];
              if (matchedClusterID == null) {
                continue;
              }
              mappedMatches.add((matchedClusterID, match.$2));
            }
            if (mappedMatches.isNotEmpty) {
              queryClusterToMatches[queryClusterID] = mappedMatches;
              fallbackQueryCount++;
            }
          }
        }

        if (fallbackQueryCount > 0) {
          _logger.info(
            "Ran filtered centroid fallback search for $fallbackQueryCount starved query clusters",
          );
        }
      }

      final personIDToCandidates = <String, List<(String, double)>>{};
      final allCandidateClusterIDs = <String>{};
      for (final entry in personIDToQueryClusters.entries) {
        final personID = entry.key;
        final personClusters = entry.value;
        final ignoredClusters = personIDToIgnoredClusters[personID]!;
        final bestDistanceByCluster = <String, double>{};

        for (final queryClusterID in personClusters) {
          final matchesForCluster =
              queryClusterToMatches[queryClusterID] ??
              const <(String, double)>[];
          for (final match in matchesForCluster) {
            final candidateClusterID = match.$1;
            final distance = match.$2;
            if (distance >= 0.65) {
              break;
            }
            if (ignoredClusters.contains(candidateClusterID) ||
                personClusters.contains(candidateClusterID)) {
              continue;
            }
            if (!clusterAvg.containsKey(candidateClusterID)) {
              continue;
            }
            final previous = bestDistanceByCluster[candidateClusterID];
            if (previous == null || distance < previous) {
              bestDistanceByCluster[candidateClusterID] = distance;
            }
          }
        }

        if (bestDistanceByCluster.isEmpty) {
          continue;
        }

        final candidates =
            bestDistanceByCluster.entries
                .map((e) => (e.key, e.value))
                .toList(growable: false)
              ..sort((a, b) => a.$2.compareTo(b.$2));
        personIDToCandidates[personID] = candidates;
        allCandidateClusterIDs.addAll(candidates.map((e) => e.$1));
      }
      if (personIDToCandidates.isEmpty || allCandidateClusterIDs.isEmpty) {
        return [];
      }

      final candidateClusterToFaceIDs = await mlDataDB.getClusterToFaceIDs(
        allCandidateClusterIDs,
      );
      final candidateClusterToFileIDs = <String, Set<int>>{};
      for (final entry in candidateClusterToFaceIDs.entries) {
        candidateClusterToFileIDs[entry.key] = entry.value
            .map(getFileIdFromFaceId<int>)
            .toSet();
      }

      final bestSuggestionPerPerson = <String, (String, double, bool)>{};
      final personIDToMedianCandidates = <String, List<String>>{};
      final overlapRejections = <(String, String)>{};
      final overlapRejectedByPerson = <String, Set<String>>{};
      final checkSizes = [20, kMinimumClusterSizeSearchResult, 10, 5, 1];

      for (final entry in personIDToCandidates.entries) {
        final personID = entry.key;
        final candidates = entry.value;
        final personClusters = personIDToQueryClusters[personID]!;
        final personFileIDs = personIDToFileIDs[personID] ?? const <int>{};

        final smallestPersonClusterSize = personClusters
            .map((clusterID) => allClusterIdsToCountMap[clusterID] ?? 0)
            .reduce((value, element) => min(value, element));

        bool foundGoodMeanSuggestion = false;
        for (final minimumSize in checkSizes.toSet()) {
          if (smallestPersonClusterSize <
              min(minimumSize, kMinimumClusterSizeSearchResult)) {
            continue;
          }
          for (final candidate in candidates) {
            final candidateClusterID = candidate.$1;
            final meanDistance = candidate.$2;
            if (meanDistance >= 0.45) {
              break;
            }
            if ((allClusterIdsToCountMap[candidateClusterID] ?? 0) <
                minimumSize) {
              continue;
            }
            final candidateFileIDs =
                candidateClusterToFileIDs[candidateClusterID] ?? const <int>{};
            if (personFileIDs.isNotEmpty && candidateFileIDs.isNotEmpty) {
              final overlap = personFileIDs.intersection(candidateFileIDs);
              if (overlap.isNotEmpty &&
                  ((overlap.length / candidateFileIDs.length) > 0.1)) {
                overlapRejections.add((personID, candidateClusterID));
                overlapRejectedByPerson
                    .putIfAbsent(personID, () => <String>{})
                    .add(candidateClusterID);
                continue;
              }
            }
            bestSuggestionPerPerson[personID] = (
              candidateClusterID,
              meanDistance,
              true,
            );
            foundGoodMeanSuggestion = true;
            break;
          }
          if (foundGoodMeanSuggestion) {
            break;
          }
        }

        if (foundGoodMeanSuggestion) {
          continue;
        }

        final medianCandidates = <String>[];
        final rejectedForPerson =
            overlapRejectedByPerson[personID] ?? const <String>{};
        for (final candidate in candidates) {
          if (candidate.$2 >= 0.65) {
            break;
          }
          final candidateClusterID = candidate.$1;
          if (rejectedForPerson.contains(candidateClusterID)) {
            continue;
          }
          medianCandidates.add(candidateClusterID);
          if (medianCandidates.length >= 20) {
            break;
          }
        }
        if (medianCandidates.isNotEmpty) {
          personIDToMedianCandidates[personID] = medianCandidates;
        }
      }

      if (overlapRejections.isNotEmpty) {
        for (final rejection in overlapRejections) {
          await mlDataDB.captureNotPersonFeedback(
            personID: rejection.$1,
            clusterID: rejection.$2,
          );
        }
      }

      if (personIDToMedianCandidates.isNotEmpty) {
        final clustersNeededForMedian = <String>{};
        for (final entry in personIDToMedianCandidates.entries) {
          clustersNeededForMedian.addAll(entry.value);
          clustersNeededForMedian.addAll(personIDToQueryClusters[entry.key]!);
        }
        final embeddingsByCluster = await mlDataDB.getFaceEmbeddingsForClusters(
          clustersNeededForMedian,
        );
        final sampledVectorsByCluster = <String, List<Vector>>{};

        List<Vector> getSampledVectors(String clusterID) {
          final cached = sampledVectorsByCluster[clusterID];
          if (cached != null) {
            return cached;
          }
          final embeddingsProto =
              embeddingsByCluster[clusterID] ?? const <Uint8List>[];
          if (embeddingsProto.isEmpty) {
            sampledVectorsByCluster[clusterID] = const [];
            return const [];
          }
          final sampledEmbeddingsProto = _randomSampleWithoutReplacement(
            embeddingsProto,
            50,
          );
          final sampledVectors = sampledEmbeddingsProto
              .map(
                (embedding) => Vector.fromList(
                  EVector.fromBuffer(embedding).values,
                  dtype: DType.float32,
                ),
              )
              .toList(growable: false);
          sampledVectorsByCluster[clusterID] = sampledVectors;
          return sampledVectors;
        }

        for (final entry in personIDToMedianCandidates.entries) {
          final personID = entry.key;
          final candidateClusterIDs = entry.value;
          final personClusters = personIDToQueryClusters[personID]!;
          final personEmbeddingsProto = <Uint8List>[];
          for (final personClusterID in personClusters) {
            final embeddingsForCluster =
                embeddingsByCluster[personClusterID] ?? const <Uint8List>[];
            personEmbeddingsProto.addAll(embeddingsForCluster);
          }
          if (personEmbeddingsProto.isEmpty) {
            continue;
          }
          final sampledPersonEmbeddingsProto = _randomSampleWithoutReplacement(
            personEmbeddingsProto,
            50,
          );
          final sampledPersonEmbeddings = sampledPersonEmbeddingsProto
              .map(
                (embedding) => Vector.fromList(
                  EVector.fromBuffer(embedding).values,
                  dtype: DType.float32,
                ),
              )
              .toList(growable: false);
          if (sampledPersonEmbeddings.isEmpty) {
            continue;
          }

          double minMedianDistance = 0.62;
          (String, double)? bestMedianSuggestion;
          for (final otherClusterID in candidateClusterIDs) {
            final sampledOtherEmbeddings = getSampledVectors(otherClusterID);
            if (sampledOtherEmbeddings.isEmpty) {
              continue;
            }
            final distances = <double>[];
            for (final otherEmbedding in sampledOtherEmbeddings) {
              for (final personEmbedding in sampledPersonEmbeddings) {
                distances.add(1 - personEmbedding.dot(otherEmbedding));
              }
            }
            if (distances.isEmpty) {
              continue;
            }
            distances.sort();
            final medianDistance = distances[distances.length ~/ 2];
            if (medianDistance < minMedianDistance) {
              minMedianDistance = medianDistance;
              bestMedianSuggestion = (otherClusterID, medianDistance);
              if (medianDistance < 0.55) {
                break;
              }
            }
          }
          if (bestMedianSuggestion != null) {
            bestSuggestionPerPerson[personID] = (
              bestMedianSuggestion.$1,
              bestMedianSuggestion.$2,
              false,
            );
          }
        }
      }

      if (bestSuggestionPerPerson.isEmpty) {
        return [];
      }

      final bestPersonPerCluster = <String, (String, double, bool)>{};
      for (final entry in bestSuggestionPerPerson.entries) {
        final personID = entry.key;
        final suggestion = entry.value;
        final previous = bestPersonPerCluster[suggestion.$1];
        if (previous == null || suggestion.$2 < previous.$2) {
          bestPersonPerCluster[suggestion.$1] = (
            personID,
            suggestion.$2,
            suggestion.$3,
          );
        }
      }
      if (bestPersonPerCluster.isEmpty) {
        return [];
      }

      final rankedSuggestions =
          bestPersonPerCluster.entries
              .map(
                (entry) =>
                    (entry.key, entry.value.$2, entry.value.$1, entry.value.$3),
              )
              .toList(growable: false)
            ..sort((a, b) => a.$2.compareTo(b.$2));

      final suggestionClusterIDs = rankedSuggestions
          .map((entry) => entry.$1)
          .toSet();

      final fileIdToClusterID = await mlDataDB
          .getFileIdToClusterIDSetForCluster(suggestionClusterIDs);
      final clusterIdToFaceIDs = await mlDataDB.getClusterToFaceIDs(
        suggestionClusterIDs,
      );

      final clusterIDToFiles = <String, List<EnteFile>>{};
      final allFiles = await SearchService.instance.getAllFilesForSearch();
      for (final file in allFiles) {
        final fileID = file.uploadedFileID;
        if (fileID == null) {
          continue;
        }
        final clusterIDs = fileIdToClusterID[fileID];
        if (clusterIDs == null) {
          continue;
        }
        for (final clusterID in clusterIDs) {
          clusterIDToFiles.putIfAbsent(clusterID, () => []).add(file);
        }
      }

      final finalSuggestions = <ClusterSuggestion>[];
      for (final suggestion in rankedSuggestions) {
        final clusterID = suggestion.$1;
        final personID = suggestion.$3;
        final person = personsMap[personID];
        final filesInCluster = clusterIDToFiles[clusterID];
        final faceIDs = clusterIdToFaceIDs[clusterID];
        if (person == null || filesInCluster == null || faceIDs == null) {
          continue;
        }
        finalSuggestions.add(
          ClusterSuggestion(
            person,
            clusterID,
            suggestion.$2,
            suggestion.$4,
            filesInCluster,
            faceIDs.toList(growable: false),
          ),
        );
      }

      try {
        await _sortSuggestionsOnDistanceToPerson(null, finalSuggestions);
      } catch (e, s) {
        _logger.severe("Error in sorting suggestions", e, s);
      }
      return finalSuggestions;
    } catch (e, s) {
      _logger.severe("Error in getAllLargePersonSuggestions", e, s);
      rethrow;
    }
  }

  Set<String> _selectPersonIDsForAllPeopleSuggestions(
    Map<String, PersonEntity> personsMap,
    Map<String, Set<String>> personToClusterIDs,
    Map<String, int> allClusterIdsToCountMap,
  ) {
    final eligiblePersons = personsMap.values
        .where((person) {
          if (person.data.isIgnored) {
            return false;
          }
          final personClusters =
              personToClusterIDs[person.remoteID] ?? const <String>{};
          if (personClusters.isEmpty) {
            return false;
          }
          for (final clusterID in personClusters) {
            if (allClusterIdsToCountMap.containsKey(clusterID)) {
              return true;
            }
          }
          return false;
        })
        .toList(growable: false);

    if (eligiblePersons.isEmpty) {
      return {};
    }

    final namedPersons = eligiblePersons
        .where((person) => person.data.name.trim().isNotEmpty)
        .toList(growable: false);
    if (namedPersons.length <= _allPeopleSuggestionNamedSampleLimit) {
      return eligiblePersons.map((person) => person.remoteID).toSet();
    }

    final sampledNamedPersons = [...namedPersons]..shuffle(Random());
    return sampledNamedPersons
        .take(_allPeopleSuggestionNamedSampleLimit)
        .map((person) => person.remoteID)
        .toSet();
  }

  Future<List<ClusterSuggestion>> _getAllLargePersonSuggestionsLegacy(
    Map<String, PersonEntity> personsMap,
    Map<String, int> allClusterIdsToCountMap,
    Map<String, Set<String>> personToClusterIDs,
    Map<String, Set<String>> personToRejectedSuggestions,
  ) async {
    final personIdToBiggestCluster = <String, String>{};
    final biggestClusterToPersonID = <String, String>{};
    final personIdToOtherPersonClusterIDs = <String, Set<String>>{};
    for (final person in personsMap.values) {
      final personID = person.remoteID;
      final personClusters = personToClusterIDs[personID] ?? {};
      if (person.data.isIgnored) {
        personIdToOtherPersonClusterIDs[personID] = personClusters;
        continue;
      }
      int biggestClusterSize = 0;
      String biggestClusterID = '';
      final Set<String> otherPersonClusterIDs = {};
      for (final clusterID in personClusters) {
        final clusterSize = allClusterIdsToCountMap[clusterID] ?? 0;
        if (clusterSize > biggestClusterSize) {
          if (biggestClusterSize > 0) {
            otherPersonClusterIDs.add(biggestClusterID);
          }
          biggestClusterID = clusterID;
          biggestClusterSize = clusterSize;
        } else {
          otherPersonClusterIDs.add(clusterID);
        }
      }
      if (biggestClusterID.isNotEmpty) {
        personIdToBiggestCluster[personID] = biggestClusterID;
        biggestClusterToPersonID[biggestClusterID] = personID;
      }
      personIdToOtherPersonClusterIDs[personID] = otherPersonClusterIDs;
    }
    if (biggestClusterToPersonID.isEmpty ||
        personIdToOtherPersonClusterIDs.isEmpty) {
      return [];
    }
    final allPersonClusters = biggestClusterToPersonID.keys.toSet();
    final allOtherPersonClustersToIgnore = <String>{};
    for (final ignoredClusters in personIdToOtherPersonClusterIDs.values) {
      allOtherPersonClustersToIgnore.addAll(ignoredClusters);
    }
    final clusterAvg = await _getUpdateClusterAvg(
      allClusterIdsToCountMap,
      allOtherPersonClustersToIgnore,
      minClusterSize: kMinimumClusterSizeSearchResult,
    );

    final personClusterToIgnoredClusters = <String, Set<String>>{};
    for (final personID in personToRejectedSuggestions.keys) {
      final personCluster = personIdToBiggestCluster[personID];
      if (personCluster == null) continue;
      final ignoredClusters = personToRejectedSuggestions[personID] ?? {};
      personClusterToIgnoredClusters[personCluster] = ignoredClusters;
    }

    final foundSuggestions = await calcSuggestionsMeanInComputer(
      clusterAvg,
      allPersonClusters,
      allOtherPersonClustersToIgnore,
      0.55,
      personClusterToIgnoredClusters: personClusterToIgnoredClusters,
    );
    if (foundSuggestions.isEmpty) {
      return [];
    }

    final suggestionClusterIDs = foundSuggestions.map((e) => e.$1).toSet();
    final fileIdToClusterID = await mlDataDB.getFileIdToClusterIDSetForCluster(
      suggestionClusterIDs,
    );
    final clusterIdToFaceIDs = await mlDataDB.getClusterToFaceIDs(
      suggestionClusterIDs,
    );
    final clusterIDToFiles = <String, List<EnteFile>>{};
    final allFiles = await SearchService.instance.getAllFilesForSearch();
    for (final file in allFiles) {
      final fileID = file.uploadedFileID;
      if (fileID == null) {
        continue;
      }
      final clusterIds = fileIdToClusterID[fileID];
      if (clusterIds == null) {
        continue;
      }
      for (final cluster in clusterIds) {
        clusterIDToFiles.putIfAbsent(cluster, () => []).add(file);
      }
    }

    final finalSuggestions = <ClusterSuggestion>[];
    for (final clusterSuggestion in foundSuggestions) {
      final personID = biggestClusterToPersonID[clusterSuggestion.$3];
      final person = personID == null ? null : personsMap[personID];
      final files = clusterIDToFiles[clusterSuggestion.$1];
      final faceIDs = clusterIdToFaceIDs[clusterSuggestion.$1];
      if (person == null || files == null || faceIDs == null) {
        continue;
      }
      finalSuggestions.add(
        ClusterSuggestion(
          person,
          clusterSuggestion.$1,
          clusterSuggestion.$2,
          true,
          files,
          faceIDs.toList(growable: false),
        ),
      );
    }
    try {
      await _sortSuggestionsOnDistanceToPerson(null, finalSuggestions);
    } catch (e, s) {
      _logger.severe("Error in sorting legacy suggestions", e, s);
    }
    return finalSuggestions;
  }

  Future<bool> checkAndDoAutomaticMerges(
    PersonEntity p, {
    required String personClusterID,
    bool firePeopleChangedEvent = true,
  }) async {
    final faceIDs = await mlDataDB.getFaceIDsForCluster(personClusterID);

    if (faceIDs.length < 2 * kMinimumClusterSizeSearchResult) {
      final fileIDs = faceIDs.map(getFileIdFromFaceId<int>).toSet();
      if (fileIDs.length < kMinimumClusterSizeSearchResult) {
        _logger.info(
          'Cluster $personClusterID has less than $kMinimumClusterSizeSearchResult faces, not doing automatic merges',
        );
        return false;
      }
    }
    final List<(String, double, String)> suggestions =
        await _getFastSuggestions(
          p,
          personClusterID,
          PersonService.autoMergeThreshold,
        );

    if (suggestions.isEmpty) {
      _logger.info(
        'No automatic merge suggestions for ${kDebugMode ? p.data.name : "private"}',
      );
      return false;
    }

    // log suggestions
    _logger.info(
      'suggestions for ${kDebugMode ? p.data.name : "private"} for cluster ID ${p.remoteID} are  suggestions $suggestions}',
    );

    for (final suggestion in suggestions) {
      final clusterID = suggestion.$1;
      await mlDataDB.assignClusterToPerson(
        personID: p.remoteID,
        clusterID: clusterID,
      );
    }

    if (firePeopleChangedEvent) {
      Bus.instance.fire(PeopleChangedEvent());
    }

    return true;
  }

  Future<void> addClusterToExistingPerson({
    required PersonEntity person,
    required String clusterID,
  }) async {
    if (person.data.rejectedFaceIDs.isNotEmpty) {
      final clusterFaceIDs = await mlDataDB.getFaceIDsForCluster(clusterID);
      final rejectedLengthBefore = person.data.rejectedFaceIDs.length;
      person.data.rejectedFaceIDs.removeWhere(
        (faceID) => clusterFaceIDs.contains(faceID),
      );
      final rejectedLengthAfter = person.data.rejectedFaceIDs.length;
      if (rejectedLengthBefore != rejectedLengthAfter) {
        _logger.info(
          'Removed ${rejectedLengthBefore - rejectedLengthAfter} rejected faces from person ${person.data.name} due to adding cluster $clusterID',
        );
        await PersonService.instance.updatePerson(person);
      }
    }
    await mlDataDB.assignClusterToPerson(
      personID: person.remoteID,
      clusterID: clusterID,
    );
    Bus.instance.fire(
      PeopleChangedEvent(
        type: PeopleEventType.addedClusterToPerson,
        source: clusterID,
      ),
    );
  }

  Future<PersonEntity> ignoreCluster(
    String clusterID, {
    bool firePeopleChangedEvent = true,
  }) async {
    final ignoredPerson = await PersonService.instance.addPerson(
      name: '',
      clusterID: clusterID,
      isHidden: true,
    );
    final merged = await checkAndDoAutomaticMerges(
      ignoredPerson,
      personClusterID: clusterID,
      firePeopleChangedEvent: firePeopleChangedEvent,
    );
    if (!merged && firePeopleChangedEvent) {
      Bus.instance.fire(
        PeopleChangedEvent(person: ignoredPerson, source: "ignore_cluster"),
      );
    }
    return ignoredPerson;
  }

  Future<List<(String, int)>> checkForMixedClusters() async {
    final allClusterToFaceCount = await mlDataDB.clusterIdToFaceCount();
    final clustersToInspect = <String>[];
    for (final clusterID in allClusterToFaceCount.keys) {
      if (allClusterToFaceCount[clusterID]! > 20 &&
          allClusterToFaceCount[clusterID]! < 500) {
        clustersToInspect.add(clusterID);
      }
    }

    final fileIDToCreationTime = await FilesDB.instance
        .getFileIDToCreationTime();

    final susClusters = <(String, int)>[];

    final inspectionStart = DateTime.now();
    for (final clusterID in clustersToInspect) {
      final int originalClusterSize = allClusterToFaceCount[clusterID]!;
      final faceIDs = await mlDataDB.getFaceIDsForCluster(clusterID);

      final embeddings = await mlDataDB.getFaceEmbeddingMapForFaces(faceIDs);

      final clusterResult = await FaceClusteringService.instance
          .predictWithinClusterComputer(
            embeddings,
            fileIDToCreationTime: fileIDToCreationTime,
            distanceThreshold: 0.22,
          );

      if (clusterResult.isEmpty) {
        _logger.warning(
          '[CheckMixedClusters] Clustering did not seem to work for cluster $clusterID of size ${allClusterToFaceCount[clusterID]}',
        );
        continue;
      }

      final newClusterIdToCount = clusterResult.newClusterIdToFaceIds.map((
        key,
        value,
      ) {
        return MapEntry(key, value.length);
      });
      final amountOfNewClusters = newClusterIdToCount.length;

      _logger.info(
        '[CheckMixedClusters] Broke up cluster $clusterID into $amountOfNewClusters clusters \n ${newClusterIdToCount.toString()}',
      );

      // Now find the sizes of the biggest and second biggest cluster
      final String biggestClusterID = newClusterIdToCount.keys.reduce((a, b) {
        return newClusterIdToCount[a]! > newClusterIdToCount[b]! ? a : b;
      });
      final int biggestSize = newClusterIdToCount[biggestClusterID]!;
      final biggestRatio = biggestSize / originalClusterSize;
      if (newClusterIdToCount.length > 1) {
        final List<String> clusterIDs = newClusterIdToCount.keys.toList();
        clusterIDs.remove(biggestClusterID);
        final String secondBiggestClusterID = clusterIDs.reduce((a, b) {
          return newClusterIdToCount[a]! > newClusterIdToCount[b]! ? a : b;
        });
        final int secondBiggestSize =
            newClusterIdToCount[secondBiggestClusterID]!;
        final secondBiggestRatio = secondBiggestSize / originalClusterSize;

        if (biggestRatio < 0.5 || secondBiggestRatio > 0.2) {
          final faceIdsOfCluster = await mlDataDB.getFaceIDsForCluster(
            clusterID,
          );
          final uniqueFileIDs = faceIdsOfCluster
              .map(getFileIdFromFaceId<int>)
              .toSet();
          susClusters.add((clusterID, uniqueFileIDs.length));
          _logger.info(
            '[CheckMixedClusters] Detected that cluster $clusterID with size ${uniqueFileIDs.length} might be mixed',
          );
        }
      } else {
        _logger.info(
          '[CheckMixedClusters] For cluster $clusterID we only found one cluster after reclustering',
        );
      }
    }
    _logger.info(
      '[CheckMixedClusters] Inspection took ${DateTime.now().difference(inspectionStart).inSeconds} seconds',
    );
    if (susClusters.isNotEmpty) {
      _logger.info(
        '[CheckMixedClusters] Found ${susClusters.length} clusters that might be mixed: $susClusters',
      );
    } else {
      _logger.info('[CheckMixedClusters] No mixed clusters found');
    }
    return susClusters;
  }

  Future<ClusteringResult> breakUpCluster(
    String clusterID, {
    bool useDbscan = false,
  }) async {
    _logger.info(
      'breakUpCluster called for cluster $clusterID with dbscan $useDbscan',
    );
    final faceIDs = await mlDataDB.getFaceIDsForCluster(clusterID);
    final originalFaceIDsSet = faceIDs.toSet();

    final embeddings = await mlDataDB.getFaceEmbeddingMapForFaces(faceIDs);

    if (embeddings.isEmpty) {
      _logger.warning('No embeddings found for cluster $clusterID');
      return ClusteringResult.empty();
    }

    final fileIDToCreationTime = await FilesDB.instance
        .getFileIDToCreationTime();

    final clusterResult = await FaceClusteringService.instance
        .predictWithinClusterComputer(
          embeddings,
          fileIDToCreationTime: fileIDToCreationTime,
          distanceThreshold: 0.22,
        );

    if (clusterResult.isEmpty) {
      _logger.warning('No clusters found or something went wrong');
      return ClusteringResult.empty();
    }

    final clusterIdToCount = clusterResult.newClusterIdToFaceIds.map((
      key,
      value,
    ) {
      return MapEntry(key, value.length);
    });
    final amountOfNewClusters = clusterIdToCount.length;

    _logger.info(
      'Broke up cluster $clusterID into $amountOfNewClusters clusters \n ${clusterIdToCount.toString()}',
    );

    if (kDebugMode) {
      final Set allClusteredFaceIDsSet = {};
      for (final List<String> value
          in clusterResult.newClusterIdToFaceIds.values) {
        allClusteredFaceIDsSet.addAll(value);
      }
      assert((originalFaceIDsSet.difference(allClusteredFaceIDsSet)).isEmpty);
    }

    return clusterResult;
  }

  Future<void> _prepareClusterCentroidVectorDbForSuggestions() {
    _prepareClusterCentroidVectorDbFuture ??=
        _prepareClusterCentroidVectorDbForSuggestionsInternal();
    return _prepareClusterCentroidVectorDbFuture!;
  }

  Future<void> _prepareClusterCentroidVectorDbForSuggestionsInternal() async {
    try {
      if (!flagService.usearchForSuggestions) return;
      if (!flagService.hasGrantedMLConsent) return;
      if (!await _clusterCentroidVectorDB.checkIfMigrationDone()) {
        await _mlDataDBForCentroidVectorDb
            .checkMigrateFillClusterCentroidVectorDB();
      }
      if (await _clusterCentroidVectorDB.checkIfMigrationDone()) {
        await _clusterCentroidVectorDB.warmupApproxSearch();
      }
    } catch (e, s) {
      _logger.severe(
        "Failed to prepare cluster centroid vector DB for suggestions",
        e,
        s,
      );
    } finally {
      _prepareClusterCentroidVectorDbFuture = null;
    }
  }

  Future<bool> _canUseClusterCentroidVectorDbForSuggestions() async {
    if (!flagService.usearchForSuggestions) return false;
    if (!flagService.hasGrantedMLConsent) return false;
    if (await _clusterCentroidVectorDB.checkIfMigrationDone()) return true;
    unawaited(_prepareClusterCentroidVectorDbForSuggestions());
    return false;
  }

  /// Returns a list of suggestions. For each suggestion we return a record consisting of the following elements:
  /// 1. clusterID: the ID of the cluster
  /// 2. distance: the distance between the person's cluster and the suggestion
  /// 3. usedMean: whether the suggestion was found using the mean (true) or the median (false)
  Future<List<(String, double, bool)>> _getSuggestions(
    PersonEntity p, {
    int sampleSize = 50,
    double maxMedianDistance = 0.62,
    double goodMedianDistance = 0.55,
    double maxMeanDistance = 0.65,
    double goodMeanDistance = 0.45,
  }) async {
    final w = (kDebugMode ? EnteWatch('getSuggestions') : null)?..start();
    // Get all the cluster data
    final allClusterIdsToCountMap = await mlDataDB.clusterIdToFaceCount();
    final ignoredClusters = await mlDataDB.getPersonIgnoredClusters(p.remoteID);
    final personClusters = await mlDataDB.getPersonClusterIDs(p.remoteID);
    if (personClusters.isEmpty) {
      return [];
    }
    final personFaceIDs = await mlDataDB.getFaceIDsForPerson(p.remoteID);
    final personFileIDs = personFaceIDs.map(getFileIdFromFaceId<int>).toSet();
    w?.log(
      '${p.data.name} has ${personClusters.length} existing clusters, getting all database data done',
    );
    final allClusterIdToFaceIDs = await mlDataDB.getAllClusterIdToFaceIDs();
    w?.log('getAllClusterIdToFaceIDs done');

    // First only do a simple check on the big clusters, if the person does not have small clusters yet
    final smallestPersonClusterSize = personClusters
        .map((clusterID) => allClusterIdsToCountMap[clusterID] ?? 0)
        .reduce((value, element) => min(value, element));
    final checkSizes = [20, kMinimumClusterSizeSearchResult, 10, 5, 1];
    Map<String, Vector> clusterAvgBigClusters = <String, Vector>{};
    final List<(String, double)> suggestionsMean = [];
    bool canUseVectorDb = await _canUseClusterCentroidVectorDbForSuggestions();
    for (final minimumSize in checkSizes.toSet()) {
      if (smallestPersonClusterSize >=
          min(minimumSize, kMinimumClusterSizeSearchResult)) {
        clusterAvgBigClusters = await _getUpdateClusterAvg(
          allClusterIdsToCountMap,
          ignoredClusters,
          minClusterSize: minimumSize,
        );
        w?.log(
          'Calculate avg for ${clusterAvgBigClusters.length} clusters of min size $minimumSize',
        );
        final suggestionsMeanBigClusters =
            await _calcSuggestionsMeanWithFallback(
              clusterAvgBigClusters,
              personClusters,
              ignoredClusters,
              goodMeanDistance,
              canUseVectorDb: canUseVectorDb,
              perClusterResultCount: 8,
              onVectorDbFailed: () => canUseVectorDb = false,
            );
        w?.log(
          'Calculate suggestions using mean for ${clusterAvgBigClusters.length} clusters of min size $minimumSize',
        );
        for (final suggestion in suggestionsMeanBigClusters) {
          // Skip suggestions that have a high overlap with the person's files
          final suggestionSet = allClusterIdToFaceIDs[suggestion.$1]!
              .map((faceID) => getFileIdFromFaceId<int>(faceID))
              .toSet();
          final overlap = personFileIDs.intersection(suggestionSet);
          if (overlap.isNotEmpty &&
              ((overlap.length / suggestionSet.length) > 0.1)) {
            await mlDataDB.captureNotPersonFeedback(
              personID: p.remoteID,
              clusterID: suggestion.$1,
            );
            continue;
          }
          suggestionsMean.add((suggestion.$1, suggestion.$2));
        }
        if (suggestionsMean.isNotEmpty) {
          return suggestionsMean
              .map((e) => (e.$1, e.$2, true))
              .toList(growable: false);
        }
      }
    }
    w?.reset();

    // Find the other cluster candidates based on the median
    final clusterAvg = clusterAvgBigClusters;
    final moreSuggestionsMean = await _calcSuggestionsMeanWithFallback(
      clusterAvg,
      personClusters,
      ignoredClusters,
      maxMeanDistance,
      canUseVectorDb: canUseVectorDb,
      perClusterResultCount: 12,
      onVectorDbFailed: () => canUseVectorDb = false,
    );
    if (moreSuggestionsMean.isEmpty) {
      _logger.info(
        "No suggestions found using mean, even with higher threshold",
      );
      return [];
    }

    moreSuggestionsMean.sort((a, b) => a.$2.compareTo(b.$2));
    final otherClusterIdsCandidates = moreSuggestionsMean
        .map((e) => e.$1)
        .toList(growable: false);
    _logger.info(
      "Found potential suggestions from loose mean for median test: $otherClusterIdsCandidates",
    );

    w?.logAndReset("Starting median test");
    // Take the embeddings from the person's clusters in one big list and sample from it
    final List<Uint8List> personEmbeddingsProto = [];
    for (final clusterID in personClusters) {
      final Iterable<Uint8List> embeddings = await mlDataDB
          .getFaceEmbeddingsForCluster(clusterID);
      personEmbeddingsProto.addAll(embeddings);
    }
    final sampledEmbeddingsProto = _randomSampleWithoutReplacement(
      personEmbeddingsProto,
      sampleSize,
    );
    final List<Vector> sampledEmbeddings = sampledEmbeddingsProto
        .map(
          (embedding) => Vector.fromList(
            EVector.fromBuffer(embedding).values,
            dtype: DType.float32,
          ),
        )
        .toList(growable: false);

    // Find the actual closest clusters for the person using median
    final List<(String, double)> suggestionsMedian = [];
    final List<(String, double)> greatSuggestionsMedian = [];
    double minMedianDistance = maxMedianDistance;
    for (final otherClusterId in otherClusterIdsCandidates) {
      final Iterable<Uint8List> otherEmbeddingsProto = await mlDataDB
          .getFaceEmbeddingsForCluster(otherClusterId);
      final sampledOtherEmbeddingsProto = _randomSampleWithoutReplacement(
        otherEmbeddingsProto,
        sampleSize,
      );
      final List<Vector> sampledOtherEmbeddings = sampledOtherEmbeddingsProto
          .map(
            (embedding) => Vector.fromList(
              EVector.fromBuffer(embedding).values,
              dtype: DType.float32,
            ),
          )
          .toList(growable: false);

      // Calculate distances and find the median
      final List<double> distances = [];
      for (final otherEmbedding in sampledOtherEmbeddings) {
        for (final embedding in sampledEmbeddings) {
          distances.add(1 - embedding.dot(otherEmbedding));
        }
      }
      distances.sort();
      final double medianDistance = distances[distances.length ~/ 2];
      if (medianDistance < minMedianDistance) {
        suggestionsMedian.add((otherClusterId, medianDistance));
        minMedianDistance = medianDistance;
        if (medianDistance < goodMedianDistance) {
          greatSuggestionsMedian.add((otherClusterId, medianDistance));
          break;
        }
      }
    }
    w?.log("Finished median test");
    if (suggestionsMedian.isEmpty) {
      _logger.info("No suggestions found using median");
      return [];
    } else {
      _logger.info("Found suggestions using median: $suggestionsMedian");
    }

    final List<(String, double, bool)> finalSuggestionsMedian =
        suggestionsMedian
            .map(((e) => (e.$1, e.$2, false)))
            .toList(growable: false)
            .reversed
            .toList(growable: false);

    if (greatSuggestionsMedian.isNotEmpty) {
      _logger.info(
        "Found great suggestion using median: $greatSuggestionsMedian",
      );
      // // Return the largest size cluster by using allClusterIdsToCountMap
      // final List<int> greatSuggestionsMedianClusterIds =
      //     greatSuggestionsMedian.map((e) => e.$1).toList(growable: false);
      // greatSuggestionsMedianClusterIds.sort(
      //   (a, b) =>
      //       allClusterIdsToCountMap[b]!.compareTo(allClusterIdsToCountMap[a]!),
      // );

      // return [greatSuggestionsMedian.last.$1, ...finalSuggestionsMedian];
    }

    return finalSuggestionsMedian;
  }

  /// Returns a list of suggestions. For each suggestion we return a record consisting of the following elements:
  /// 1. clusterID: the ID of the cluster
  /// 2. distance: the distance between the person's cluster and the suggestion
  /// 3. personClusterID: the ID of the person's cluster
  Future<List<(String, double, String)>> _getFastSuggestions(
    PersonEntity person,
    String clusterID,
    double threshold, {
    Set<String>? extraIgnoredClusters,
  }) async {
    assert(
      !isLocalGalleryMode,
      "Fast person suggestions require an Ente account and should not run in local gallery mode.",
    );
    if (isLocalGalleryMode) {
      _logger.info(
        "Skipping _getFastSuggestions in local gallery mode because person suggestions require an Ente account",
      );
      return [];
    }
    final allClusterIdsToCountMap = (await mlDataDB.clusterIdToFaceCount());
    final personignoredClusters = await mlDataDB.getPersonIgnoredClusters(
      person.remoteID,
    );
    final ignoredClusters = personignoredClusters.union(
      extraIgnoredClusters ?? {},
    );
    final startTime = DateTime.now();
    final Map<String, Vector> clusterAvg = await _getUpdateClusterAvg(
      allClusterIdsToCountMap,
      ignoredClusters,
      minClusterSize: kMinimumClusterSizeSearchResult,
    );
    final avgCalcTime = DateTime.now();

    // Returns a list of tuples containing the suggestion ID, distance, and personClusterID, respectively
    final List<(String, double, String)> foundSuggestions =
        await calcSuggestionsMeanInComputer(
          clusterAvg,
          {clusterID},
          ignoredClusters,
          threshold,
        );
    final suggestionCalcTime = DateTime.now();
    _logger.info(
      "Calculated average vectors in ${avgCalcTime.difference(startTime).inMilliseconds}ms and suggestions in ${suggestionCalcTime.difference(avgCalcTime).inMilliseconds}ms",
    );
    return foundSuggestions;
  }

  Future<Map<String, Vector>> _getUpdateClusterAvg(
    Map<String, int> allClusterIdsToCountMap,
    Set<String> ignoredClusters, {
    int minClusterSize = 1,
    int maxClusterInCurrentRun = 500,
    int maxEmbeddingToRead = 10000,
  }) async {
    final w = (kDebugMode ? EnteWatch('_getUpdateClusterAvg') : null)?..start();
    final startTime = DateTime.now();
    final shouldPersistClusterSummaryUpdates =
        _prepareClusterCentroidVectorDbFuture == null;
    _logger.info(
      'start getUpdateClusterAvg for ${allClusterIdsToCountMap.length} clusters, minClusterSize $minClusterSize, maxClusterInCurrentRun $maxClusterInCurrentRun',
    );
    if (!shouldPersistClusterSummaryUpdates) {
      _logger.info(
        "Skipping cluster summary cache writes while centroid vector DB migration is in progress",
      );
    }

    final Map<String, (Uint8List, int)> clusterToSummary = await mlDataDB
        .getAllClusterSummary(minClusterSize);
    final Map<String, (Uint8List, int)> updatesForClusterSummary = {};

    w?.log('getUpdateClusterAvg database call for getAllClusterSummary');

    final serializationEmbeddings =
        await _computer.compute(
              checkAndSerializeCurrentClusterMeans,
              param: {
                'allClusterIdsToCountMap': allClusterIdsToCountMap,
                'minClusterSize': minClusterSize,
                'ignoredClusters': ignoredClusters,
                'clusterToSummary': clusterToSummary,
              },
            )
            as (Map<String, Vector>, Set<String>, int, int, int);
    final clusterAvg = serializationEmbeddings.$1;
    final allClusterIds = serializationEmbeddings.$2;
    final ignoredClustersCnt = serializationEmbeddings.$3;
    final alreadyUpdatedClustersCnt = serializationEmbeddings.$4;
    final smallerClustersCnt = serializationEmbeddings.$5;

    // Assert that all existing clusterAvg are normalized
    for (final avg in clusterAvg.values) {
      assert((avg.norm() - 1.0).abs() < 1e-5);
    }

    w?.log('serialization of embeddings');
    _logger.info(
      'Ignored $ignoredClustersCnt clusters, already updated $alreadyUpdatedClustersCnt clusters, $smallerClustersCnt clusters are smaller than $minClusterSize',
    );

    if (allClusterIds.isEmpty) {
      _logger.info(
        'No clusters to update, getUpdateClusterAvg done in ${DateTime.now().difference(startTime).inMilliseconds} ms',
      );
      return clusterAvg;
    }

    // get clusterIDs sorted by count in descending order
    final sortedClusterIDs = allClusterIds.toList();
    sortedClusterIDs.sort(
      (a, b) =>
          allClusterIdsToCountMap[b]!.compareTo(allClusterIdsToCountMap[a]!),
    );
    int indexedInCurrentRun = 0;
    w?.reset();

    int currentPendingRead = 0;
    final List<String> clusterIdsToRead = [];
    for (final clusterID in sortedClusterIDs) {
      if (maxClusterInCurrentRun-- <= 0) {
        break;
      }
      if (currentPendingRead == 0) {
        currentPendingRead = allClusterIdsToCountMap[clusterID] ?? 0;
        clusterIdsToRead.add(clusterID);
      } else {
        if ((currentPendingRead + allClusterIdsToCountMap[clusterID]!) <
            maxEmbeddingToRead) {
          clusterIdsToRead.add(clusterID);
          currentPendingRead += allClusterIdsToCountMap[clusterID]!;
        } else {
          break;
        }
      }
    }

    final Map<String, Iterable<Uint8List>> clusterEmbeddings = await mlDataDB
        .getFaceEmbeddingsForClusters(clusterIdsToRead);

    w?.logAndReset(
      'read  $currentPendingRead embeddings for ${clusterEmbeddings.length} clusters',
    );

    for (final clusterID in clusterEmbeddings.keys) {
      final Iterable<Uint8List> embeddings = clusterEmbeddings[clusterID]!;
      final Iterable<Vector> vectors = embeddings.map(
        (e) =>
            Vector.fromList(EVector.fromBuffer(e).values, dtype: DType.float32),
      );
      final avg = vectors.reduce((a, b) => a + b) / vectors.length;
      final avgNormalized = avg / avg.norm();
      if (shouldPersistClusterSummaryUpdates) {
        final avgEmbeddingBuffer = EVector(
          values: avgNormalized,
        ).writeToBuffer();
        updatesForClusterSummary[clusterID] = (
          avgEmbeddingBuffer,
          embeddings.length,
        );
      }
      // store the intermediate updates
      indexedInCurrentRun++;
      if (shouldPersistClusterSummaryUpdates &&
          updatesForClusterSummary.length > 100) {
        await mlDataDB.clusterSummaryUpdate(updatesForClusterSummary);
        updatesForClusterSummary.clear();
        if (kDebugMode) {
          _logger.info(
            'getUpdateClusterAvg $indexedInCurrentRun clusters in current one',
          );
        }
      }
      clusterAvg[clusterID] = avgNormalized;
    }
    if (shouldPersistClusterSummaryUpdates &&
        updatesForClusterSummary.isNotEmpty) {
      await mlDataDB.clusterSummaryUpdate(updatesForClusterSummary);
    }
    w?.logAndReset('done computing avg ');
    _logger.info(
      'end getUpdateClusterAvg for ${clusterAvg.length} clusters, done in ${DateTime.now().difference(startTime).inMilliseconds} ms',
    );

    return clusterAvg;
  }

  Future<List<(String, double, String)>> _calcSuggestionsMeanWithFallback(
    Map<String, Vector> clusterAvg,
    Set<String> personClusters,
    Set<String> ignoredClusters,
    double maxClusterDistance, {
    required bool canUseVectorDb,
    int perClusterResultCount = 8,
    required VoidCallback onVectorDbFailed,
  }) async {
    if (canUseVectorDb) {
      try {
        return await _calcSuggestionsMeanWithVectorDb(
          clusterAvg,
          personClusters,
          ignoredClusters,
          maxClusterDistance,
          perClusterResultCount: perClusterResultCount,
        );
      } catch (e, s) {
        _logger.warning(
          "Cluster centroid vector DB mean suggestions failed, falling back to in-memory comparisons",
          e,
          s,
        );
        onVectorDbFailed();
      }
    }
    return calcSuggestionsMeanInComputer(
      clusterAvg,
      personClusters,
      ignoredClusters,
      maxClusterDistance,
    );
  }

  Future<List<(String, double, String)>> _calcSuggestionsMeanWithVectorDb(
    Map<String, Vector> clusterAvg,
    Set<String> personClusters,
    Set<String> ignoredClusters,
    double maxClusterDistance, {
    int perClusterResultCount = 8,
  }) async {
    if (clusterAvg.isEmpty) {
      return [];
    }
    if (perClusterResultCount <= 0) {
      return [];
    }

    final validPersonClusters = personClusters
        .where((clusterID) => clusterAvg.containsKey(clusterID))
        .toSet();
    if (validPersonClusters.isEmpty) {
      return [];
    }

    final otherClusters = clusterAvg.keys
        .toSet()
        .difference(validPersonClusters)
        .difference(ignoredClusters);
    if (otherClusters.isEmpty) {
      return [];
    }

    final relevantClusterIDs = <String>{}
      ..addAll(validPersonClusters)
      ..addAll(otherClusters);
    final clusterIDToVectorID = await _mlDataDBForCentroidVectorDb
        .getClusterCentroidVectorIdMap(
          relevantClusterIDs,
          createIfMissing: false,
        );
    if (clusterIDToVectorID.isEmpty) {
      return [];
    }

    final baseAllowedVectorIDs = otherClusters
        .map((clusterID) => clusterIDToVectorID[clusterID])
        .whereType<int>()
        .toSet();
    if (baseAllowedVectorIDs.isEmpty) {
      return [];
    }

    final vectorIDToClusterID = {
      for (final entry in clusterIDToVectorID.entries) entry.value: entry.key,
    };

    final orderedPersonClusterIDs = <String>[];
    final queryVectors = <List<double>>[];
    for (final personClusterID in validPersonClusters) {
      final queryVector = clusterAvg[personClusterID];
      if (queryVector == null) {
        continue;
      }
      orderedPersonClusterIDs.add(personClusterID);
      queryVectors.add(queryVector.toList(growable: false));
    }
    if (orderedPersonClusterIDs.isEmpty) {
      return [];
    }

    final matchesPerQuery = await _clusterCentroidVectorDB
        .bulkSearchApproxClosestCentroidsWithinDistance(
          queryVectors,
          baseAllowedVectorIDs,
          maxDistance: maxClusterDistance,
          count: perClusterResultCount,
        );

    final bestSuggestionPerCluster = <String, (double, String)>{};
    final alignedQueryLength = min(
      orderedPersonClusterIDs.length,
      matchesPerQuery.length,
    );
    for (var i = 0; i < alignedQueryLength; i++) {
      final personClusterID = orderedPersonClusterIDs[i];
      final matches = matchesPerQuery[i];

      for (final match in matches) {
        final suggestedClusterID = vectorIDToClusterID[match.$1];
        if (suggestedClusterID == null) {
          continue;
        }
        if (ignoredClusters.contains(suggestedClusterID) ||
            validPersonClusters.contains(suggestedClusterID)) {
          continue;
        }
        final previous = bestSuggestionPerCluster[suggestedClusterID];
        if (previous == null || match.$2 < previous.$1) {
          bestSuggestionPerCluster[suggestedClusterID] = (
            match.$2,
            personClusterID,
          );
        }
      }
    }

    final suggestions = <(String, double, String)>[];
    for (final entry in bestSuggestionPerCluster.entries) {
      suggestions.add((entry.key, entry.value.$1, entry.value.$2));
    }
    suggestions.sort((a, b) => a.$2.compareTo(b.$2));
    return suggestions.sublist(0, min(suggestions.length, 20));
  }

  Future<List<(String, double, String)>> calcSuggestionsMeanInComputer(
    Map<String, Vector> clusterAvg,
    Set<String> personClusters,
    Set<String> ignoredClusters,
    double maxClusterDistance, {
    Map<String, Set<String>>? personClusterToIgnoredClusters,
  }) async {
    return await _computer.compute(
      _calcSuggestionsMean,
      param: {
        'clusterAvg': clusterAvg,
        'personClusters': personClusters,
        'ignoredClusters': ignoredClusters,
        'maxClusterDistance': maxClusterDistance,
        'personClusterToIgnoredClusters': personClusterToIgnoredClusters,
      },
    );
  }

  List<S> _randomSampleWithoutReplacement<S>(
    Iterable<S> embeddings,
    int sampleSize,
  ) {
    final random = Random();

    if (sampleSize >= embeddings.length) {
      return embeddings.toList();
    }

    // If sampleSize is more than half the list size, shuffle and take first sampleSize elements
    if (sampleSize > embeddings.length / 2) {
      final List<S> shuffled = List<S>.from(embeddings)..shuffle(random);
      return shuffled.take(sampleSize).toList(growable: false);
    }

    // Otherwise, use the set-based method for efficiency
    final selectedIndices = <int>{};
    final sampledEmbeddings = <S>[];
    while (sampledEmbeddings.length < sampleSize) {
      final int index = random.nextInt(embeddings.length);
      if (!selectedIndices.contains(index)) {
        selectedIndices.add(index);
        sampledEmbeddings.add(embeddings.elementAt(index));
      }
    }

    return sampledEmbeddings;
  }

  Future<void> _sortSuggestionsOnDistanceToPerson(
    PersonEntity? person,
    List<ClusterSuggestion> suggestions, {
    bool onlySortBigSuggestions = true,
  }) async {
    if (suggestions.isEmpty) {
      debugPrint('No suggestions to sort');
      return;
    }
    if (onlySortBigSuggestions) {
      final bigSuggestions = suggestions
          .where(
            (s) => s.filesInCluster.length > kMinimumClusterSizeSearchResult,
          )
          .toList();
      if (bigSuggestions.isEmpty) {
        debugPrint('No big suggestions to sort');
        return;
      }
    }
    final startTime = DateTime.now();
    final w = (kDebugMode ? EnteWatch('sortSuggestions') : null)?..start();

    final Map<String, Vector> personAverages = {};
    if (person != null) {
      final avg = await _getPersonAvg(person.remoteID);
      w?.log('getPersonAvg');
      if (avg != null) personAverages[person.remoteID] = avg;
    }

    // Sort the suggestions based on the distance to the person
    for (final suggestion in suggestions) {
      if (onlySortBigSuggestions) {
        if (suggestion.filesInCluster.length <= 8) {
          continue;
        }
      }
      // get person average
      Vector? personAvg = personAverages[suggestion.person.remoteID];
      if (personAvg == null) {
        personAvg = await _getPersonAvg(suggestion.person.remoteID);
        if (personAvg != null) {
          personAverages[suggestion.person.remoteID] = personAvg;
        } else {
          continue;
        }
      }

      final clusterID = suggestion.clusterIDToMerge;
      final faceIDs = suggestion.faceIDsInCluster;
      final faceIdToEmbeddingMap = await mlDataDB.getFaceEmbeddingMapForFaces(
        faceIDs,
      );
      final faceIdToVectorMap = faceIdToEmbeddingMap.map(
        (key, value) => MapEntry(
          key,
          Vector.fromList(
            EVector.fromBuffer(value).values,
            dtype: DType.float32,
          ),
        ),
      );
      w?.log(
        'got ${faceIdToEmbeddingMap.values.length} embeddings for ${suggestion.filesInCluster.length} files for cluster $clusterID',
      );
      final fileIdToDistanceMap = {};
      for (final entry in faceIdToVectorMap.entries) {
        fileIdToDistanceMap[getFileIdFromFaceId<int>(entry.key)] =
            1 - personAvg.dot(entry.value);
      }
      w?.log('calculated distances for cluster $clusterID');
      suggestion.filesInCluster.sort((b, a) {
        //todo: review with @laurens, added this to avoid null safety issue
        final double distanceA = fileIdToDistanceMap[a.uploadedFileID!] ?? -1;
        final double distanceB = fileIdToDistanceMap[b.uploadedFileID!] ?? -1;
        return distanceA.compareTo(distanceB);
      });
      w?.log('sorted files for cluster $clusterID');

      debugPrint(
        "[${_logger.name}] Sorted suggestions for cluster $clusterID based on distance to person: ${suggestion.filesInCluster.map((e) => fileIdToDistanceMap[e.uploadedFileID]).toList()}",
      );
    }

    final endTime = DateTime.now();
    _logger.fine(
      "Sorting suggestions based on distance to person took ${endTime.difference(startTime).inMilliseconds} ms for ${suggestions.length} suggestions",
    );
  }

  Future<Vector?> _getPersonAvg(String personID) async {
    final w = (kDebugMode ? EnteWatch('_getPersonAvg') : null)?..start();
    // Get the cluster averages for the person's clusters and the suggestions' clusters
    final personClusters = await mlDataDB.getPersonClusterIDs(personID);
    w?.log('got person clusters');
    final Map<String, (Uint8List, int)> personClusterToSummary = await mlDataDB
        .getClusterToClusterSummary(personClusters);
    w?.log('got cluster summaries');

    // remove personClusters that don't have any summary
    for (final clusterID in personClusters.toSet()) {
      if (!personClusterToSummary.containsKey(clusterID)) {
        _logger.warning('missing summary for $clusterID');
        personClusters.remove(clusterID);
      }
    }
    if (personClusters.isEmpty) {
      _logger.warning('No person clusters with summary found');
      return null;
    }

    // Calculate the avg embedding of the person
    int personEmbeddingsCount = 0;
    for (final clusterID in personClusters) {
      personEmbeddingsCount += personClusterToSummary[clusterID]!.$2;
    }

    Vector personAvg = Vector.filled(192, 0);
    for (final personClusterID in personClusters) {
      final personClusterBlob = personClusterToSummary[personClusterID]!.$1;
      final personClusterAvg = Vector.fromList(
        EVector.fromBuffer(personClusterBlob).values,
        dtype: DType.float32,
      );
      final clusterWeight =
          personClusterToSummary[personClusterID]!.$2 / personEmbeddingsCount;
      personAvg += personClusterAvg * clusterWeight;
    }
    w?.log('calculated person avg');
    return personAvg;
  }

  Future<void> debugLogClusterBlurValues(
    String clusterID, {
    int? clusterSize,
    bool logClusterSummary = false,
    bool logBlurValues = false,
  }) async {
    if (!kDebugMode) return;

    // Logging the clusterID
    _logger.info(
      "Debug logging for cluster $clusterID${clusterSize != null ? ' with $clusterSize photos' : ''}",
    );
    // todo:(laurens) remove to review
    const String biggestClusterID = 'some random id';

    // Logging the cluster summary for the cluster
    if (logClusterSummary) {
      final summaryMap = await mlDataDB.getClusterToClusterSummary([
        clusterID,
        biggestClusterID,
      ]);
      final summary = summaryMap[clusterID];
      if (summary != null) {
        _logger.info(
          "Cluster summary for cluster $clusterID says the amount of faces is: ${summary.$2}",
        );
      }

      final biggestClusterSummary = summaryMap[biggestClusterID];
      final clusterSummary = summaryMap[clusterID];
      if (biggestClusterSummary != null && clusterSummary != null) {
        _logger.info(
          "Cluster summary for biggest cluster $biggestClusterID says the size is: ${biggestClusterSummary.$2}",
        );
        _logger.info(
          "Cluster summary for current cluster $clusterID says the size is: ${clusterSummary.$2}",
        );

        // Mean distance
        final biggestMean = Vector.fromList(
          EVector.fromBuffer(biggestClusterSummary.$1).values,
          dtype: DType.float32,
        );
        final currentMean = Vector.fromList(
          EVector.fromBuffer(clusterSummary.$1).values,
          dtype: DType.float32,
        );
        final bigClustersMeanDistance = 1 - biggestMean.dot(currentMean);
        _logger.info(
          "Mean distance between biggest cluster and current cluster: $bigClustersMeanDistance",
        );
        _logger.info(
          'Element differences between the two means are ${biggestMean - currentMean}',
        );
        final currentL2Norm = currentMean.norm();
        _logger.info('L2 norm of current mean: $currentL2Norm');
        final trueDistance = biggestMean.distanceTo(
          currentMean,
          distance: Distance.cosine,
        );
        _logger.info('True distance between the two means: $trueDistance');

        // Median distance
        const sampleSize = 100;
        final Iterable<Uint8List> biggestEmbeddings = await mlDataDB
            .getFaceEmbeddingsForCluster(biggestClusterID);
        final List<Uint8List> biggestSampledEmbeddingsProto =
            _randomSampleWithoutReplacement(biggestEmbeddings, sampleSize);
        final List<Vector> biggestSampledEmbeddings =
            biggestSampledEmbeddingsProto
                .map(
                  (embedding) => Vector.fromList(
                    EVector.fromBuffer(embedding).values,
                    dtype: DType.float32,
                  ),
                )
                .toList(growable: false);

        final Iterable<Uint8List> currentEmbeddings = await mlDataDB
            .getFaceEmbeddingsForCluster(clusterID);
        final List<Uint8List> currentSampledEmbeddingsProto =
            _randomSampleWithoutReplacement(currentEmbeddings, sampleSize);
        final List<Vector> currentSampledEmbeddings =
            currentSampledEmbeddingsProto
                .map(
                  (embedding) => Vector.fromList(
                    EVector.fromBuffer(embedding).values,
                    dtype: DType.float32,
                  ),
                )
                .toList(growable: false);

        // Calculate distances and find the median
        final List<double> distances = [];
        final List<double> trueDistances = [];
        for (final biggestEmbedding in biggestSampledEmbeddings) {
          for (final currentEmbedding in currentSampledEmbeddings) {
            distances.add(1 - biggestEmbedding.dot(currentEmbedding));
            trueDistances.add(
              biggestEmbedding.distanceTo(
                currentEmbedding,
                distance: Distance.cosine,
              ),
            );
          }
        }
        distances.sort();
        trueDistances.sort();
        final double medianDistance = distances[distances.length ~/ 2];
        final double trueMedianDistance =
            trueDistances[trueDistances.length ~/ 2];
        _logger.info(
          "Median distance between biggest cluster and current cluster: $medianDistance (using sample of $sampleSize)",
        );
        _logger.info(
          'True distance median between the two embeddings: $trueMedianDistance',
        );
      }
    }

    // Logging the blur values for the cluster
    if (logBlurValues) {
      final List<double> blurValues = await mlDataDB
          .getBlurValuesForCluster(clusterID)
          .then((value) => value.toList());
      final blurValuesIntegers = blurValues
          .map((value) => value.round())
          .toList();
      blurValuesIntegers.sort();
      _logger.info(
        "Blur values for cluster $clusterID${clusterSize != null ? ' with $clusterSize photos' : ''}: $blurValuesIntegers",
      );
    }

    return;
  }
}

/// Returns a list of suggestions for a cluster in a tuple. The values of the tuple are:
/// 1. The suggested cluster ID
/// 2. The distance between the two clusters
/// 3. The corresponding cluster ID of the person cluster
List<(String, double, String)> _calcSuggestionsMean(Map<String, dynamic> args) {
  // Fill in args
  final Map<String, Vector> clusterAvg = args['clusterAvg'];
  final Set<String> personClusters = args['personClusters'];
  final Set<String> ignoredClusters = args['ignoredClusters'];
  final double maxClusterDistance = args['maxClusterDistance'];
  final Map<String, Set<String>>? personClusterToIgnoredClusters =
      args['personClusterToIgnoredClusters'];
  final bool extraIgnoreCheck = personClusterToIgnoredClusters != null;

  final Map<String, List<(String, double)>> suggestions = {};
  const suggestionMax = 2000;
  int suggestionCount = 0;
  int comparisons = 0;
  final w = (kDebugMode ? EnteWatch('getSuggestions') : null)?..start();

  // ignore the clusters that belong to the person or is ignored
  Set<String> otherClusters = clusterAvg.keys.toSet().difference(
    personClusters,
  );
  otherClusters = otherClusters.difference(ignoredClusters);

  for (final otherClusterID in otherClusters) {
    final Vector? otherAvg = clusterAvg[otherClusterID];
    if (otherAvg == null) {
      dev.log('[WARNING] no avg for othercluster $otherClusterID');
      continue;
    }
    String? nearestPersonCluster;
    double? minDistance;
    for (final personCluster in personClusters) {
      if (clusterAvg[personCluster] == null) {
        dev.log('[WARNING] no avg for personcluster $personCluster');
        continue;
      }
      if (extraIgnoreCheck &&
          personClusterToIgnoredClusters[personCluster] != null &&
          personClusterToIgnoredClusters[personCluster]!.contains(
            otherClusterID,
          )) {
        continue;
      }
      final Vector avg = clusterAvg[personCluster]!;
      final distance = 1 - avg.dot(otherAvg);
      comparisons++;
      if (distance < maxClusterDistance) {
        if (minDistance == null || distance < minDistance) {
          minDistance = distance;
          nearestPersonCluster = personCluster;
        }
      }
    }
    if (nearestPersonCluster != null && minDistance != null) {
      suggestions.putIfAbsent(nearestPersonCluster, () => []).add((
        otherClusterID,
        minDistance,
      ));
      suggestionCount++;
    }
    if (suggestionCount >= suggestionMax) {
      break;
    }
  }
  w?.log(
    'calculation inside calcSuggestionsMean for ${personClusters.length} person clusters and ${otherClusters.length} other clusters (so ${personClusters.length * otherClusters.length} combinations, $comparisons comparisons made resulted in $suggestionCount suggestions)',
  );

  if (suggestions.isNotEmpty) {
    final List<(String, double, String)> suggestClusterIds = [];
    for (final String personClusterID in suggestions.keys) {
      final suggestionss = suggestions[personClusterID]!;
      suggestClusterIds.addAll(
        suggestionss.map(
          (suggestion) => (suggestion.$1, suggestion.$2, personClusterID),
        ),
      );
    }
    suggestClusterIds.sort((a, b) => a.$2.compareTo(b.$2)); // sort by distance

    dev.log(
      "Already found ${suggestClusterIds.length} good suggestions using mean",
    );
    return suggestClusterIds.sublist(0, min(suggestClusterIds.length, 20));
  } else {
    dev.log("No suggestions found using mean");
    return <(String, double, String)>[];
  }
}

Future<(Map<String, Vector>, Set<String>, int, int, int)>
checkAndSerializeCurrentClusterMeans(Map args) async {
  final Map<String, int> allClusterIdsToCountMap =
      args['allClusterIdsToCountMap'];
  final int minClusterSize = args['minClusterSize'] ?? 1;
  final Set<String> ignoredClusters = args['ignoredClusters'] ?? {};
  final Map<String, (Uint8List, int)> clusterToSummary =
      args['clusterToSummary'];

  final Map<String, Vector> clusterAvg = {};

  final allClusterIds = allClusterIdsToCountMap.keys.toSet();
  int ignoredClustersCnt = 0, alreadyUpdatedClustersCnt = 0;
  int smallerClustersCnt = 0;
  for (final id in allClusterIdsToCountMap.keys) {
    if (ignoredClusters.contains(id)) {
      allClusterIds.remove(id);
      ignoredClustersCnt++;
    }
    if (clusterToSummary[id]?.$2 == allClusterIdsToCountMap[id]) {
      allClusterIds.remove(id);
      clusterAvg[id] = Vector.fromList(
        EVector.fromBuffer(clusterToSummary[id]!.$1).values,
        dtype: DType.float32,
      );
      alreadyUpdatedClustersCnt++;
    }
    if (allClusterIdsToCountMap[id]! < minClusterSize) {
      allClusterIds.remove(id);
      smallerClustersCnt++;
    }
  }

  return (
    clusterAvg,
    allClusterIds,
    ignoredClustersCnt,
    alreadyUpdatedClustersCnt,
    smallerClustersCnt,
  );
}
