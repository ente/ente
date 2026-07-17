import "dart:async";
import "dart:developer";
import "dart:typed_data" show Uint8List;

import "package:computer/computer.dart";
import "package:logging/logging.dart";
import "package:ml_linalg/dtype.dart";
import "package:ml_linalg/vector.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/models/base/id.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/isolate/super_isolate.dart";

class FaceInfo {
  final String faceID;
  final double? faceScore;
  final double? blurValue;
  final bool? badFace;
  final Vector? vEmbedding;
  String? clusterId;
  final List<String>? rejectedClusterIds;
  String? closestFaceId;
  int? closestDist;
  int? fileCreationTime;
  FaceInfo({
    required this.faceID,
    this.faceScore,
    this.blurValue,
    this.badFace,
    this.vEmbedding,
    this.clusterId,
    this.rejectedClusterIds,
    this.fileCreationTime,
  });
}

enum ClusterOperation { linearIncrementalClustering }

class ClusteringResult {
  final Map<String, String> newFaceIdToCluster;
  final Map<String, List<String>> newClusterIdToFaceIds;
  final Map<String, (Uint8List, int)> newClusterSummaries;

  bool get isEmpty => newFaceIdToCluster.isEmpty;

  ClusteringResult({
    required this.newFaceIdToCluster,
    required this.newClusterSummaries,
    required this.newClusterIdToFaceIds,
  });

  factory ClusteringResult.empty() {
    return ClusteringResult(
      newFaceIdToCluster: {},
      newClusterIdToFaceIds: {},
      newClusterSummaries: {},
    );
  }
}

@pragma('vm:entry-point')
class FaceClusteringService extends SuperIsolate {
  @override
  Logger get logger => _logger;
  final _logger = Logger("FaceLinearClustering");

  final _computer = Computer.shared();

  bool isRunning = false;

  static const kRecommendedDistanceThreshold = 0.24;
  static const kConservativeDistanceThreshold = 0.16;
  static const kConservativeDistanceDelta =
      kRecommendedDistanceThreshold - kConservativeDistanceThreshold;

  static double defaultDistanceThreshold = kRecommendedDistanceThreshold;

  @override
  String get isolateName => "FaceClusteringIsolate";

  @override
  bool get shouldAutomaticDispose => true;

  // singleton pattern
  FaceClusteringService._privateConstructor();

  /// Use this instance to access the FaceClustering service.
  /// e.g. `FaceLinearClustering.instance.predict(dataset)`
  static final instance = FaceClusteringService._privateConstructor();
  factory FaceClusteringService() => instance;

  static void init(LocalSettings settings) {
    final savedDistance = settings.defaultClusteringDistanceOverride;
    if (savedDistance != null) {
      defaultDistanceThreshold = savedDistance.clamp(0.0, 1.0);
    }
  }

  /// Runs the clustering algorithm [runLinearClustering] on the given [input], in an isolate.
  ///
  /// Returns the clustering result, which is a list of clusters, where each cluster is a list of indices of the dataset.
  Future<ClusteringResult?> predictLinearIsolate(
    Set<FaceDbInfoForClustering> input, {
    Map<int, int>? fileIDToCreationTime,
    double? distanceThreshold,
    double? conservativeDistanceThreshold,
    bool useDynamicThreshold = true,
    int? offset,
    required Map<String, (Uint8List, int)> oldClusterSummaries,
  }) async {
    final resolvedDistanceThreshold =
        distanceThreshold ?? defaultDistanceThreshold;
    final resolvedConservativeDistanceThreshold =
        conservativeDistanceThreshold ??
        (resolvedDistanceThreshold - kConservativeDistanceDelta).clamp(
          0.0,
          resolvedDistanceThreshold,
        );
    if (input.isEmpty) {
      _logger.warning(
        "Clustering dataset of embeddings is empty, returning empty list.",
      );
      return null;
    }
    if (isRunning) {
      _logger.warning("Clustering is already running, returning empty list.");
      return null;
    }

    isRunning = true;
    try {
      // Clustering inside the isolate
      _logger.info(
        "Start clustering on ${input.length} embeddings inside computer isolate",
      );
      final stopwatchClustering = Stopwatch()..start();
      // final Map<String, int> faceIdToCluster =
      //     await _runLinearClusteringInComputer(input);
      final ClusteringResult faceIdToCluster =
          await runInIsolate(IsolateOperation.linearIncrementalClustering, {
            'input': input,
            'fileIDToCreationTime': fileIDToCreationTime,
            'distanceThreshold': resolvedDistanceThreshold,
            'conservativeDistanceThreshold':
                resolvedConservativeDistanceThreshold,
            'useDynamicThreshold': useDynamicThreshold,
            'offset': offset,
            'oldClusterSummaries': oldClusterSummaries,
          });
      // return _runLinearClusteringInComputer(input);
      _logger.info(
        'predictLinear Clustering executed in ${stopwatchClustering.elapsed.inSeconds} seconds',
      );

      return faceIdToCluster;
    } catch (e, stackTrace) {
      _logger.severe('Error while running clustering', e, stackTrace);
      rethrow;
    } finally {
      isRunning = false;
    }
  }

