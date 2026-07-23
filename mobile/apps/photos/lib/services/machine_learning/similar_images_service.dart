import "dart:io" show File;
import "dart:math" show max;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart"
    show Uint64List;
import 'package:logging/logging.dart';
import "package:path_provider/path_provider.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/similar_files.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/machine_learning/ml_computer.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/search_service.dart";
import "package:photos/utils/cache_util.dart";

class SimilarImagesService {
  static const double _groupedClipEmbeddingLossRefreshRatio = 0.05;

  final _logger = Logger("SimilarImagesService");

  SimilarImagesService._privateConstructor();
  static final SimilarImagesService instance =
      SimilarImagesService._privateConstructor();

  /// Returns a list of SimilarFiles, where each SimilarFiles object contains
  /// a list of files that are perceptually similar
  Future<List<SimilarFiles>> getSimilarFiles(
    double distanceThreshold, {
    bool exact = false,
    bool forceRefresh = false,
  }) async {
    try {
      final now = DateTime.now();
      final List<SimilarFiles> result = await _getSimilarFiles(
        distanceThreshold,
        exact,
        forceRefresh,
      );
      final duration = DateTime.now().difference(now);
      _logger.info(
        "Found ${result.length} similar files in ${duration.inSeconds} seconds for threshold $distanceThreshold and exact $exact",
      );
      return result;
    } catch (e, s) {
      _logger.severe("failed to get similar files", e, s);
      rethrow;
    }
  }

  Future<List<SimilarFiles>> _getSimilarFiles(
    double distanceThreshold,
    bool exact,
    bool forceRefresh,
  ) async {
    final w = (kDebugMode ? EnteWatch('getSimilarFiles') : null)?..start();
    final mlDataDB = MLDataDB.instance;
    _logger.info("Checking migration and filling clip vector DB");
    await mlDataDB.checkMigrateFillClipVectorDB();
    w?.log("checkMigrateFillClipVectorDB");

    // Get all files with CLIP embeddings first to avoid caching unindexed files
    final Map<int, int> clipIndexedFiles = await mlDataDB
        .clipIndexedFileWithVersion();
    final Set<int> clipIndexedFileIDs = clipIndexedFiles.keys.toSet();
    w?.log("getClipIndexedFiles");

    // Get all files, and all potential embedding IDs, and create a map of fileID to file
    final allFiles = Set<EnteFile>.from(
      await SearchService.instance.getAllFilesForSearch(),
    );
    final allFileIdsToFile = <int, EnteFile>{};
    final fileIDs = <int>[];
    for (final file in allFiles) {
      if (file.uploadedFileID != null &&
          file.isOwner &&
          !file.isVideo &&
          clipIndexedFileIDs.contains(file.uploadedFileID!)) {
        allFileIdsToFile[file.uploadedFileID!] = file;
        fileIDs.add(file.uploadedFileID!);
      }
    }
    final Uint64List potentialKeys = Uint64List.fromList(fileIDs);
    w?.log("getAllFilesForSearch");

    // Get mapping of fileIDs to corresponding personIDs
    final fileIDToPersonIDs = <int, Set<String>>{};
    final dbPersonClusterInfo = await mlDataDB.getPersonToClusterIdToFaceIds();
    for (final personID in dbPersonClusterInfo.keys) {
      final clusterInfo = dbPersonClusterInfo[personID]!;
      for (final faceIDs in clusterInfo.values) {
        for (final faceID in faceIDs) {
          final fileID = getFileIdFromFaceId<int>(faceID);
          if (allFileIdsToFile.containsKey(fileID)) {
            fileIDToPersonIDs
                .putIfAbsent(fileID, () => <String>{})
                .add(personID);
          }
        }
      }
    }
    w?.log("getFileIDToPersonIDs");

    if (forceRefresh) {
      final result = await _performFullSearch(
        potentialKeys,
        allFileIdsToFile,
        fileIDToPersonIDs,
        distanceThreshold,
        exact,
      );
      await _cacheSimilarFiles(
        result,
        fileIDs.toSet(),
        distanceThreshold,
        exact,
        DateTime.now().millisecondsSinceEpoch,
      );
      return result;
    }

    // Load cached data
    final SimilarFilesCache? cachedData = await _readCachedSimilarFiles();
    if (cachedData == null) {
      _logger.warning("No cached similar files found");
    } else {
      _logger.info(
        "Cached similar files found with ${cachedData.similarFilesJsonStringList.length} groups",
      );
    }

    // Determine if we need full refresh
    bool needsFullRefresh = false;
    if (cachedData != null) {
      final Set<int> cachedFileIDs = cachedData.allCheckedFileIDs;
      final currentFileIDs = fileIDs.toSet();

      if (cachedData.distanceThreshold != distanceThreshold ||
          cachedData.exact != exact) {
        needsFullRefresh = true;
      }

      // Check condition: less than 1000 files
      if (currentFileIDs.length < 1000) {
        needsFullRefresh = true;
      }

      // Check condition: cache is older than a month
      if (DateTime.fromMillisecondsSinceEpoch(
        cachedData.cachedTime,
      ).isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
        needsFullRefresh = true;
      }

      // Check condition: new files > 20% of total files
      if (!needsFullRefresh) {
        final newFileIDs = currentFileIDs.difference(cachedFileIDs);
        if (newFileIDs.length > currentFileIDs.length * 0.2) {
          needsFullRefresh = true;
        }
      }

      // Check condition: 20+% of grouped files deleted
      if (!needsFullRefresh) {
        final Set<int> cacheGroupedFileIDs = await cachedData
            .getGroupedFileIDs();
        final deletedFromGroups = cacheGroupedFileIDs.intersection(
          cachedFileIDs.difference(currentFileIDs),
        );
        final totalInGroups = cacheGroupedFileIDs.length;
        if (totalInGroups > 0 &&
            deletedFromGroups.length > totalInGroups * 0.2) {
          needsFullRefresh = true;
        }

        if (!needsFullRefresh && totalInGroups > 0) {
          final groupedFilesWithoutClipEmbeddings = cacheGroupedFileIDs
              .difference(clipIndexedFileIDs);
          if (groupedFilesWithoutClipEmbeddings.length >
              totalInGroups * _groupedClipEmbeddingLossRefreshRatio) {
            _logger.info(
              "Refreshing similar images cache because ${groupedFilesWithoutClipEmbeddings.length} of $totalInGroups grouped files no longer have CLIP embeddings",
            );
            needsFullRefresh = true;
          }
        }
      }
    }

    if (cachedData == null || needsFullRefresh) {
      final result = await _performFullSearch(
        potentialKeys,
        allFileIdsToFile,
        fileIDToPersonIDs,
        distanceThreshold,
        exact,
      );
      await _cacheSimilarFiles(
        result,
        fileIDs.toSet(),
        distanceThreshold,
        exact,
        DateTime.now().millisecondsSinceEpoch,
      );
      return result;
    } else {
      return await _performIncrementalUpdate(
        cachedData,
        potentialKeys,
        allFileIdsToFile,
        fileIDToPersonIDs,
        distanceThreshold,
        exact,
      );
    }
  }

