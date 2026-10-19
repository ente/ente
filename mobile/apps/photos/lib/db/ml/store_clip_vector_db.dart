import "package:collection/collection.dart";
import "package:logging/logging.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;

class StoreClipVectorDB implements ClipVectorDB {
  static final Logger _logger = Logger("StoreClipVectorDB");
  static const int _bulkSearchBatchSize = 500;

  final RustMLDataDB _mlDataDB;

  StoreClipVectorDB._(this._mlDataDB);

  static final instance = StoreClipVectorDB._(RustMLDataDB.instance);
  static final localGalleryInstance = StoreClipVectorDB._(
    RustMLDataDB.localGalleryInstance,
  );

  @override
  Future<bool> isReady() async {
    try {
      return await _mlDataDB.fillState(rust.Index.clip) ==
          rust.FillState.filled;
    } catch (e, s) {
      _logger.warning(
        "Clip vector index readiness check failed, treating it as not ready",
        e,
        s,
      );
      return false;
    }
  }

  @override
  Future<void> warmup() async {
    final stopwatch = Stopwatch()..start();
    final stats = await (await _mlDataDB.store).stats(index: rust.Index.clip);
    _logger.info(
      "Clip vector index warmed up with ${stats.liveCount} vectors in ${stopwatch.elapsedMilliseconds} ms",
    );
  }

  @override
  Future<List<QueryResult>> searchSimilaritiesWithinThreshold(
    List<double> query,
    double minimumSimilarity,
  ) async {
    if (!await isReady()) {
      throw StateError(
        "ClipVectorDB index is not filled, cannot run similarity search",
      );
    }
    final matches = await (await _mlDataDB.store).search(
      index: rust.Index.clip,
      query: query,
      limit: null,
      maxDistance: 1.0 - minimumSimilarity,
      exact: true,
      allowedKeys: null,
    );
    return [
      for (final match in matches)
        QueryResult(int.parse(match.key), 1.0 - match.distance),
    ];
  }

  @override
  Future<Map<int, List<(int, double)>>> bulkSearchNearestForFiles(
    List<int> fileIDs, {
    required int count,
    required double maxDistance,
    required bool exact,
  }) async {
    if (fileIDs.isEmpty) return {};
    final store = await _mlDataDB.store;
    final nearest = <int, List<(int, double)>>{};
    for (final batch in fileIDs.slices(_bulkSearchBatchSize)) {
      nearest.addAll(
        await _bulkSearchStoredBatch(
          store,
          batch,
          count: count,
          maxDistance: maxDistance,
          exact: exact,
        ),
      );
    }
    return nearest;
  }

  Future<Map<int, List<(int, double)>>> _bulkSearchStoredBatch(
    rust.MlStore store,
    List<int> fileIDs, {
    required int count,
    required double maxDistance,
    required bool exact,
  }) async {
    final results = await store.bulkSearchStored(
      index: rust.Index.clip,
      keys: [for (final fileID in fileIDs) fileID.toString()],
      count: count,
      maxDistance: maxDistance,
      exact: exact,
      restrictToInput: false,
    );
    return {
      for (final result in results)
        int.parse(result.key): [
          for (final match in result.matches)
            (int.parse(match.key), match.distance),
        ],
    };
  }
}