  Future<ClusteringResult> predictWithinClusterComputer(
    Map<String, Uint8List> input, {
    Map<int, int>? fileIDToCreationTime,
    Map<String, (Uint8List, int)> oldClusterSummaries =
        const <String, (Uint8List, int)>{},
    double? distanceThreshold,
  }) async {
    final resolvedDistanceThreshold =
        distanceThreshold ?? defaultDistanceThreshold;
    _logger.info(
      '`predictWithinClusterComputer` called with ${input.length} faces and distance threshold $resolvedDistanceThreshold',
    );
    try {
      if (input.length < 500) {
        final mergeThreshold = resolvedDistanceThreshold;
        _logger.info(
          'Running complete clustering on ${input.length} faces with distance threshold $mergeThreshold',
        );
        final ClusteringResult clusterResult = await _predictCompleteComputer(
          input,
          fileIDToCreationTime: fileIDToCreationTime,
          oldClusterSummaries: oldClusterSummaries,
          distanceThreshold:
              (resolvedDistanceThreshold - kConservativeDistanceDelta).clamp(
                0.0,
                resolvedDistanceThreshold,
              ),
          mergeThreshold: mergeThreshold,
        );
        return clusterResult;
      } else {
        _logger.info(
          'Running linear clustering on ${input.length} faces with distance threshold $resolvedDistanceThreshold',
        );
        final ClusteringResult clusterResult = await _predictLinearComputer(
          input,
          fileIDToCreationTime: fileIDToCreationTime,
          oldClusterSummaries: oldClusterSummaries,
          distanceThreshold: resolvedDistanceThreshold,
        );
        return clusterResult;
      }
    } catch (e, s) {
      _logger.severe("Face clustering prediction failed", e, s);
      rethrow;
    }
  }

  /// Runs the clustering algorithm [runLinearClustering] on the given [input], in computer, without any dynamic thresholding
  Future<ClusteringResult> _predictLinearComputer(
    Map<String, Uint8List> input, {
    Map<int, int>? fileIDToCreationTime,
    required Map<String, (Uint8List, int)> oldClusterSummaries,
    double? distanceThreshold,
  }) async {
    final resolvedDistanceThreshold =
        distanceThreshold ?? defaultDistanceThreshold;
    if (input.isEmpty) {
      _logger.warning(
        "Linear Clustering dataset of embeddings is empty, returning empty list.",
      );
      return ClusteringResult.empty();
    }

    // Clustering inside the isolate
    _logger.info(
      "Start Linear clustering on ${input.length} embeddings inside computer isolate",
    );

    try {
      final clusteringInput = input
          .map((key, value) {
            return MapEntry(
              key,
              FaceDbInfoForClustering(
                faceID: key,
                embeddingBytes: value,
                faceScore: kMinimumQualityFaceScore + 0.01,
                blurValue: kLapacianDefault,
              ),
            );
          })
          .values
          .toSet();
      final startTime = DateTime.now();
      final faceIdToCluster =
          await _computer.compute(
                runLinearClustering,
                param: {
                  "input": clusteringInput,
                  "fileIDToCreationTime": fileIDToCreationTime,
                  "oldClusterSummaries": oldClusterSummaries,
                  "distanceThreshold": resolvedDistanceThreshold,
                  "conservativeDistanceThreshold":
                      (resolvedDistanceThreshold - kConservativeDistanceDelta)
                          .clamp(0.0, resolvedDistanceThreshold),
                  "useDynamicThreshold": false,
                },
                taskName: "createImageEmbedding",
              )
              as ClusteringResult;
      final endTime = DateTime.now();
      _logger.info(
        "Linear Clustering took: ${endTime.difference(startTime).inMilliseconds}ms",
      );
      return faceIdToCluster;
    } catch (e, s) {
      _logger.severe("Linear face clustering failed", e, s);
      rethrow;
    }
  }