  Future<List<SimilarFiles>> _performIncrementalUpdate(
    SimilarFilesCache cachedData,
    Uint64List currentFileIDs,
    Map<int, EnteFile> allFileIdsToFile,
    Map<int, Set<String>> fileIDToPersonIDs,
    double distanceThreshold,
    bool exact,
  ) async {
    _logger.info("Performing incremental update for similar files");
    final existingGroups = await cachedData.similarFilesList();
    final cachedFileIDs = cachedData.allCheckedFileIDs;
    final currentFileIDsSet = currentFileIDs.map((id) => id.toInt()).toSet();
    final deletedFiles = cachedFileIDs.difference(currentFileIDsSet);

    // Clean up deleted files from existing groups
    if (deletedFiles.isNotEmpty) {
      for (final group in existingGroups) {
        final filesInGroupToDelete = [];
        for (final fileInGroup in group.files) {
          if (deletedFiles.contains(fileInGroup.uploadedFileID ?? -1)) {
            filesInGroupToDelete.add(fileInGroup);
          }
        }
        for (final fileToDelete in filesInGroupToDelete) {
          group.removeFile(fileToDelete);
        }
      }
    }
    // Remove empty groups
    existingGroups.removeWhere((group) => group.length <= 1);

    // Identify new files
    final newFileIDs = currentFileIDsSet.difference(cachedFileIDs);
    if (newFileIDs.isEmpty) {
      if (deletedFiles.isNotEmpty) {
        await _cacheSimilarFiles(
          existingGroups,
          currentFileIDsSet,
          distanceThreshold,
          exact,
          cachedData.cachedTime,
        );
      }
      return existingGroups;
    }

    // Search only new files
    final newFileIDsList = Uint64List.fromList(newFileIDs.toList());
    final (keys, vectorKeys, distances) = await MLComputer.instance
        .bulkVectorSearchWithKeys(newFileIDsList, exact);
    final keysList = keys.map((key) => key.toInt()).toList();

    // Try to assign new files to existing groups
    final unassignedNewFilesIndices = <int>{};
    final unassignedNewFileIDs = <int>{};
    for (int i = 0; i < keysList.length; i++) {
      final newFileID = keysList[i];
      final newFile = allFileIdsToFile[newFileID];
      if (newFile == null) continue;
      final similarFileIDs = vectorKeys[i];
      final fileDistances = distances[i];
      final newFilePersonIDs = fileIDToPersonIDs[newFileID] ?? <String>{};
      bool assigned = false;
      for (int j = 0; j < similarFileIDs.length; j++) {
        final otherFileID = similarFileIDs[j].toInt();
        if (otherFileID == newFileID) continue;
        final distance = fileDistances[j];
        if (distance > distanceThreshold) break;
        for (final group in existingGroups) {
          if (group.fileIds.contains(otherFileID)) {
            final otherPersonIDs = fileIDToPersonIDs[otherFileID] ?? <String>{};
            if (setsAreEqual(newFilePersonIDs, otherPersonIDs)) {
              group.addFile(newFile);
              group.furthestDistance = max(group.furthestDistance, distance);
              group.files.sort((a, b) {
                if (FavoritesService.instance.isFavoriteCache(a)) {
                  return -1;
                } else if (FavoritesService.instance.isFavoriteCache(b)) {
                  return 1;
                }
                final sizeComparison = (b.fileSize ?? 0).compareTo(
                  a.fileSize ?? 0,
                );
                if (sizeComparison != 0) return sizeComparison;
                return a.displayName.compareTo(b.displayName);
              });
              assigned = true;
              break;
            }
          }
        }
        if (assigned) break;
      }
      if (!assigned) {
        unassignedNewFilesIndices.add(i);
        unassignedNewFileIDs.add(newFileID);
      }
    }

    // Check if unassigned new files form groups among themselves
    if (unassignedNewFilesIndices.isNotEmpty) {
      final alreadyUsedNewFiles = <int>{};
      for (final searchIndex in unassignedNewFilesIndices) {
        final newFileID = keysList[searchIndex];
        if (alreadyUsedNewFiles.contains(newFileID)) continue;
        final newFile = allFileIdsToFile[newFileID];
        if (newFile == null) continue;
        final similarFileIDs = vectorKeys[searchIndex];
        final fileDistances = distances[searchIndex];
        final newFilePersonIDs = fileIDToPersonIDs[newFileID] ?? <String>{};
        final similarNewFiles = <EnteFile>[];
        double furthestDistance = 0.0;
        for (int j = 0; j < similarFileIDs.length; j++) {
          final otherFileID = similarFileIDs[j].toInt();
          if (otherFileID == newFileID) continue;
          if (!unassignedNewFileIDs.contains(otherFileID)) continue;
          if (alreadyUsedNewFiles.contains(otherFileID)) continue;
          final distance = fileDistances[j];
          if (distance > distanceThreshold) break;
          final otherFile = allFileIdsToFile[otherFileID];
          if (otherFile == null) continue;
          final otherPersonIDs = fileIDToPersonIDs[otherFileID] ?? <String>{};
          if (!setsAreEqual(newFilePersonIDs, otherPersonIDs)) continue;
          similarNewFiles.add(otherFile);
          alreadyUsedNewFiles.add(otherFileID);
          furthestDistance = max(furthestDistance, distance);
        }
        if (similarNewFiles.isNotEmpty) {
          similarNewFiles.add(newFile);
          alreadyUsedNewFiles.add(newFileID);
          similarNewFiles.sort((a, b) {
            if (FavoritesService.instance.isFavoriteCache(a)) {
              return -1;
            } else if (FavoritesService.instance.isFavoriteCache(b)) {
              return 1;
            }
            final sizeComparison = (b.fileSize ?? 0).compareTo(a.fileSize ?? 0);
            if (sizeComparison != 0) return sizeComparison;
            return a.displayName.compareTo(b.displayName);
          });
          existingGroups.add(SimilarFiles(similarNewFiles, furthestDistance));
        }
      }
    }
    await _cacheSimilarFiles(
      existingGroups,
      currentFileIDsSet,
      distanceThreshold,
      exact,
      cachedData.cachedTime,
    );

    return existingGroups;
  }

