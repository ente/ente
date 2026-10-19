import "dart:typed_data" show Float32List;

import "package:logging/logging.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;

class StoreClusterCentroidVectorDB implements ClusterCentroidVectorDB {
  static final Logger _logger = Logger("StoreClusterCentroidVectorDB");

  final RustMLDataDB _mlDataDB;

  StoreClusterCentroidVectorDB._(this._mlDataDB);

  static final instance = StoreClusterCentroidVectorDB._(RustMLDataDB.instance);
  static final localGalleryInstance = StoreClusterCentroidVectorDB._(
    RustMLDataDB.localGalleryInstance,
  );

  @override
  Future<bool> isReady() async {
    try {
      return await _mlDataDB.fillState(rust.Index.clusterCentroid) ==
          rust.FillState.filled;
    } catch (e, s) {
      _logger.warning(
        "Cluster centroid vector index readiness check failed, treating it as not ready",
        e,
        s,
      );
      return false;
    }
  }

  @override
  Future<void> warmup() async {
    final stopwatch = Stopwatch()..start();
    final stats = await (await _mlDataDB.store).stats(
      index: rust.Index.clusterCentroid,
    );
    _logger.info(
      "Cluster centroid vector index warmed up with ${stats.liveCount} vectors in ${stopwatch.elapsedMilliseconds} ms",
    );
  }

  Future<void> _ensureReady() async {
    if (!await isReady()) {
      throw StateError(
        "Cluster centroid vector index is not filled, cannot run search",
      );
    }
  }

  @override
  Future<List<List<(String, double)>>> bulkSearchNearestAllowed(
    List<List<double>> queries,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    int count = 10,
  }) async {
    await _ensureReady();
    if (count <= 0 || queries.isEmpty || allowedClusterIDs.isEmpty) {
      return List.generate(queries.length, (_) => const <(String, double)>[]);
    }
    final matchesPerQuery = await (await _mlDataDB.store).bulkSearch(
      index: rust.Index.clusterCentroid,
      queries: [
        for (final query in queries)
          query is Float32List ? query : Float32List.fromList(query),
      ],
      limit: count,
      maxDistance: maxDistance,
      exact: false,
      allowedKeys: allowedClusterIDs.toList(),
    );
    return [
      for (var i = 0; i < queries.length; i++)
        i < matchesPerQuery.length
            ? [
                for (final match in matchesPerQuery[i])
                  (match.key, match.distance),
              ]
            : const <(String, double)>[],
    ];
  }

  @override
  Future<Map<String, ClusterCentroidMatches>> bulkSearchNearestForClusters(
    Set<String> queryClusterIDs, {
    required Set<String> candidateClusterIDs,
    required int count,
    double? maxDistance,
  }) async {
    await _ensureReady();
    if (count <= 0 || queryClusterIDs.isEmpty) {
      return const {};
    }
    final results = await (await _mlDataDB.store).bulkSearchStored(
      index: rust.Index.clusterCentroid,
      keys: queryClusterIDs.toList(),
      count: count,
      maxDistance: maxDistance,
      exact: false,
      restrictToInput: false,
    );
    return {
      for (final result in results)
        result.key: (
          matches: [
            for (final match in result.matches)
              if (candidateClusterIDs.contains(match.key))
                (match.key, match.distance),
          ],
          reachedCount: result.matches.length >= count,
        ),
    };
  }
}
