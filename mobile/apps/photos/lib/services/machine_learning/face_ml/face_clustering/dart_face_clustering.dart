import "dart:math" show min;
import "dart:typed_data" show Uint8List;

import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/dart_db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";

class DartFaceClustering implements FaceClustering {
  static final Logger _logger = Logger("DartFaceClustering");

  final IMLDataDB<int> _mlDataDB;

  DartFaceClustering._(this._mlDataDB);

  static final instance = DartFaceClustering._(DartMLDataDB.instance);
  static final localGalleryInstance = DartFaceClustering._(
    DartMLDataDB.localGalleryInstance,
  );

  @override
  Future<void> clusterAllFaces({
    required Map<int, int> fileIDToCreationTime,
    required Map<String, List<String>> rejectedClusterIDsByFaceID,
    required MlRunControl control,
  }) async {
    final mlDataDB = _mlDataDB;
    final int totalFaces = await mlDataDB.getTotalFaceCount();
    final startEmbeddingFetch = DateTime.now();
    final result = await mlDataDB.getFaceInfoForClustering(
      maxFaces: totalFaces,
    );
    final Set<int> missingFileIDs = {};
    final allFaceInfoForClustering = <FaceDbInfoForClustering>[];
    for (final faceInfo in result) {
      if (!fileIDToCreationTime.containsKey(faceInfo.fileID)) {
        missingFileIDs.add(faceInfo.fileID);
      } else {
        if (rejectedClusterIDsByFaceID.containsKey(faceInfo.faceID)) {
          faceInfo.rejectedClusterIds =
              rejectedClusterIDsByFaceID[faceInfo.faceID];
        }
        allFaceInfoForClustering.add(faceInfo);
      }
    }
    allFaceInfoForClustering.sort((b, a) {
      return fileIDToCreationTime[a.fileID]!.compareTo(
        fileIDToCreationTime[b.fileID]!,
      );
    });
    _logger.info(
      'Getting and sorting embeddings took ${DateTime.now().difference(startEmbeddingFetch).inMilliseconds} ms for ${allFaceInfoForClustering.length} embeddings'
      'and ${missingFileIDs.length} missing fileIDs',
    );

    if (missingFileIDs.isNotEmpty) {
      await mlDataDB.deleteUnclusteredFaceIndexForFiles(
        missingFileIDs.toList(),
      );
      _logger.info(
        'Pruned unclustered face data for ${missingFileIDs.length} missing files',
      );
    }

    if (allFaceInfoForClustering.every((face) => face.clusterId != null)) {
      _logger.info('All faces clustered');
      return;
    }

    final Map<String, (Uint8List, int)> oldClusterSummaries = await mlDataDB
        .getAllClusterSummary();

    const int bucketSize = 10000;
    const int offsetIncrement = 7500;
    int offset = 0;
    int bucket = 1;

    while (true) {
      if (control.stopRequested) {
        _logger.info(
          "Clustering stopped before bucket $bucket (${control.stopReason?.name})",
        );
        break;
      }
      if (offset > allFaceInfoForClustering.length - 1) {
        _logger.warning(
          'faceIdToEmbeddingBucket is empty, this should ideally not happen as it should have stopped earlier. offset: $offset, totalFaces: $totalFaces',
        );
        break;
      }
      if (offset > totalFaces) {
        _logger.warning(
          'offset > totalFaces, this should ideally not happen. offset: $offset, totalFaces: $totalFaces',
        );
        break;
      }

      final bucketStartTime = DateTime.now();
      final faceInfoForClustering = allFaceInfoForClustering.sublist(
        offset,
        min(offset + bucketSize, allFaceInfoForClustering.length),
      );

      if (faceInfoForClustering.every((face) => face.clusterId != null)) {
        _logger.info('Everything in bucket $bucket is already clustered');
        if (offset + bucketSize >= totalFaces) {
          _logger.info('All faces clustered');
          break;
        } else {
          _logger.info('Skipping to next bucket');
          offset += offsetIncrement;
          bucket++;
          continue;
        }
      }

      final clusteringResult = await FaceClusteringService.instance
          .predictLinearIsolate(
            faceInfoForClustering.toSet(),
            fileIDToCreationTime: fileIDToCreationTime,
            offset: offset,
            oldClusterSummaries: oldClusterSummaries,
          );
      if (clusteringResult == null) {
        _logger.warning("faceIdToCluster is null");
        return;
      }

      await mlDataDB.updateFaceIdToClusterId(
        clusteringResult.newFaceIdToCluster,
      );
      await mlDataDB.clusterSummaryUpdate(clusteringResult.newClusterSummaries);
      Bus.instance.fire(PeopleChangedEvent());
      for (final faceInfo in faceInfoForClustering) {
        faceInfo.clusterId ??=
            clusteringResult.newFaceIdToCluster[faceInfo.faceID];
      }
      for (final clusterUpdate
          in clusteringResult.newClusterSummaries.entries) {
        oldClusterSummaries[clusterUpdate.key] = clusterUpdate.value;
      }
      _logger.info(
        'Done with clustering ${offset + faceInfoForClustering.length} embeddings (${(100 * (offset + faceInfoForClustering.length) / totalFaces).toStringAsFixed(0)}%) in bucket $bucket, offset: $offset, in ${DateTime.now().difference(bucketStartTime).inSeconds} seconds',
      );
      if (offset + bucketSize >= totalFaces) {
        _logger.info('All faces clustered');
        break;
      }
      offset += offsetIncrement;
      bucket++;
    }
  }

  @override
  Future<Map<String, String>> reclusterFaces(
    List<String> faceIDs, {
    required Map<int, int> fileIDToCreationTime,
    required double distanceThreshold,
  }) async {
    final embeddings = await _mlDataDB.getFaceEmbeddingMapForFaces(faceIDs);
    if (embeddings.isEmpty) return {};
    final clusterResult = await FaceClusteringService.instance
        .predictWithinClusterComputer(
          embeddings,
          fileIDToCreationTime: fileIDToCreationTime,
          distanceThreshold: distanceThreshold,
        );
    if (clusterResult.isEmpty) return {};
    await _mlDataDB.forceUpdateClusterIds(clusterResult.newFaceIdToCluster);
    await _mlDataDB.clusterSummaryUpdate(clusterResult.newClusterSummaries);
    return clusterResult.newFaceIdToCluster;
  }
}
