import "dart:typed_data" hide Int64List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:logging/logging.dart";
import "package:path/path.dart" show join;
import "package:path_provider/path_provider.dart";
import "package:photos/db/common/base.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/db/ml/ml_data_db_orchestration.dart";
import "package:photos/db/ml/rust_db_model_mappers.dart" as mappers;
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;
import "package:photos/utils/ml_util.dart";

class RustMLDataDB with MLDataDBOrchestration implements IMLDataDB<int> {
  static final Logger _logger = Logger("MLDataDB");

  final String _databaseName;
  final ClipVectorDB _clipVectorDB;
  final ClusterCentroidVectorDB _clusterCentroidVectorDB;
  final bool _isLocalGallery;

  RustMLDataDB._privateConstructor({
    String databaseName = "ente.ml.db",
    ClipVectorDB? clipVectorDB,
    ClusterCentroidVectorDB? clusterCentroidVectorDB,
    bool isLocalGallery = false,
  }) : _databaseName = databaseName,
       _clipVectorDB = clipVectorDB ?? ClipVectorDB.instance,
       _clusterCentroidVectorDB =
           clusterCentroidVectorDB ?? ClusterCentroidVectorDB.instance,
       _isLocalGallery = isLocalGallery;

  static final RustMLDataDB instance = RustMLDataDB._privateConstructor();
  static final RustMLDataDB localGalleryInstance =
      RustMLDataDB._privateConstructor(
        databaseName: "ente.ml.offline.db",
        clipVectorDB: ClipVectorDB.localGalleryInstance,
        clusterCentroidVectorDB: ClusterCentroidVectorDB.localGalleryInstance,
        isLocalGallery: true,
      );

  @override
  ClipVectorDB get clipVectorDB => _clipVectorDB;

  @override
  ClusterCentroidVectorDB get clusterCentroidVectorDB =>
      _clusterCentroidVectorDB;

  @override
  bool get isLocalGallery => _isLocalGallery;

  @override
  Logger get logger => _logger;

  Future<rust.MlDb>? _dbFuture;

  Future<rust.MlDb> get _db async {
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

  Future<rust.MlDb> _openDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    _logger.info("Opening rust ML DB access: DB path $path");
    try {
      return await rust.MlDb.open(path: path);
    } on rust.MlDbError_Downgrade catch (e) {
      throw DatabaseDowngradeError(e.message);
    }
  }

  @override
  Future<void> bulkInsertFaces(List<Face> faces) async =>
      (await _db).bulkInsertFaces(faces: faces.map(mappers.toFaceRow).toList());

  @override
  Future<void> bulkInsertPetFaces(List<DBPetFace> petFaces) async =>
      (await _db).bulkInsertPetFaces(
        petFaces: petFaces.map(mappers.toPetFaceRow).toList(),
      );

  @override
  Future<void> bulkInsertPetBodies(List<DBPetBody> petBodies) async =>
      (await _db).bulkInsertPetBodies(
        petBodies: petBodies.map(mappers.toPetBodyRow).toList(),
      );

  @override
  Future<void> updatePetFaceVectorIds(
    Map<String, int> petFaceIdToVectorId,
  ) async => (await _db).updatePetFaceVectorIds(
    petFaceIdToVectorId: petFaceIdToVectorId,
  );

  @override
  Future<void> updatePetBodyVectorIds(
    Map<String, int> petBodyIdToVectorId,
  ) async => (await _db).updatePetBodyVectorIds(
    petBodyIdToVectorId: petBodyIdToVectorId,
  );

  @override
  Future<Map<String, int>> getPetFaceVectorIdMap(
    Iterable<String> petFaceIds, {
    bool createIfMissing = false,
  }) async => (await _db).getPetFaceVectorIdMap(
    petFaceIds: petFaceIds.toList(),
    createIfMissing: createIfMissing,
  );

  @override
  Future<Map<String, int>> getPetBodyVectorIdMap(
    Iterable<String> petBodyIds, {
    bool createIfMissing = false,
  }) async => (await _db).getPetBodyVectorIdMap(
    petBodyIds: petBodyIds.toList(),
    createIfMissing: createIfMissing,
  );

  @override
  Future<void> updateFaceIdToClusterId(
    Map<String, String> faceIDToClusterID,
  ) async =>
      (await _db).updateFaceIdToClusterId(faceIdToClusterId: faceIDToClusterID);

  @override
  Future<Map<int, int>> faceIndexedFileIds({
    int minimumMlVersion = faceMlVersion,
  }) async =>
      (await _db).faceIndexedFileIds(minimumMlVersion: minimumMlVersion);