  Future<List<SimilarFiles>> _performFullSearch(
    Uint64List potentialKeys,
    Map<int, EnteFile> allFileIdsToFile,
    Map<int, Set<String>> fileIDToPersonIDs,
    double distanceThreshold,
    bool exact,
  ) async {
    _logger.info("Performing full search for similar files");
    final w = (kDebugMode ? EnteWatch('getSimilarFiles') : null)?..start();
    // Run bulk vector search
    final (keys, vectorKeys, distances) = await MLComputer.instance
        .bulkVectorSearchWithKeys(potentialKeys, exact);
    w?.log("bulkSearchVectors");

    // Run through the vector search results and create SimilarFiles objects
    final alreadyUsedFileIDs = <int>{};
    final allSimilarFiles = <SimilarFiles>[];
    for (int i = 0; i < keys.length; i++) {
      final fileID = keys[i].toInt();
      if (alreadyUsedFileIDs.contains(fileID)) continue;
      final firstLoopFile = allFileIdsToFile[fileID];
      if (firstLoopFile == null || firstLoopFile.uploadedFileID == null) {
        continue;
      }
      final otherFileIDs = vectorKeys[i];
      final distancesToFiles = distances[i];
      final similarFilesList = <EnteFile>[];
      final personIDs = fileIDToPersonIDs[fileID] ?? <String>{};
      double furthestDistance = 0.0;
      for (int j = 0; j < otherFileIDs.length; j++) {
        final otherFileID = otherFileIDs[j].toInt();
        if (otherFileID == fileID) continue;
        if (alreadyUsedFileIDs.contains(otherFileID)) continue;
        final distance = distancesToFiles[j];
        if (distance > distanceThreshold) break;
        final otherFile = allFileIdsToFile[otherFileID];
        if (otherFile == null || otherFile.uploadedFileID == null) {
          continue;
        }
        final otherPersonIDs = fileIDToPersonIDs[otherFileID] ?? <String>{};
        if (!setsAreEqual(personIDs, otherPersonIDs)) continue;
        similarFilesList.add(otherFile);
        furthestDistance = max(furthestDistance, distance);
        alreadyUsedFileIDs.add(otherFileID);
      }
      if (similarFilesList.isNotEmpty) {
        similarFilesList.add(firstLoopFile);
        for (final file in similarFilesList) {
          alreadyUsedFileIDs.add(file.uploadedFileID!);
        }
        // show highest quality files first
        similarFilesList.sort((a, b) {
          if (FavoritesService.instance.isFavoriteCache(a)) {
            return -1;
          } else if (FavoritesService.instance.isFavoriteCache(b)) {
            return 1;
          }
          final sizeComparison = (b.fileSize ?? 0).compareTo(a.fileSize ?? 0);
          if (sizeComparison != 0) return sizeComparison;
          return a.displayName.compareTo(b.displayName);
        });
        final similarFiles = SimilarFiles(similarFilesList, furthestDistance);
        allSimilarFiles.add(similarFiles);
      }
    }
    w?.log("going through files");

    return allSimilarFiles;
  }