  /// Runs the clustering algorithm [_runCompleteClustering] on the given [input], in computer.
  ///
  /// WARNING: Only use on small datasets, as it is not optimized for large datasets.
  Future<ClusteringResult> _predictCompleteComputer(
    Map<String, Uint8List> input, {
    Map<int, int>? fileIDToCreationTime,
    required Map<String, (Uint8List, int)> oldClusterSummaries,
    double? distanceThreshold,
    double mergeThreshold = 0.30,
  }) async {
    final resolvedDistanceThreshold =
        distanceThreshold ?? defaultDistanceThreshold;
    if (input.isEmpty) {
      _logger.warning(
        "Complete Clustering dataset of embeddings is empty, returning empty list.",
      );
      return ClusteringResult.empty();
    }

    // Clustering inside the isolate
    _logger.info(
      "Start Complete clustering on ${input.length} embeddings inside computer isolate",
    );

    try {
      final startTime = DateTime.now();
      final clusteringResult =
          await _computer.compute(
                _runCompleteClustering,
                param: {
                  "input": input,
                  "fileIDToCreationTime": fileIDToCreationTime,
                  "oldClusterSummaries": oldClusterSummaries,
                  "distanceThreshold": resolvedDistanceThreshold,
                  "mergeThreshold": mergeThreshold,
                },
                taskName: "createImageEmbedding",
              )
              as ClusteringResult;
      final endTime = DateTime.now();
      _logger.info(
        "Complete Clustering took: ${endTime.difference(startTime).inMilliseconds}ms",
      );
      return clusteringResult;
    } catch (e, s) {
      _logger.severe("Complete face clustering failed", e, s);
      rethrow;
    }
  }
}

final _logger = Logger("FaceLinearClustering");

