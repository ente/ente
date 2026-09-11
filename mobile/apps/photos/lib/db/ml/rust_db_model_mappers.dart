import "dart:convert";
import "dart:typed_data";

import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/detection.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;

rust.FaceRow toFaceRow(Face face) {
  return rust.FaceRow(
    fileId: face.fileID,
    faceId: face.faceID,
    detectionJson: json.encode(face.detection.toJson()),
    embedding: Float64List.fromList(face.embedding),
    score: face.score,
    blur: face.blur,
    isSideways: face.detection.faceIsSideways(),
    imageHeight: face.fileInfo?.imageHeight ?? 0,
    imageWidth: face.fileInfo?.imageWidth ?? 0,
    mlVersion: faceMlVersion,
  );
}

Face toFace(rust.FaceRow row) {
  return Face(
    row.faceId,
    row.fileId,
    row.embedding,
    row.score,
    Detection.fromJson(json.decode(row.detectionJson) as Map<String, dynamic>),
    row.blur,
    fileInfo: FileInfo(
      imageWidth: row.imageWidth,
      imageHeight: row.imageHeight,
    ),
  );
}

FaceWithoutEmbedding toFaceWithoutEmbedding(rust.FaceWithoutEmbedding row) {
  return FaceWithoutEmbedding(
    row.faceId,
    row.fileId,
    row.score,
    Detection.fromJson(json.decode(row.detectionJson) as Map<String, dynamic>),
    row.blur,
  );
}

FaceDbInfoForClustering toFaceDbInfoForClustering(
  rust.FaceDbInfoForClustering row,
) {
  return FaceDbInfoForClustering(
    faceID: row.faceId,
    clusterId: row.clusterId,
    embeddingBytes: row.embeddingBytes,
    faceScore: row.faceScore,
    blurValue: row.blurValue,
    isSideways: row.isSideways,
  );
}

rust.PetFaceRow toPetFaceRow(DBPetFace petFace) {
  return rust.PetFaceRow(
    fileId: petFace.fileId,
    petFaceId: petFace.petFaceId,
    detectionJson: petFace.detection,
    faceVectorId: petFace.faceVectorId,
    species: petFace.species,
    faceScore: petFace.faceScore,
    imageHeight: petFace.imageHeight,
    imageWidth: petFace.imageWidth,
    mlVersion: petFace.mlVersion,
  );
}

DBPetFace toDBPetFace(rust.PetFaceRow row) {
  return DBPetFace(
    fileId: row.fileId,
    petFaceId: row.petFaceId,
    detection: row.detectionJson,
    faceVectorId: row.faceVectorId,
    species: row.species,
    faceScore: row.faceScore,
    imageHeight: row.imageHeight,
    imageWidth: row.imageWidth,
    mlVersion: row.mlVersion,
  );
}

rust.PetBodyRow toPetBodyRow(DBPetBody petBody) {
  return rust.PetBodyRow(
    fileId: petBody.fileId,
    petBodyId: petBody.petBodyId,
    detectionJson: petBody.detection,
    bodyVectorId: petBody.bodyVectorId,
    species: petBody.species,
    score: petBody.score,
    imageHeight: petBody.imageHeight,
    imageWidth: petBody.imageWidth,
    mlVersion: petBody.mlVersion,
  );
}

DBPetBody toDBPetBody(rust.PetBodyRow row) {
  return DBPetBody(
    fileId: row.fileId,
    petBodyId: row.petBodyId,
    detection: row.detectionJson,
    bodyVectorId: row.bodyVectorId,
    species: row.species,
    score: row.score,
    imageHeight: row.imageHeight,
    imageWidth: row.imageWidth,
    mlVersion: row.mlVersion,
  );
}

rust.ClipEmbedding toClipEmbeddingRow(ClipEmbedding embedding) {
  return rust.ClipEmbedding(
    fileId: embedding.fileID,
    embedding: Float64List.fromList(embedding.embedding),
    version: embedding.version,
  );
}

EmbeddingVector toEmbeddingVector(rust.EmbeddingVector vector) {
  return EmbeddingVector(fileID: vector.fileId, embedding: vector.embedding);
}

rust.ClusterSummary toClusterSummaryRow((Uint8List, int) summary) {
  return rust.ClusterSummary(avg: summary.$1, count: summary.$2);
}

(Uint8List, int) toClusterSummaryRecord(rust.ClusterSummary summary) {
  return (summary.avg, summary.count);
}

rust.FdStatus toFdStatusRow(FDStatus status) {
  return rust.FdStatus(
    fileId: status.fileID,
    userId: status.userID,
    dataType: status.type,
    size: status.size,
    objectId: status.objectID,
    objectNonce: status.objectNonce,
    updatedAt: status.updatedAt,
  );
}

PreviewInfo toPreviewInfo(rust.PreviewInfo info) {
  return PreviewInfo(objectId: info.objectId, objectSize: info.objectSize);
}