  @override
  Future<int> getFaceIndexedFileCount({
    int minimumMlVersion = faceMlVersion,
  }) async =>
      (await _db).getFaceIndexedFileCount(minimumMlVersion: minimumMlVersion);

  @override
  Future<Map<String, int>> clusterIdToFaceCount() async =>
      (await _db).clusterIdToFaceCount();

  @override
  Future<Set<String>> getBadFaceSingletonClusterIDs() async =>
      (await _db).getBadFaceSingletonClusterIds();

  @override
  Future<Set<String>> getClustersWithThreeOrMoreNotPersonFeedback() async =>
      (await _db).getClustersWithThreeOrMoreNotPersonFeedback();

  @override
  Future<Set<String>> getPersonIgnoredClusters(String personID) async =>
      (await _db).getPersonIgnoredClusters(personId: personID);

  @override
  Future<Map<String, Set<String>>> getPersonToRejectedSuggestions() async =>
      (await _db).getPersonToRejectedSuggestions();

  @override
  Future<Set<String>> getPersonClusterIDs(String personID) async =>
      (await _db).getPersonClusterIds(personId: personID);

  @override
  Future<Set<String>> getPersonsClusterIDs(List<String> personID) async =>
      (await _db).getPersonsClusterIds(personIds: personID);

  @override
  Future<void> clearNonPetTables() async => (await _db).clearNonPetTables();

  @override
  Future<void> clearPetTables() async => (await _db).clearPetTables();

  @override
  Future<Iterable<Uint8List>> getFaceEmbeddingsForCluster(
    String clusterID, {
    int? limit,
  }) async => (await _db).getFaceEmbeddingsForCluster(
    clusterId: clusterID,
    limit: limit,
  );

  @override
  Future<Map<String, Iterable<Uint8List>>> getFaceEmbeddingsForClusters(
    Iterable<String> clusterIDs, {
    int? limit,
  }) async => (await _db).getFaceEmbeddingsForClusters(
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
    final db = await _db;
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
    final db = await _db;
    final rows = await db.getFacesForGivenFileId(fileUploadId: fileUploadID);
    return rows.isEmpty ? null : rows.map(mappers.toFace).toList();
  }

  @override
  Future<List<DBPetFace>?> getPetFacesForFileID(int fileUploadID) async {
    final db = await _db;
    final rows = await db.getPetFacesForFileId(fileUploadId: fileUploadID);
    return rows.isEmpty ? null : rows.map(mappers.toDBPetFace).toList();
  }

  @override
  Future<List<DBPetBody>?> getPetBodiesForFileID(int fileUploadID) async {
    final db = await _db;
    final rows = await db.getPetBodiesForFileId(fileUploadId: fileUploadID);
    return rows.isEmpty ? null : rows.map(mappers.toDBPetBody).toList();
  }

  @override
  Future<Map<int, List<FaceWithoutEmbedding>>>
  getFileIDsToFacesWithoutEmbedding() async {
    final db = await _db;
    final rows = await db.getFileIdsToFacesWithoutEmbedding();
    return rows.map(
      (fileID, faces) =>
          MapEntry(fileID, faces.map(mappers.toFaceWithoutEmbedding).toList()),
    );
  }

  @override
  Future<Map<String, Iterable<String>>> getClusterToFaceIDs(
    Set<String> clusterIDs,
  ) async => (await _db).getClusterToFaceIds(clusterIds: clusterIDs);

  @override
  Future<String?> getClusterIDForFaceID(String faceID) async =>
      (await _db).getClusterIdForFaceId(faceId: faceID);

  @override
  Future<Map<String, Iterable<String>>> getAllClusterIdToFaceIDs() async =>
      (await _db).getAllClusterIdToFaceIds();

  @override
  Future<Iterable<String>> getFaceIDsForCluster(String clusterID) async =>
      (await _db).getFaceIdsForCluster(clusterId: clusterID);

  @override
  Future<List<String>> getFaceIDsForClusterOrderedByScore(
    String clusterID, {
    int limit = 10,
  }) async => (await _db).getFaceIdsForClusterOrderedByScore(
    clusterId: clusterID,
    limit: limit,
  );

  @override
  Future<Map<String, Map<String, Set<String>>>>
  getPersonToClusterIdToFaceIds() async =>
      (await _db).getPersonToClusterIdToFaceIds();

  @override
  Future<Map<String, Set<String>>> getPersonToClusterIDs() async =>
      (await _db).getPersonToClusterIds();

  @override
  Future<Map<String, String>> getFaceIdToPersonIdForFaces(
    Iterable<String> faceIDs,
  ) async => (await _db).getFaceIdToPersonIdForFaces(faceIds: faceIDs.toList());