ClusteringResult runLinearClustering(Map args) {
  // final input = args['input'] as Map<String, (int?, Uint8List)>;
  final input = args['input'] as Set<FaceDbInfoForClustering>;
  final fileIDToCreationTime = args['fileIDToCreationTime'] as Map<int, int>?;
  final distanceThreshold = args['distanceThreshold'] as double;
  final conservativeDistanceThreshold =
      args['conservativeDistanceThreshold'] as double;
  final useDynamicThreshold = args['useDynamicThreshold'] as bool;
  final offset = args['offset'] as int?;
  final oldClusterSummaries =
      args['oldClusterSummaries'] as Map<String, (Uint8List, int)>?;

  _logger.info("Copied to isolate ${input.length} faces");

  // Organize everything into a list of FaceInfo objects
  final List<FaceInfo> faceInfos = [];
  for (final face in input) {
    faceInfos.add(
      FaceInfo(
        faceID: face.faceID,
        faceScore: face.faceScore,
        blurValue: face.blurValue,
        badFace:
            face.faceScore < kMinimumQualityFaceScore ||
            face.blurValue < kLaplacianSoftThreshold ||
            (face.blurValue < kLaplacianVerySoftThreshold &&
                face.faceScore < kMediumQualityFaceScore) ||
            face.isSideways,
        vEmbedding: Vector.fromList(
          EVector.fromBuffer(face.embeddingBytes).values,
          dtype: DType.float32,
        ),
        clusterId: face.clusterId,
        rejectedClusterIds: face.rejectedClusterIds,
        fileCreationTime:
            fileIDToCreationTime?[getFileIdFromFaceId<int>(face.faceID)],
      ),
    );
  }

  // Assert that the embeddings are normalized
  for (final faceInfo in faceInfos) {
    if (faceInfo.vEmbedding != null) {
      final norm = faceInfo.vEmbedding!.norm();
      assert((norm - 1.0).abs() < 1e-5);
    }
  }

  if (fileIDToCreationTime != null) {
    _sortFaceInfosOnCreationTime(faceInfos);
  }

  // Sort the faceInfos such that the ones with null clusterId are at the end
  final List<FaceInfo> facesWithClusterID = <FaceInfo>[];
  final List<FaceInfo> facesWithoutClusterID = <FaceInfo>[];
  for (final FaceInfo faceInfo in faceInfos) {
    if (faceInfo.clusterId == null) {
      facesWithoutClusterID.add(faceInfo);
    } else {
      facesWithClusterID.add(faceInfo);
    }
  }
  final alreadyClusteredCount = facesWithClusterID.length;
  final newToClusterCount = facesWithoutClusterID.length;
  final sortedFaceInfos = <FaceInfo>[];
  sortedFaceInfos.addAll(facesWithClusterID);
  sortedFaceInfos.addAll(facesWithoutClusterID);

  if (sortedFaceInfos.isEmpty) {
    return ClusteringResult.empty();
  }
  final int totalFaces = sortedFaceInfos.length;
  int dynamicThresholdCount = 0;

  // Start actual clustering
  _logger.info(
    "[ClusterIsolate] ${DateTime.now()} Processing $totalFaces faces ($newToClusterCount new, $alreadyClusteredCount already done) in total in this round ${offset != null ? "on top of ${offset + facesWithClusterID.length} earlier processed faces" : ""}",
  );
  String clusterID = newClusterID();
  if (facesWithClusterID.isEmpty) {
    // assign a clusterID to the first face
    sortedFaceInfos[0].clusterId = clusterID;
    clusterID = newClusterID();
  }
  final stopwatchClustering = Stopwatch()..start();
  for (int i = 1; i < totalFaces; i++) {
    // Incremental clustering, so we can skip faces that already have a clusterId
    if (sortedFaceInfos[i].clusterId != null) {
      // clusterID = max(clusterID, sortedFaceInfos[i].clusterId!);
      continue;
    }

    int closestIdx = -1;
    double closestDistance = double.infinity;
    late double thresholdValue;
    if (useDynamicThreshold) {
      thresholdValue = sortedFaceInfos[i].badFace!
          ? conservativeDistanceThreshold
          : distanceThreshold;
      if (sortedFaceInfos[i].badFace!) dynamicThresholdCount++;
    } else {
      thresholdValue = distanceThreshold;
    }
    final bool faceHasBeenRejectedBefore =
        sortedFaceInfos[i].rejectedClusterIds != null;
    if (i % 250 == 0) {
      _logger.info("Processed ${offset != null ? i + offset : i} faces");
    }
    // WARNING: The loop below is now O(n^2) so be very careful with anything you put in there!
    for (int j = i - 1; j >= 0; j--) {
      final double distance =
          1 -
          sortedFaceInfos[i].vEmbedding!.dot(sortedFaceInfos[j].vEmbedding!);
      if (distance < closestDistance) {
        if (sortedFaceInfos[j].badFace! &&
            distance > conservativeDistanceThreshold) {
          continue;
        }
        if (faceHasBeenRejectedBefore &&
            sortedFaceInfos[j].clusterId != null &&
            sortedFaceInfos[i].rejectedClusterIds!.contains(
              sortedFaceInfos[j].clusterId!,
            )) {
          continue;
        }
        closestDistance = distance;
        closestIdx = j;
      }
    }

    if (closestDistance < thresholdValue) {
      if (sortedFaceInfos[closestIdx].clusterId == null) {
        // Ideally this should never happen, but just in case log it
        _logger.severe(
          "Found new cluster $clusterID, but closest face has no clusterId",
        );
        clusterID = newClusterID();
        sortedFaceInfos[closestIdx].clusterId = clusterID;
      }
      sortedFaceInfos[i].clusterId = sortedFaceInfos[closestIdx].clusterId;
    } else {
      clusterID = newClusterID();
      sortedFaceInfos[i].clusterId = clusterID;
    }
  }

  // Finally, assign the new clusterId to the faces
  final Map<String, String> newFaceIdToCluster = {};
  final newClusteredFaceInfos = sortedFaceInfos.sublist(alreadyClusteredCount);
  for (final faceInfo in newClusteredFaceInfos) {
    newFaceIdToCluster[faceInfo.faceID] = faceInfo.clusterId!;
  }

  // Create a map of clusterId to faceIds
  final Map<String, List<String>> clusterIdToFaceIds = {};
  for (final entry in newFaceIdToCluster.entries) {
    final clusterID = entry.value;
    if (clusterIdToFaceIds.containsKey(clusterID)) {
      clusterIdToFaceIds[clusterID]!.add(entry.key);
    } else {
      clusterIdToFaceIds[clusterID] = [entry.key];
    }
  }

  stopwatchClustering.stop();
  _logger.info(
    'Clustering for ${sortedFaceInfos.length} embeddings executed in ${stopwatchClustering.elapsedMilliseconds}ms',
  );
  if (useDynamicThreshold) {
    _logger.info(
      "Dynamic thresholding: $dynamicThresholdCount faces had a low face score or low blur clarity",
    );
  }

  // Now calculate the mean of the embeddings for each cluster and update the cluster summaries
  final newClusterSummaries = _updateClusterSummaries(
    newFaceInfos: newClusteredFaceInfos,
    oldSummary: oldClusterSummaries,
  );

  // analyze the results
  // FaceClusteringService._analyzeClusterResults(sortedFaceInfos);

  return ClusteringResult(
    newFaceIdToCluster: newFaceIdToCluster,
    newClusterSummaries: newClusterSummaries,
    newClusterIdToFaceIds: clusterIdToFaceIds,
  );
}

