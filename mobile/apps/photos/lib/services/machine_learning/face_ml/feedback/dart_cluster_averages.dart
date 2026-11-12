import 'dart:developer' as dev show log;
import "dart:math" show min;

import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:ml_linalg/linalg.dart";
import "package:photos/db/ml/dart_db.dart";
import "package:photos/db/ml/usearch_cluster_centroid_vector_db.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_averages.dart";

class DartClusterAverages implements ClusterAverages {
  static final Logger _logger = Logger("DartClusterAverages");
  static final _computer = Computer.shared();

  final Map<String, Vector> _clusterAvg;

  DartClusterAverages._(this._clusterAvg);

  @override
  late final Set<String> clusterIDs = _clusterAvg.keys.toSet();

  static Future<DartClusterAverages> refresh(
    Map<String, int> allClusterIdsToCountMap,
    Set<String> ignoredClusters, {
    required bool shouldPersistClusterSummaryUpdates,
    int minClusterSize = 1,
    int maxClusterInCurrentRun = 500,
    int maxEmbeddingToRead = 10000,
  }) async {
    final mlDataDB = DartMLDataDB.instance;
    final w = (kDebugMode ? EnteWatch('_getUpdateClusterAvg') : null)?..start();
    final startTime = DateTime.now();
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
      return DartClusterAverages._(clusterAvg);
    }

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

    return DartClusterAverages._(clusterAvg);
  }

  @override
  Future<List<List<(String, double)>>> searchNearest(
    List<String> queryClusterIDs,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    required int count,
  }) {
    return UsearchClusterCentroidVectorDB.instance.bulkSearchNearestAllowed(
      [
        for (final clusterID in queryClusterIDs)
          _clusterAvg[clusterID]!.toList(growable: false),
      ],
      allowedClusterIDs,
      maxDistance: maxDistance,
      count: count,
    );
  }

  @override
  Future<List<(String, double, String)>> suggestByMean(
    Set<String> personClusters,
    Set<String> ignoredClusters,
    double maxClusterDistance, {
    Map<String, Set<String>>? personClusterToIgnoredClusters,
  }) async {
    return await _computer.compute(
      _calcSuggestionsMean,
      param: {
        'clusterAvg': _clusterAvg,
        'personClusters': personClusters,
        'ignoredClusters': ignoredClusters,
        'maxClusterDistance': maxClusterDistance,
        'personClusterToIgnoredClusters': personClusterToIgnoredClusters,
      },
    );
  }
}

// Returns (suggestion cluster ID, distance, person cluster ID).
List<(String, double, String)> _calcSuggestionsMean(Map<String, dynamic> args) {
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
    suggestClusterIds.sort((a, b) => a.$2.compareTo(b.$2));

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