  @override
  Future<Map<String, Set<String>>> getClusterIdToFaceIdsForPerson(
    String personID,
  ) async => (await _db).getClusterIdToFaceIdsForPerson(personId: personID);

  @override
  Future<Set<String>> getFaceIDsForPerson(String personID) async =>
      (await _db).getFaceIdsForPerson(personId: personID);

  @override
  Future<List<String>> getFaceIDsForPersonOrderedByScore(
    String personID, {
    int limit = 10,
  }) async => (await _db).getFaceIdsForPersonOrderedByScore(
    personId: personID,
    limit: limit,
  );

  @override
  Future<Iterable<double>> getBlurValuesForCluster(String clusterID) async =>
      (await _db).getBlurValuesForCluster(clusterId: clusterID);

  @override
  Future<Map<String, String?>> getFaceIdsToClusterIds(
    Iterable<String> faceIds,
  ) async => (await _db).getFaceIdsToClusterIds(faceIds: faceIds.toList());

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIds() async =>
      (await _db).getFileIdToClusterIds();

  @override
  Future<void> forceUpdateClusterIds(
    Map<String, String> faceIDToClusterID,
  ) async =>
      (await _db).forceUpdateClusterIds(faceIdToClusterId: faceIDToClusterID);

  @override
  Future<void> removeFaceIdToClusterId(
    Map<String, String> faceIDToClusterID,
  ) async =>
      (await _db).removeFaceIdToClusterId(faceIdToClusterId: faceIDToClusterID);

  @override
  Future<void> removePerson(String personID) async =>
      (await _db).removePerson(personId: personID);

  @override
  Future<List<FaceDbInfoForClustering>> getFaceInfoForClustering({
    int maxFaces = 20000,
    int offset = 0,
    int batchSize = 10000,
  }) async {
    final db = await _db;
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
    final db = await _db;
    final rows = await db.getFaceEmbeddingRowsForFaces(
      faceIds: faceIDs.toList(),
    );
    return {for (final (faceID, embedding) in rows) faceID: embedding};
  }

  @override
  Future<int> getTotalFaceCount() async => (await _db).getTotalFaceCount();

  @override
  Future<int> getErroredFaceCount() async => (await _db).getErroredFaceCount();

  @override
  Future<Set<int>> getErroredFileIDs() async {
    final db = await _db;
    final fileIDs = await db.getErroredFileIds();
    return fileIDs.inner.toSet();
  }

  @override
  Future<void> pruneResolvedFaceErrorResults(List<int> fileIDs) async =>
      (await _db).pruneResolvedFaceErrorResults(
        fileIds: Int64List.fromList(fileIDs),
      );

  @override
  Future<Set<int>> getFileIDsWithErrorResults(List<int> fileIDs) async {
    final db = await _db;
    final result = await db.getFileIdsWithErrorResults(
      fileIds: Int64List.fromList(fileIDs),
    );
    return result.inner.toSet();
  }

  @override
  Future<void> deleteFaceIndexForFiles(List<int> fileIDs) async =>
      (await _db).deleteFaceIndexForFiles(fileIds: Int64List.fromList(fileIDs));

  @override
  Future<void> deleteUnclusteredFaceIndexForFiles(List<int> fileIDs) async =>
      (await _db).deleteUnclusteredFaceIndexForFiles(
        fileIds: Int64List.fromList(fileIDs),
      );

  @override
  Future<int> getClusteredOrFacelessFileCount() async =>
      (await _db).getClusteredOrFacelessFileCount();

  @override
  Future<double> getClusteredToIndexableFilesRatio() async {
    final int indexableFiles = await getIndexableFileCount();
    final int clusteredFiles = await getClusteredOrFacelessFileCount();

    return clusteredFiles / indexableFiles;
  }

  @override
  Future<int> getUnclusteredFaceCount() async =>
      (await _db).getUnclusteredFaceCount();