ClusteringResult _runCompleteClustering(Map args) {
  final input = args['input'] as Map<String, Uint8List>;
  final fileIDToCreationTime = args['fileIDToCreationTime'] as Map<int, int>?;
  final distanceThreshold = args['distanceThreshold'] as double;
  final mergeThreshold = args['mergeThreshold'] as double;
  final oldClusterSummaries =
      args['oldClusterSummaries'] as Map<String, (Uint8List, int)>?;

  log(
    "[CompleteClustering] ${DateTime.now()} Copied to isolate ${input.length} faces for clustering",
  );

  // Organize everything into a list of FaceInfo objects
  final List<FaceInfo> faceInfos = [];
  for (final entry in input.entries) {
    faceInfos.add(
      FaceInfo(
        faceID: entry.key,
        vEmbedding: Vector.fromList(
          EVector.fromBuffer(entry.value).values,
          dtype: DType.float32,
        ),
        fileCreationTime:
            fileIDToCreationTime?[getFileIdFromFaceId<int>(entry.key)],
      ),
    );
  }

  if (fileIDToCreationTime != null) {
    _sortFaceInfosOnCreationTime(faceInfos);
  }

  if (faceInfos.isEmpty) {
    ClusteringResult.empty();
  }
  final int totalFaces = faceInfos.length;

  // Start actual clustering
  log(
    "[CompleteClustering] ${DateTime.now()} Processing $totalFaces faces in one single round of complete clustering",
  );

  String clusterID = newClusterID();

  // Start actual clustering
  final Map<String, String> newFaceIdToCluster = {};
  final stopwatchClustering = Stopwatch()..start();
  for (int i = 0; i < totalFaces; i++) {
    if ((i + 1) % 250 == 0) {
      log("[CompleteClustering] ${DateTime.now()} Processed ${i + 1} faces");
    }
    if (faceInfos[i].clusterId != null) continue;
    int closestIdx = -1;
    double closestDistance = double.infinity;
    for (int j = 0; j < totalFaces; j++) {
      if (i == j) continue;
      final double distance =
          1 - faceInfos[i].vEmbedding!.dot(faceInfos[j].vEmbedding!);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIdx = j;
      }
    }

    if (closestDistance < distanceThreshold) {
      if (faceInfos[closestIdx].clusterId == null) {
        clusterID = newClusterID();
        faceInfos[closestIdx].clusterId = clusterID;
      }
      faceInfos[i].clusterId = faceInfos[closestIdx].clusterId!;
    } else {
      clusterID = newClusterID();
      faceInfos[i].clusterId = clusterID;
    }
  }

  // Now calculate the mean of the embeddings for each cluster
  final Map<String, List<FaceInfo>> clusterIdToFaceInfos = {};
  for (final faceInfo in faceInfos) {
    if (clusterIdToFaceInfos.containsKey(faceInfo.clusterId)) {
      clusterIdToFaceInfos[faceInfo.clusterId]!.add(faceInfo);
    } else {
      clusterIdToFaceInfos[faceInfo.clusterId!] = [faceInfo];
    }
  }
  final Map<String, (Vector, int)> clusterIdToMeanEmbeddingAndWeight = {};
  for (final clusterId in clusterIdToFaceInfos.keys) {
    final List<Vector> embeddings = clusterIdToFaceInfos[clusterId]!
        .map((faceInfo) => faceInfo.vEmbedding!)
        .toList();
    final count = clusterIdToFaceInfos[clusterId]!.length;
    final Vector meanEmbedding = embeddings.reduce((a, b) => a + b) / count;
    final Vector meanEmbeddingNormalized = meanEmbedding / meanEmbedding.norm();
    clusterIdToMeanEmbeddingAndWeight[clusterId] = (
      meanEmbeddingNormalized,
      count,
    );
  }

  // Now merge the clusters that are close to each other, based on mean embedding
  final List<(String, String)> mergedClustersList = [];
  final List<String> clusterIds = clusterIdToMeanEmbeddingAndWeight.keys
      .toList();
  log(
    ' [CompleteClustering] ${DateTime.now()} ${clusterIds.length} clusters found, now checking for merges',
  );
  while (true) {
    if (clusterIds.length < 2) break;
    double distance = double.infinity;
    (String, String) clusterIDsToMerge = ('', '');
    for (int i = 0; i < clusterIds.length; i++) {
      for (int j = 0; j < clusterIds.length; j++) {
        if (i == j) continue;
        final double newDistance =
            1 -
            clusterIdToMeanEmbeddingAndWeight[clusterIds[i]]!.$1.dot(
              clusterIdToMeanEmbeddingAndWeight[clusterIds[j]]!.$1,
            );
        if (newDistance < distance) {
          distance = newDistance;
          clusterIDsToMerge = (clusterIds[i], clusterIds[j]);
        }
      }
    }
    if (distance < mergeThreshold) {
      mergedClustersList.add(clusterIDsToMerge);
      final clusterID1 = clusterIDsToMerge.$1;
      final clusterID2 = clusterIDsToMerge.$2;
      final mean1 = clusterIdToMeanEmbeddingAndWeight[clusterID1]!.$1;
      final mean2 = clusterIdToMeanEmbeddingAndWeight[clusterID2]!.$1;
      final count1 = clusterIdToMeanEmbeddingAndWeight[clusterID1]!.$2;
      final count2 = clusterIdToMeanEmbeddingAndWeight[clusterID2]!.$2;
      final weight1 = count1 / (count1 + count2);
      final weight2 = count2 / (count1 + count2);
      final weightedMean = mean1 * weight1 + mean2 * weight2;
      final weightedMeanNormalized = weightedMean / weightedMean.norm();
      clusterIdToMeanEmbeddingAndWeight[clusterID1] = (
        weightedMeanNormalized,
        count1 + count2,
      );
      clusterIdToMeanEmbeddingAndWeight.remove(clusterID2);
      clusterIds.remove(clusterID2);
    } else {
      break;
    }
  }
  log(
    ' [CompleteClustering] ${DateTime.now()} ${mergedClustersList.length} clusters merged',
  );

  // Now assign the new clusterId to the faces
  for (final faceInfo in faceInfos) {
    for (final mergedClusters in mergedClustersList) {
      if (faceInfo.clusterId == mergedClusters.$2) {
        faceInfo.clusterId = mergedClusters.$1;
      }
    }
  }

  // Finally, assign the new clusterId to the faces
  for (final faceInfo in faceInfos) {
    newFaceIdToCluster[faceInfo.faceID] = faceInfo.clusterId!;
  }

  final Map<String, List<String>> clusterIdToFaceIds = {};
  for (final entry in newFaceIdToCluster.entries) {
    final clusterID = entry.value;
    if (clusterIdToFaceIds.containsKey(clusterID)) {
      clusterIdToFaceIds[clusterID]!.add(entry.key);
    } else {
      clusterIdToFaceIds[clusterID] = [entry.key];
    }
  }

  // Now calculate the mean of the embeddings for each cluster and update the cluster summaries
  final newClusterSummaries = _updateClusterSummaries(
    newFaceInfos: faceInfos,
    oldSummary: oldClusterSummaries,
  );

  stopwatchClustering.stop();
  log(
    ' [CompleteClustering] ${DateTime.now()} Clustering for ${faceInfos.length} embeddings executed in ${stopwatchClustering.elapsedMilliseconds}ms',
  );

  return ClusteringResult(
    newFaceIdToCluster: newFaceIdToCluster,
    newClusterSummaries: newClusterSummaries,
    newClusterIdToFaceIds: clusterIdToFaceIds,
  );
}

