import "dart:typed_data" hide Int64List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:logging/logging.dart";
import "package:path/path.dart" show join;
import "package:path_provider/path_provider.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/common/base.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/ml_exclusive_operation.dart";
import "package:photos/db/ml/rust_db_model_mappers.dart" as mappers;
import "package:photos/events/embedding_updated_event.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import "package:photos/services/machine_learning/ml_process_lock.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;
import "package:photos/utils/ml_util.dart";

class RustMLDataDB implements IMLDataDB<int> {
  static final Logger _logger = Logger("MLDataDB");
  static const _clipFillBlocker = "clip_vector_db_migration_in_progress";
  static const _clusterCentroidFillBlocker =
      "cluster_centroid_vector_db_migration_in_progress";

  final String _databaseName;

  RustMLDataDB._privateConstructor({String databaseName = "ente.ml.db"})
    : _databaseName = databaseName;

  static final RustMLDataDB instance = RustMLDataDB._privateConstructor();
  static final RustMLDataDB localGalleryInstance =
      RustMLDataDB._privateConstructor(databaseName: "ente.ml.offline.db");

  Future<rust.MlStore>? _dbFuture;

  Future<rust.MlStore> get store async {
    final future = _dbFuture ??= _openDatabase();
    try {
      return await future;
    } catch (e) {
      if (e is! DatabaseDowngradeError && identical(_dbFuture, future)) {
        _dbFuture = null;
      }
      rethrow;
    }
  }

