import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;

class StoreFaceClustering implements FaceClustering {
  static final Logger _logger = Logger("StoreFaceClustering");

  final RustMLDataDB _mlDataDB;

  StoreFaceClustering._(this._mlDataDB);

  static final instance = StoreFaceClustering._(RustMLDataDB.instance);
  static final localGalleryInstance = StoreFaceClustering._(
    RustMLDataDB.localGalleryInstance,
  );

  @override
  Future<void> clusterAllFaces({
    required Map<int, int> fileIDToCreationTime,
    required Map<String, List<String>> rejectedClusterIDsByFaceID,
    required MlRunControl control,
  }) async {
    final store = await _mlDataDB.store;
    final stopwatch = Stopwatch()..start();
    final run = await store.startFaceClustering(
      fileCreationTimes: fileIDToCreationTime,
      rejectedClusterIds: rejectedClusterIDsByFaceID,
      distanceThreshold: FaceClusteringService.defaultDistanceThreshold,
    );
    try {
      final plan = run.plan();
      _logger.info(
        "Prepared ${plan.faces} faces for clustering in ${stopwatch.elapsedMilliseconds} ms: "
        "${plan.unclusteredFaces} unclustered, ${plan.invalidFaces} skipped for invalid embeddings, "
        "unclustered faces of ${plan.missingFiles} missing files pruned",
      );
      while (true) {
        if (control.stopRequested) {
          _logger.info("Clustering stopped (${control.stopReason?.name})");
          return;
        }
        stopwatch.reset();
        final rust.ClusteredBucket? bucket;
        try {
          bucket = await store.clusterNextBucket(run: run);
        } on rust.MlDbError_Index catch (e, s) {
          _logger.severe(
            "ClusterCentroidVectorDB write failed while clustering. The index is marked stale and refills on the next fill check.",
            e,
            s,
          );
          Bus.instance.fire(PeopleChangedEvent());
          continue;
        }
        if (bucket == null) {
          _logger.info("All faces clustered");
          return;
        }
        Bus.instance.fire(PeopleChangedEvent());
        _logger.info(
          "Clustered ${bucket.clusteredFaces} new faces, ${bucket.processedFaces} of ${plan.faces} done, in ${stopwatch.elapsedMilliseconds} ms",
        );
      }
    } finally {
      run.dispose();
    }
  }

  @override
  Future<Map<String, String>> reclusterFaces(
    List<String> faceIDs, {
    required Map<int, int> fileIDToCreationTime,
    required double distanceThreshold,
  }) async {
    final fileIDs = faceIDs.map(getFileIdFromFaceId<int>).toSet();
    return (await _mlDataDB.store).reclusterFaces(
      faceIds: faceIDs,
      fileCreationTimes: {
        for (final fileID in fileIDs) fileID: ?fileIDToCreationTime[fileID],
      },
      distanceThreshold: distanceThreshold,
    );
  }
}