/// Sort the faceInfos based on fileCreationTime, in descending order, so newest faces are first
void _sortFaceInfosOnCreationTime(List<FaceInfo> faceInfos) {
  faceInfos.sort((b, a) {
    if (a.fileCreationTime == null && b.fileCreationTime == null) {
      return 0;
    } else if (a.fileCreationTime == null) {
      return 1;
    } else if (b.fileCreationTime == null) {
      return -1;
    } else {
      return a.fileCreationTime!.compareTo(b.fileCreationTime!);
    }
  });
}

Map<String, (Uint8List, int)> _updateClusterSummaries({
  required List<FaceInfo> newFaceInfos,
  Map<String, (Uint8List, int)>? oldSummary,
}) {
  final calcSummariesStart = DateTime.now();
  final Map<String, List<FaceInfo>> newClusterIdToFaceInfos = {};
  for (final faceInfo in newFaceInfos) {
    if (newClusterIdToFaceInfos.containsKey(faceInfo.clusterId!)) {
      newClusterIdToFaceInfos[faceInfo.clusterId!]!.add(faceInfo);
    } else {
      newClusterIdToFaceInfos[faceInfo.clusterId!] = [faceInfo];
    }
  }

  final Map<String, (Uint8List, int)> newClusterSummaries = {};
  for (final clusterId in newClusterIdToFaceInfos.keys) {
    final List<Vector> newEmbeddings = newClusterIdToFaceInfos[clusterId]!
        .map((faceInfo) => faceInfo.vEmbedding!)
        .toList();
    final newCount = newEmbeddings.length;
    if (oldSummary != null && oldSummary.containsKey(clusterId)) {
      final oldMean = Vector.fromList(
        EVector.fromBuffer(oldSummary[clusterId]!.$1).values,
        dtype: DType.float32,
      );
      final oldCount = oldSummary[clusterId]!.$2;
      final oldEmbeddings = oldMean * oldCount;
      newEmbeddings.add(oldEmbeddings);
      final newMeanVector =
          newEmbeddings.reduce((a, b) => a + b) / (oldCount + newCount);
      final newMeanVectorNormalized = newMeanVector / newMeanVector.norm();
      newClusterSummaries[clusterId] = (
        EVector(values: newMeanVectorNormalized.toList()).writeToBuffer(),
        oldCount + newCount,
      );
    } else {
      final newMeanVector = newEmbeddings.reduce((a, b) => a + b);
      final newMeanVectorNormalized = newMeanVector / newMeanVector.norm();
      newClusterSummaries[clusterId] = (
        EVector(values: newMeanVectorNormalized.toList()).writeToBuffer(),
        newCount,
      );
    }
  }
  _logger.info(
    "Calculated cluster summaries in ${DateTime.now().difference(calcSummariesStart).inMilliseconds}ms",
  );

  return newClusterSummaries;
}