  Future<String> _getCachePath() async {
    return (await getApplicationSupportDirectory()).path +
        "/cache/similar_images_cache";
  }

  Future<void> _cacheSimilarFiles(
    List<SimilarFiles> similarGroups,
    Set<int> allCheckedFileIDs,
    double distanceThreshold,
    bool exact,
    int cachedTimeOfOriginalComputation,
  ) async {
    final cachePath = await _getCachePath();
    final similarGroupsJsonStringList = similarGroups
        .map((group) => group.toJsonString())
        .toList();
    final cacheObject = SimilarFilesCache(
      similarFilesJsonStringList: similarGroupsJsonStringList,
      allCheckedFileIDs: allCheckedFileIDs,
      distanceThreshold: distanceThreshold,
      exact: exact,
      cachedTime: cachedTimeOfOriginalComputation,
    );
    await writeToJsonFile<SimilarFilesCache>(
      cachePath,
      cacheObject,
      SimilarFilesCache.encodeToJsonString,
    );
  }

  Future<SimilarFilesCache?> _readCachedSimilarFiles() async {
    _logger.info("Reading similar files cache result from disk");
    final cache = decodeJsonFile<SimilarFilesCache>(
      await _getCachePath(),
      SimilarFilesCache.decodeFromJsonString,
    );
    return cache;
  }

  Future<void> clearCache() async {
    try {
      final cachePath = await _getCachePath();
      final file = File(cachePath);
      if (await file.exists()) {
        await file.delete();
        _logger.info("Cleared similar files cache at $cachePath");
      }
    } catch (e, s) {
      _logger.severe("Error clearing similar files cache", e, s);
      rethrow;
    }
  }
}

bool setsAreEqual(Set<String> set1, Set<String> set2) {
  return set1.length == set2.length && set1.containsAll(set2);
}
