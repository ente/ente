import "dart:typed_data";

import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";

abstract class IMLDataDB<T> {
  Future<void> bulkInsertFaces(List<Face> faces);
  Future<void> bulkInsertPetFaces(List<DBPetFace> petFaces);
  Future<void> bulkInsertPetBodies(List<DBPetBody> petBodies);
  Future<void> updateFaceIdToClusterId(Map<String, String> faceIDToClusterID);
  Future<Map<int, int>> faceIndexedFileIds({int minimumMlVersion});
  Future<int> getFaceIndexedFileCount({int minimumMlVersion});
  Future<Map<String, int>> clusterIdToFaceCount();
  Future<Set<String>> getPersonIgnoredClusters(String personID);
  Future<Map<String, Set<String>>> getPersonToRejectedSuggestions();
  Future<Set<String>> getPersonClusterIDs(String personID);
  Future<Set<String>> getPersonsClusterIDs(List<String> personID);
  Future<void> clearTable();
  Future<Iterable<Uint8List>> getFaceEmbeddingsForCluster(
    String clusterID, {
    int? limit,
  });
  Future<Map<String, Iterable<Uint8List>>> getFaceEmbeddingsForClusters(
    Iterable<String> clusterIDs, {
    int? limit,
  });
  Future<Face?> getCoverFaceForPerson({
    required T recentFileID,
    String? personID,
    String? avatarFaceId,
    String? clusterID,
  });
  Future<List<Face>?> getFacesForGivenFileID(T fileUploadID);
  Future<List<DBPetFace>?> getPetFacesForFileID(T fileUploadID);
  Future<List<DBPetBody>?> getPetBodiesForFileID(T fileUploadID);
  Future<Map<int, List<FaceWithoutEmbedding>>>
  getFileIDsToFacesWithoutEmbedding();
  Future<Map<String, Iterable<String>>> getClusterToFaceIDs(
    Set<String> clusterIDs,
  );
  Future<String?> getClusterIDForFaceID(String faceID);
  Future<Map<String, Iterable<String>>> getAllClusterIdToFaceIDs();
  Future<Iterable<String>> getFaceIDsForCluster(String clusterID);
  Future<Map<String, Map<String, Set<String>>>> getPersonToClusterIdToFaceIds();
  Future<Map<String, Set<String>>> getPersonToClusterIDs();
  Future<Map<String, Set<String>>> getClusterIdToFaceIdsForPerson(
    String personID,
  );
  Future<Set<String>> getFaceIDsForPerson(String personID);
  Future<Iterable<double>> getBlurValuesForCluster(String clusterID);
  Future<Map<String, String?>> getFaceIdsToClusterIds(Iterable<String> faceIds);
  Future<Map<T, Set<String>>> getFileIdToClusterIds();
  Future<void> forceUpdateClusterIds(Map<String, String> faceIDToClusterID);
  Future<void> removeFaceIdToClusterId(Map<String, String> faceIDToClusterID);
  Future<void> removePerson(String personID);
  Future<List<FaceDbInfoForClustering>> getFaceInfoForClustering({
    int maxFaces,
    int offset,
    int batchSize,
  });
  Future<Map<String, Uint8List>> getFaceEmbeddingMapForFaces(
    Iterable<String> faceIDs,
  );
  Future<int> getTotalFaceCount();
  Future<int> getErroredFaceCount();
  Future<Set<T>> getErroredFileIDs();
  Future<void> deleteFaceIndexForFiles(List<T> fileIDs);
  Future<int> getClusteredOrFacelessFileCount();
  Future<double> getClusteredToIndexableFilesRatio();
  Future<int> getUnclusteredFaceCount();
  Future<void> assignClusterToPerson({
    required String personID,
    required String clusterID,
  });
  Future<void> bulkAssignClusterToPersonID(
    Map<String, String> clusterToPersonID,
  );
  Future<void> captureNotPersonFeedback({
    required String personID,
    required String clusterID,
  });
  Future<void> bulkCaptureNotPersonFeedback(
    Map<String, String> clusterToPersonID,
  );
  Future<void> removeNotPersonFeedback({
    required String personID,
    required String clusterID,
  });
  Future<void> removeClusterToPerson({
    required String personID,
    required String clusterID,
  });
  Future<Map<T, Set<String>>> getFileIdToClusterIDSet(String personID);
  Future<Map<T, Set<String>>> getFileIdToClusterIDSetForCluster(
    Set<String> clusterIDs,
  );
  Future<void> clusterSummaryUpdate(Map<String, (Uint8List, int)> summary);
  Future<void> deleteClusterSummary(String clusterID);
  Future<Map<String, (Uint8List, int)>> getAllClusterSummary([
    int? minClusterSize,
  ]);
  Future<Map<String, (Uint8List, int)>> getClusterToClusterSummary(
    Iterable<String> clusterIDs,
  );
  Future<Map<String, String>> getClusterIDToPersonID();
  Future<void> dropClustersAndPersonTable({bool faces});
  Future<void> dropFacesFeedbackTables();
  Future<List<T>> getFileIDsOfPersonID(String personID);
  Future<List<T>> getFileIDsOfClusterID(String clusterID);
  Future<Set<T>> getAllFileIDsOfFaceIDsNotInAnyCluster();
  Future<Set<T>> getAllFilesAssociatedWithAllClusters({
    List<String>? exceptClusters,
  });

  Future<void> updatePetFaceVectorIds(Map<String, int> petFaceIdToVectorId);
  Future<void> updatePetBodyVectorIds(Map<String, int> petBodyIdToVectorId);

  Future<List<EmbeddingVector>> getAllClipVectors();
  Future<Map<int, int>> clipIndexedFileWithVersion();
  Future<int> getClipIndexedFileCount({int minimumMlVersion});
  Future<void> putClip(List<ClipEmbedding> embeddings);
  Future<void> deleteClipEmbeddings(List<T> fileIDs);
  Future<void> deleteClipIndexes();

  Future<Map<int, int>> petIndexedFileIds({int minimumMlVersion});
  Future<int> getPetIndexedFileCount({int minimumMlVersion});
  Future<void> deletePetDataForFiles(List<int> fileIDs);
}