  Future<rust.MlStore> _openDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    _logger.info("Opening rust ML DB access: DB path $path");
    try {
      return await rust.MlStore.open(path: path);
    } on rust.MlDbError_Downgrade catch (e) {
      throw DatabaseDowngradeError(e.message);
    }
  }

  Future<rust.FillState> fillState(rust.Index index) async =>
      (await store).fillState(index: index);

  Future<void> releaseVectorIndexes() async {
    if (_dbFuture == null) return;
    try {
      await (await store).release();
    } catch (e, s) {
      _logger.warning("Failed to release vector indexes", e, s);
    }
  }

  @override
  Future<void> clearTable() => runMlOperationExclusive(
    MlOperation.clearData,
    () async => (await store).clearAll(),
  );

  @override
  Future<void> checkMigrateFillClipVectorDB({bool force = false}) =>
      _checkMigrateFillIndex(
        rust.Index.clip,
        force: force,
        operation: MlOperation.clipVectorMigration,
        blocker: _clipFillBlocker,
        fill: (db) => db.fillClipIndex(force: force),
      );

  @override
  Future<void> checkMigrateFillClusterCentroidVectorDB({bool force = false}) =>
      _checkMigrateFillIndex(
        rust.Index.clusterCentroid,
        force: force,
        operation: MlOperation.clusterCentroidVectorMigration,
        blocker: _clusterCentroidFillBlocker,
        fill: (db) => db.fillClusterCentroidIndex(force: force),
      );

  Future<void> _checkMigrateFillIndex(
    rust.Index index, {
    required bool force,
    required MlOperation operation,
    required String blocker,
    required Future<rust.FillReport> Function(rust.MlStore db) fill,
  }) async {
    if (!force && await fillState(index) == rust.FillState.filled) {
      return;
    }
    await runMlOperationExclusive(
      operation,
      () => _fillIndex(index, blocker: blocker, fill: fill),
      waitDeadline: kMlMigrationLockWaitDeadline,
    );
  }

  Future<void> _fillIndex(
    rust.Index index, {
    required String blocker,
    required Future<rust.FillReport> Function(rust.MlStore db) fill,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      computeController.blockCompute(blocker: blocker);
      final report = await fill(await store);
      _logger.info(
        "${index.name} index fill ${report.outcome.name} in ${stopwatch.elapsedMilliseconds} ms: rows=${report.rows}, indexed=${report.indexed}, skipped=${report.skipped}, resumed=${report.resumed}",
      );
    } finally {
      stopwatch.stop();
      computeController.unblockCompute(blocker: blocker);
    }
  }

  @override
  Future<void> bulkInsertFaces(List<Face> faces) async => (await store)
      .bulkInsertFaces(faces: faces.map(mappers.toFaceRow).toList());

  @override
  Future<void> updateFaceIdToClusterId(
    Map<String, String> faceIDToClusterID,
  ) async => (await store).updateFaceIdToClusterId(
    faceIdToClusterId: faceIDToClusterID,
  );

  @override
  Future<Map<int, int>> faceIndexedFileIds({
    int minimumMlVersion = faceMlVersion,
  }) async =>
      (await store).faceIndexedFileIds(minimumMlVersion: minimumMlVersion);

  @override
  Future<int> getFaceIndexedFileCount({
    int minimumMlVersion = faceMlVersion,
  }) async =>
      (await store).getFaceIndexedFileCount(minimumMlVersion: minimumMlVersion);

  @override
  Future<Map<String, int>> clusterIdToFaceCount() async =>
      (await store).clusterIdToFaceCount();

  @override
  Future<Set<String>> getBadFaceSingletonClusterIDs() async =>
      (await store).getBadFaceSingletonClusterIds();

  @override
  Future<Set<String>> getClustersWithThreeOrMoreNotPersonFeedback() async =>
      (await store).getClustersWithThreeOrMoreNotPersonFeedback();

  @override
  Future<Set<String>> getPersonIgnoredClusters(String personID) async =>
      (await store).getPersonIgnoredClusters(personId: personID);

  @override
  Future<Map<String, Set<String>>> getPersonToRejectedSuggestions() async =>
      (await store).getPersonToRejectedSuggestions();

  @override
  Future<Set<String>> getPersonClusterIDs(String personID) async =>
      (await store).getPersonClusterIds(personId: personID);

  @override
  Future<Set<String>> getPersonsClusterIDs(List<String> personID) async =>
      (await store).getPersonsClusterIds(personIds: personID);

  @override
  Future<Iterable<Uint8List>> getFaceEmbeddingsForCluster(
    String clusterID, {
    int? limit,
  }) async => (await store).getFaceEmbeddingsForCluster(
    clusterId: clusterID,
    limit: limit,
  );

  @override
  Future<Map<String, Iterable<Uint8List>>> getFaceEmbeddingsForClusters(
    Iterable<String> clusterIDs, {
    int? limit,
  }) async => (await store).getFaceEmbeddingsForClusters(
    clusterIds: clusterIDs.toList(),
    limit: limit,
  );

  @override
  Future<Face?> getCoverFaceForPerson({
    required int recentFileID,
    String? personID,
    String? avatarFaceId,
    String? clusterID,
  }) async {
    final db = await store;
    final row = await db.getCoverFaceForPerson(
      recentFileId: recentFileID,
      personId: personID,
      avatarFaceId: avatarFaceId,
      clusterId: clusterID,
    );
    return row == null ? null : mappers.toFace(row);
  }

  @override
  Future<List<Face>?> getFacesForGivenFileID(int fileUploadID) async {
    final db = await store;
    final rows = await db.getFacesForGivenFileId(fileUploadId: fileUploadID);
    return rows.isEmpty ? null : rows.map(mappers.toFace).toList();
  }

  @override
  Future<Map<int, List<FaceWithoutEmbedding>>>
  getFileIDsToFacesWithoutEmbedding() async {
    final db = await store;
    final rows = await db.getFileIdsToFacesWithoutEmbedding();
    return rows.map(
      (fileID, faces) =>
          MapEntry(fileID, faces.map(mappers.toFaceWithoutEmbedding).toList()),
    );
  }

  @override
  Future<Map<String, Iterable<String>>> getClusterToFaceIDs(
    Set<String> clusterIDs,
  ) async => (await store).getClusterToFaceIds(clusterIds: clusterIDs);

  @override
  Future<String?> getClusterIDForFaceID(String faceID) async =>
      (await store).getClusterIdForFaceId(faceId: faceID);

  @override
  Future<Map<String, Iterable<String>>> getAllClusterIdToFaceIDs() async =>
      (await store).getAllClusterIdToFaceIds();

  @override
  Future<Iterable<String>> getFaceIDsForCluster(String clusterID) async =>
      (await store).getFaceIdsForCluster(clusterId: clusterID);

  @override
  Future<List<String>> getFaceIDsForClusterOrderedByScore(
    String clusterID, {
    int limit = 10,
  }) async => (await store).getFaceIdsForClusterOrderedByScore(
    clusterId: clusterID,
    limit: limit,
  );

  @override
  Future<Map<String, Map<String, Set<String>>>>
  getPersonToClusterIdToFaceIds() async =>
      (await store).getPersonToClusterIdToFaceIds();

  @override
  Future<Map<String, Set<String>>> getPersonToClusterIDs() async =>
      (await store).getPersonToClusterIds();

  @override
  Future<Map<String, String>> getFaceIdToPersonIdForFaces(
    Iterable<String> faceIDs,
  ) async =>
      (await store).getFaceIdToPersonIdForFaces(faceIds: faceIDs.toList());

  @override
  Future<Map<String, Set<String>>> getClusterIdToFaceIdsForPerson(
    String personID,
  ) async => (await store).getClusterIdToFaceIdsForPerson(personId: personID);

  @override
  Future<Set<String>> getFaceIDsForPerson(String personID) async =>
      (await store).getFaceIdsForPerson(personId: personID);

  @override
  Future<List<String>> getFaceIDsForPersonOrderedByScore(
    String personID, {
    int limit = 10,
  }) async => (await store).getFaceIdsForPersonOrderedByScore(
    personId: personID,
    limit: limit,
  );

  @override
  Future<Iterable<double>> getBlurValuesForCluster(String clusterID) async =>
      (await store).getBlurValuesForCluster(clusterId: clusterID);

  @override
  Future<Map<String, String?>> getFaceIdsToClusterIds(
    Iterable<String> faceIds,
  ) async => (await store).getFaceIdsToClusterIds(faceIds: faceIds.toList());

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIds() async =>
      (await store).getFileIdToClusterIds();

  @override
  Future<void> forceUpdateClusterIds(
    Map<String, String> faceIDToClusterID,
  ) async =>
      (await store).forceUpdateClusterIds(faceIdToClusterId: faceIDToClusterID);

  @override
  Future<void> removeFaceIdToClusterId(
    Map<String, String> faceIDToClusterID,
  ) async => (await store).removeFaceIdToClusterId(
    faceIdToClusterId: faceIDToClusterID,
  );

  @override
  Future<void> removePerson(String personID) async =>
      (await store).removePerson(personId: personID);

  @override
  Future<List<FaceDbInfoForClustering>> getFaceInfoForClustering({
    int maxFaces = 20000,
    int offset = 0,
    int batchSize = 10000,
  }) async {
    final db = await store;
    final rows = await db.getFaceInfoForClustering(
      maxFaces: maxFaces,
      offset: offset,
      batchSize: batchSize,
    );
    return rows.map(mappers.toFaceDbInfoForClustering).toList();
  }

  @override
  Future<Map<String, Uint8List>> getFaceEmbeddingMapForFaces(
    Iterable<String> faceIDs,
  ) async {
    final db = await store;
    final rows = await db.getFaceEmbeddingRowsForFaces(
      faceIds: faceIDs.toList(),
    );
    return {for (final (faceID, embedding) in rows) faceID: embedding};
  }

  @override
  Future<int> getTotalFaceCount() async => (await store).getTotalFaceCount();

  @override
  Future<int> getErroredFaceCount() async =>
      (await store).getErroredFaceCount();

  @override
  Future<Set<int>> getErroredFileIDs() async {
    final db = await store;
    final fileIDs = await db.getErroredFileIds();
    return fileIDs.inner.toSet();
  }

  @override
  Future<void> pruneResolvedFaceErrorResults(List<int> fileIDs) async =>
      (await store).pruneResolvedFaceErrorResults(
        fileIds: Int64List.fromList(fileIDs),
      );

  @override
  Future<Set<int>> getFileIDsWithErrorResults(List<int> fileIDs) async {
    final db = await store;
    final result = await db.getFileIdsWithErrorResults(
      fileIds: Int64List.fromList(fileIDs),
    );
    return result.inner.toSet();
  }

  @override
  Future<void> deleteFaceIndexForFiles(List<int> fileIDs) async => (await store)
      .deleteFaceIndexForFiles(fileIds: Int64List.fromList(fileIDs));

  @override
  Future<void> deleteUnclusteredFaceIndexForFiles(List<int> fileIDs) async =>
      (await store).deleteUnclusteredFaceIndexForFiles(
        fileIds: Int64List.fromList(fileIDs),
      );

  @override
  Future<int> getClusteredOrFacelessFileCount() async =>
      (await store).getClusteredOrFacelessFileCount();

  @override
  Future<double> getClusteredToIndexableFilesRatio() async {
    final int indexableFiles = await getIndexableFileCount();
    final int clusteredFiles = await getClusteredOrFacelessFileCount();

    return clusteredFiles / indexableFiles;
  }

  @override
  Future<int> getUnclusteredFaceCount() async =>
      (await store).getUnclusteredFaceCount();

  @override
  Future<void> assignClusterToPerson({
    required String personID,
    required String clusterID,
  }) async => (await store).assignClusterToPerson(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<void> bulkAssignClusterToPersonID(
    Map<String, String> clusterToPersonID,
  ) async => (await store).bulkAssignClusterToPersonId(
    clusterToPersonId: clusterToPersonID,
  );

  @override
  Future<void> captureNotPersonFeedback({
    required String personID,
    required String clusterID,
  }) async => (await store).captureNotPersonFeedback(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<void> bulkCaptureNotPersonFeedback(
    Map<String, String> clusterToPersonID,
  ) async => (await store).bulkCaptureNotPersonFeedback(
    clusterToPersonId: clusterToPersonID,
  );

  @override
  Future<void> removeNotPersonFeedback({
    required String personID,
    required String clusterID,
  }) async => (await store).removeNotPersonFeedback(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<void> removeClusterToPerson({
    required String personID,
    required String clusterID,
  }) async => (await store).removeClusterToPerson(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIDSet(
    String personID,
  ) async => (await store).getFileIdToClusterIdSet(personId: personID);

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIDSetForCluster(
    Set<String> clusterIDs,
  ) async =>
      (await store).getFileIdToClusterIdSetForCluster(clusterIds: clusterIDs);

  @override
  Future<void> clusterSummaryUpdate(
    Map<String, (Uint8List, int)> summary,
  ) async {
    if (summary.isEmpty) return;
    try {
      await (await store).clusterSummaryUpdate(
        summary: summary.map(
          (clusterID, value) =>
              MapEntry(clusterID, mappers.toClusterSummaryRow(value)),
        ),
      );
    } on rust.MlDbError_Index catch (e, s) {
      _logClusterCentroidIndexWriteFailure("clusterSummaryUpdate", e, s);
    }
  }

  @override
  Future<void> deleteClusterSummary(String clusterID) async {
    try {
      await (await store).deleteClusterSummary(clusterId: clusterID);
    } on rust.MlDbError_Index catch (e, s) {
      _logClusterCentroidIndexWriteFailure("deleteClusterSummary", e, s);
    }
  }

  void _logClusterCentroidIndexWriteFailure(
    String operation,
    rust.MlDbError_Index error,
    StackTrace stackTrace,
  ) {
    _logger.severe(
      "ClusterCentroidVectorDB write failed during `$operation`. The index is marked stale and refills on the next fill check.",
      error,
      stackTrace,
    );
  }

  @override
  Future<Map<String, (Uint8List, int)>> getAllClusterSummary([
    int? minClusterSize,
  ]) async {
    final db = await store;
    final rows = await db.getAllClusterSummary(minClusterSize: minClusterSize);
    return rows.map(
      (clusterID, summary) =>
          MapEntry(clusterID, mappers.toClusterSummaryRecord(summary)),
    );
  }

  @override
  Future<Map<String, (Uint8List, int)>> getClusterToClusterSummary(
    Iterable<String> clusterIDs,
  ) async {
    final db = await store;
    final rows = await db.getClusterToClusterSummary(
      clusterIds: clusterIDs.toList(),
    );
    return rows.map(
      (clusterID, summary) =>
          MapEntry(clusterID, mappers.toClusterSummaryRecord(summary)),
    );
  }

  @override
  Future<Map<String, String>> getClusterIDToPersonID() async =>
      (await store).getClusterIdToPersonId();

  @override
  Future<void> dropClustersAndPersonTable({bool faces = false}) async {
    try {
      await (await store).dropClustersAndPersonTable(faces: faces);
    } catch (e, s) {
      _logger.severe("Error dropping clusters and person table", e, s);
    }
  }

  @override
  Future<void> dropFacesFeedbackTables() async {
    try {
      final db = await store;
      await db.dropFacesFeedbackTables();
    } catch (e) {
      _logger.severe('Error dropping feedback tables', e);
    }
  }

  @override
  Future<List<int>> getFileIDsOfPersonID(String personID) async {
    final db = await store;
    final fileIDs = await db.getFileIdsOfPersonId(personId: personID);
    return fileIDs.inner.toList();
  }

  @override
  Future<List<int>> getFileIDsOfClusterID(String clusterID) async {
    final db = await store;
    final fileIDs = await db.getFileIdsOfClusterId(clusterId: clusterID);
    return fileIDs.inner.toList();
  }

  @override
  Future<Set<int>> getAllFileIDsOfFaceIDsNotInAnyCluster() async {
    final db = await store;
    final fileIDs = await db.getAllFileIdsOfFaceIdsNotInAnyCluster();
    return fileIDs.inner.toSet();
  }

  @override
  Future<Set<int>> getAllFilesAssociatedWithAllClusters({
    List<String>? exceptClusters,
  }) async {
    final db = await store;
    final fileIDs = await db.getAllFilesAssociatedWithAllClusters(
      exceptClusters: exceptClusters,
    );
    return fileIDs.inner.toSet();
  }

  @override
  Future<List<EmbeddingVector>> getAllClipVectors() async {
    final db = await store;
    final rows = await db.getAllClipVectors();
    return rows
        .where(
          (row) => row.embedding.length == ClipVectorDB.embeddingDimensions,
        )
        .map(mappers.toEmbeddingVector)
        .toList();
  }

  @override
  Future<Map<int, int>> clipIndexedFileWithVersion() async =>
      (await store).clipIndexedFileWithVersion();

  @override
  Future<int> getClipIndexedFileCount({
    int minimumMlVersion = clipMlVersion,
  }) async =>
      (await store).getClipIndexedFileCount(minimumMlVersion: minimumMlVersion);

  @override
  Future<int> getClipVectorizableFileCount({
    int minimumMlVersion = clipMlVersion,
  }) async => (await store).getClipVectorizableFileCount(
    minimumMlVersion: minimumMlVersion,
  );

  @override
  Future<Map<int, int>> petIndexedFileIds({
    int minimumMlVersion = petMlVersion,
  }) async =>
      (await store).petIndexedFileIds(minimumMlVersion: minimumMlVersion);

  @override
  Future<Set<int>> getFullyIndexedFileIds({required bool includePets}) async {
    final db = await store;
    final fileIDs = await db.getFullyIndexedFileIds(includePets: includePets);
    return fileIDs.inner.toSet();
  }

  @override
  Future<void> putClip(List<ClipEmbedding> embeddings) async {
    if (embeddings.isEmpty) return;
    await (await store).putClip(
      embeddings: embeddings.map(mappers.toClipEmbeddingRow).toList(),
    );
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  @override
  Future<void> deleteClipEmbeddings(List<int> fileIDs) async {
    await (await store).deleteClip(fileIds: Int64List.fromList(fileIDs));
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  @override
  Future<void> deleteClipIndexes() async {
    await (await store).deleteAllClip();
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  @override
  Future<void> putRepeatedTextEmbeddingCache(
    String query,
    List<double> embedding,
  ) async => (await store).putRepeatedTextEmbeddingCache(
    query: query,
    embedding: embedding,
  );

  @override
  Future<List<double>?> getRepeatedTextEmbeddingCache(String query) async =>
      (await store).getRepeatedTextEmbeddingCache(query: query);

  @override
  Future<void> putFaceIdCachedForPersonOrCluster(
    String personOrClusterId,
    String faceID,
  ) async => (await store).putFaceIdCachedForPersonOrCluster(
    personOrClusterId: personOrClusterId,
    faceId: faceID,
  );

  @override
  Future<String?> getFaceIdUsedForPersonOrCluster(
    String personOrClusterId,
  ) async => (await store).getFaceIdUsedForPersonOrCluster(
    personOrClusterId: personOrClusterId,
  );

  @override
  Future<void> removeFaceIdCachedForPersonOrCluster(
    String personOrClusterID,
  ) async => (await store).removeFaceIdCachedForPersonOrCluster(
    personOrClusterId: personOrClusterID,
  );

  @override
  Future<Set<String>> getClustersForMemoryLane(Set<String> assigned) async =>
      (await store).getClustersForMemoryLane(assigned: assigned);

  @override
  Future<void> putFDStatus(List<FDStatus> fdStatusList) async =>
      (await store).putFdStatus(
        fdStatusList: fdStatusList.map(mappers.toFdStatusRow).toList(),
      );

  @override
  Future<Map<int, PreviewInfo>> getFileIDsVidPreview() async {
    final db = await store;
    final rows = await db.getFileIdsVidPreview();
    return rows.map(
      (fileID, info) => MapEntry(fileID, mappers.toPreviewInfo(info)),
    );
  }

  @override
  Future<Set<int>> getFileIDsWithFDData({DataType? type}) async {
    final db = await store;
    final fileIDs = await db.getFileIdsWithFdData(dataType: type?.toJson());
    return fileIDs.inner.toSet();
  }
}