  @override
  Future<void> assignClusterToPerson({
    required String personID,
    required String clusterID,
  }) async => (await _db).assignClusterToPerson(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<void> bulkAssignClusterToPersonID(
    Map<String, String> clusterToPersonID,
  ) async => (await _db).bulkAssignClusterToPersonId(
    clusterToPersonId: clusterToPersonID,
  );

  @override
  Future<void> captureNotPersonFeedback({
    required String personID,
    required String clusterID,
  }) async => (await _db).captureNotPersonFeedback(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<void> bulkCaptureNotPersonFeedback(
    Map<String, String> clusterToPersonID,
  ) async => (await _db).bulkCaptureNotPersonFeedback(
    clusterToPersonId: clusterToPersonID,
  );

  @override
  Future<void> removeNotPersonFeedback({
    required String personID,
    required String clusterID,
  }) async => (await _db).removeNotPersonFeedback(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<void> removeClusterToPerson({
    required String personID,
    required String clusterID,
  }) async => (await _db).removeClusterToPerson(
    personId: personID,
    clusterId: clusterID,
  );

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIDSet(
    String personID,
  ) async => (await _db).getFileIdToClusterIdSet(personId: personID);

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIDSetForCluster(
    Set<String> clusterIDs,
  ) async =>
      (await _db).getFileIdToClusterIdSetForCluster(clusterIds: clusterIDs);

  @override
  Future<Map<String, int>> getClusterCentroidVectorIdMap(
    Iterable<String> clusterIDs, {
    bool createIfMissing = false,
  }) async => (await _db).getClusterCentroidVectorIdMap(
    clusterIds: clusterIDs.toList(),
    createIfMissing: createIfMissing,
  );

  @override
  Future<void> deleteClusterCentroidVectorIdMapping(String clusterID) async =>
      (await _db).deleteClusterCentroidVectorIdMapping(clusterId: clusterID);

  @override
  Future<void> clearClusterCentroidVectorIdMappings() async =>
      (await _db).clearClusterCentroidVectorIdMappings();

  @override
  Future<void> upsertClusterSummaryRows(
    Map<String, (Uint8List, int)> summary,
  ) async => (await _db).upsertClusterSummaryRows(
    summary: summary.map(
      (clusterID, value) =>
          MapEntry(clusterID, mappers.toClusterSummaryRow(value)),
    ),
  );

  @override
  Future<void> deleteClusterSummaryRow(String clusterID) async =>
      (await _db).deleteClusterSummaryRow(clusterId: clusterID);

  @override
  Future<Map<String, (Uint8List, int)>> getAllClusterSummary([
    int? minClusterSize,
  ]) async {
    final db = await _db;
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
    final db = await _db;
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
      (await _db).getClusterIdToPersonId();

  @override
  Future<void> resetClusterTables({required bool faces}) async =>
      (await _db).resetClusterTables(faces: faces);

  @override
  Future<void> dropFacesFeedbackTables() async {
    try {
      final db = await _db;
      await db.dropFacesFeedbackTables();
    } catch (e) {
      _logger.severe('Error dropping feedback tables', e);
    }
  }

  @override
  Future<List<int>> getFileIDsOfPersonID(String personID) async {
    final db = await _db;
    final fileIDs = await db.getFileIdsOfPersonId(personId: personID);
    return fileIDs.inner.toList();
  }

  @override
  Future<List<int>> getFileIDsOfClusterID(String clusterID) async {
    final db = await _db;
    final fileIDs = await db.getFileIdsOfClusterId(clusterId: clusterID);
    return fileIDs.inner.toList();
  }

  @override
  Future<Set<int>> getAllFileIDsOfFaceIDsNotInAnyCluster() async {
    final db = await _db;
    final fileIDs = await db.getAllFileIdsOfFaceIdsNotInAnyCluster();
    return fileIDs.inner.toSet();
  }

  @override
  Future<Set<int>> getAllFilesAssociatedWithAllClusters({
    List<String>? exceptClusters,
  }) async {
    final db = await _db;
    final fileIDs = await db.getAllFilesAssociatedWithAllClusters(
      exceptClusters: exceptClusters,
    );
    return fileIDs.inner.toSet();
  }

  @override
  Future<List<EmbeddingVector>> getAllClipVectors() async {
    final db = await _db;
    final rows = await db.getAllClipVectors();
    return rows.map(mappers.toEmbeddingVector).toList();
  }

  @override
  Future<int> countClusterSummaries() async =>
      (await _db).countClusterSummaries();

  @override
  Future<List<(String, Uint8List)>> getClusterSummaryPage({
    String? beforeClusterID,
    required int limit,
  }) async {
    final db = await _db;
    final rows = await db.getClusterSummaryPage(
      beforeClusterId: beforeClusterID,
      limit: limit,
    );
    return [for (final row in rows) (row.clusterId, row.avg)];
  }

  @override
  Future<int> countClipRows() async => (await _db).countClipRows();

  @override
  Future<List<(int, Uint8List)>> getClipRowsPage({
    required int limit,
    required int offset,
  }) async {
    final db = await _db;
    final rows = await db.getClipRowsPage(limit: limit, offset: offset);
    return [for (final row in rows) (row.fileId, row.embedding)];
  }

  @override
  Future<Map<int, int>> clipIndexedFileWithVersion() async =>
      (await _db).clipIndexedFileWithVersion();

  @override
  Future<int> getClipIndexedFileCount({
    int minimumMlVersion = clipMlVersion,
  }) async =>
      (await _db).getClipIndexedFileCount(minimumMlVersion: minimumMlVersion);

  @override
  Future<int> getClipVectorizableFileCount({
    int minimumMlVersion = clipMlVersion,
  }) async => (await _db).getClipVectorizableFileCount(
    minimumMlVersion: minimumMlVersion,
  );

  @override
  Future<Map<int, int>> petIndexedFileIds({
    int minimumMlVersion = petMlVersion,
  }) async => (await _db).petIndexedFileIds(minimumMlVersion: minimumMlVersion);

  @override
  Future<int> getPetIndexedFileCount({
    int minimumMlVersion = petMlVersion,
  }) async =>
      (await _db).getPetIndexedFileCount(minimumMlVersion: minimumMlVersion);

  @override
  Future<Set<int>> getFullyIndexedFileIds({required bool includePets}) async {
    final db = await _db;
    final fileIDs = await db.getFullyIndexedFileIds(includePets: includePets);
    return fileIDs.inner.toSet();
  }

  @override
  Future<(List<(String, int?, int)>, List<(String, int?, int)>)>
  getPetRowsForFiles(List<int> fileIDs) async {
    final db = await _db;
    final rows = await db.getPetRowsForFiles(
      fileIds: Int64List.fromList(fileIDs),
    );
    return (
      [
        for (final row in rows.faces)
          (row.petFaceId, row.faceVectorId, row.species),
      ],
      [
        for (final row in rows.bodies)
          (row.petBodyId, row.bodyVectorId, row.species),
      ],
    );
  }

  @override
  Future<void> deletePetRowsForFiles({
    required List<int> fileIDs,
    required List<String> petFaceIds,
    required List<String> petBodyIds,
  }) async => (await _db).deletePetRowsForFiles(
    fileIds: Int64List.fromList(fileIDs),
    petFaceIds: petFaceIds,
    petBodyIds: petBodyIds,
  );

  @override
  Future<void> insertClipRows(List<ClipEmbedding> embeddings) async =>
      (await _db).insertClipRows(
        embeddings: embeddings.map(mappers.toClipEmbeddingRow).toList(),
      );

  @override
  Future<void> putRepeatedTextEmbeddingCache(
    String query,
    List<double> embedding,
  ) async => (await _db).putRepeatedTextEmbeddingCache(
    query: query,
    embedding: embedding,
  );

  @override
  Future<List<double>?> getRepeatedTextEmbeddingCache(String query) async =>
      (await _db).getRepeatedTextEmbeddingCache(query: query);

  @override
  Future<void> deleteClipRows(List<int> fileIDs) async =>
      (await _db).deleteClipRows(fileIds: Int64List.fromList(fileIDs));

  @override
  Future<void> deleteAllClipRows() async => (await _db).deleteAllClipRows();

  @override
  Future<void> putFaceIdCachedForPersonOrCluster(
    String personOrClusterId,
    String faceID,
  ) async => (await _db).putFaceIdCachedForPersonOrCluster(
    personOrClusterId: personOrClusterId,
    faceId: faceID,
  );

  @override
  Future<String?> getFaceIdUsedForPersonOrCluster(
    String personOrClusterId,
  ) async => (await _db).getFaceIdUsedForPersonOrCluster(
    personOrClusterId: personOrClusterId,
  );

  @override
  Future<void> removeFaceIdCachedForPersonOrCluster(
    String personOrClusterID,
  ) async => (await _db).removeFaceIdCachedForPersonOrCluster(
    personOrClusterId: personOrClusterID,
  );

  @override
  Future<Set<String>> getClustersForMemoryLane(Set<String> assigned) async =>
      (await _db).getClustersForMemoryLane(assigned: assigned);

  @override
  Future<void> putFDStatus(List<FDStatus> fdStatusList) async =>
      (await _db).putFdStatus(
        fdStatusList: fdStatusList.map(mappers.toFdStatusRow).toList(),
      );

  @override
  Future<Map<int, PreviewInfo>> getFileIDsVidPreview() async {
    final db = await _db;
    final rows = await db.getFileIdsVidPreview();
    return rows.map(
      (fileID, info) => MapEntry(fileID, mappers.toPreviewInfo(info)),
    );
  }

  @override
  Future<Set<int>> getFileIDsWithFDData({DataType? type}) async {
    final db = await _db;
    final fileIDs = await db.getFileIdsWithFdData(dataType: type?.toJson());
    return fileIDs.inner.toSet();
  }
}
