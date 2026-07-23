import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/models/ml/face/detection.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/ml_result.dart";

class FaceWithoutEmbedding {
  final String faceID;
  final int fileID;
  Detection detection;
  final double score;
  final double blur;

  bool get isBlurry => blur < kLaplacianHardThreshold;

  bool get hasHighScore => score > kMinimumQualityFaceScore;

  bool get isHighQuality => (!isBlurry) && hasHighScore;

  FaceWithoutEmbedding(
    this.faceID,
    this.fileID,
    this.score,
    this.detection,
    this.blur,
  );

  factory FaceWithoutEmbedding.fromJson(Map<String, dynamic> json) {
    final String faceID = json['faceID'] as String;
    final int fileID = getFileIdFromFaceId<int>(faceID);
    return FaceWithoutEmbedding(
      faceID,
      fileID,
      parseIntOrDoubleAsDouble(json['score'])!,
      Detection.fromJson(json['detection'] as Map<String, dynamic>),
      // high value means t
      parseIntOrDoubleAsDouble(json['blur']) ?? kLapacianDefault,
    );
  }

  // Note: Keep the information in toJson minimum. Keep in sync with desktop.
  // Derive fields like fileID from other values whenever possible
  Map<String, dynamic> toJson() => {
    'faceID': faceID,
    'detection': detection.toJson(),
    'score': score,
    'blur': blur,
  };
}
