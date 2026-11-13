import "package:logging/logging.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/db/ml/store_cluster_centroid_vector_db.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_averages.dart";

class StoreClusterAverages implements ClusterAverages {
  static final Logger _logger = Logger("StoreClusterAverages");

  final RustMLDataDB _mlDataDB;

  @override
  final Set<String> clusterIDs;

  StoreClusterAverages._(this._mlDataDB, this.clusterIDs);

  static Future<StoreClusterAverages> refresh(
    Map<String, int> allClusterIdsToCountMap,
    Set<String> ignoredClusters, {
    required int minClusterSize,
  }) async {
    final mlDataDB = RustMLDataDB.instance;
    final stopwatch = Stopwatch()..start();
    final clusterIDs = await (await mlDataDB.store).refreshClusterAverages(
      clusterFaceCounts: allClusterIdsToCountMap,
      ignoredClusterIds: ignoredClusters.toList(),
      minClusterSize: minClusterSize,
    );
    _logger.info(
      'Refreshed cluster averages in ${stopwatch.elapsedMilliseconds} ms, ${clusterIDs.length} clusters have an average (minClusterSize $minClusterSize)',
    );
    return StoreClusterAverages._(mlDataDB, clusterIDs);
  }

  @override
  Future<List<List<(String, double)>>> searchNearest(
    List<String> queryClusterIDs,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    required int count,
  }) {
    return StoreClusterCentroidVectorDB.instance
        .bulkSearchNearestAllowedForClusters(
          queryClusterIDs,
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
    final suggestions = await (await _mlDataDB.store).suggestClustersByMean(
      personClusterIds: personClusters.where(clusterIDs.contains).toList(),
      candidateClusterIds: clusterIDs
          .difference(personClusters)
          .difference(ignoredClusters)
          .toList(),
      maxDistance: maxClusterDistance,
      ignoredByPersonCluster: {
        for (final entry in (personClusterToIgnoredClusters ?? {}).entries)
          entry.key: entry.value.toList(),
      },
    );
    return [
      for (final suggestion in suggestions)
        (suggestion.clusterId, suggestion.distance, suggestion.personClusterId),
    ];
  }
}
