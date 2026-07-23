import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/models/ml/face/box.dart";
import "package:photos/models/ml/face/detection.dart";
import "package:photos/models/ml/face/dimension.dart";
import "package:photos/models/ml/face/landmark.dart";
import 'package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart';
import "package:photos/services/machine_learning/ml_result.dart";

// FileInfo contains the image width and height of the image the face was detected in.
class FileInfo {
  int? imageWidth;
  int? imageHeight;
  FileInfo({this.imageWidth, this.imageHeight});
}

class Face {
  final String faceID;
  final List<double> embedding;
  Detection detection;
  final double score;
  final double blur;

  ///#region Local DB fields
  // This is not stored on the server, using it for local DB row
  FileInfo? fileInfo;
  final int fileID;

  ///#endregion

  bool get isBlurry => blur < kLaplacianHardThreshold;

  bool get hasHighScore => score > kMinimumQualityFaceScore;

  bool get isHighQuality => (!isBlurry) && hasHighScore;

  Face(
    this.faceID,
    this.fileID,
    this.embedding,
    this.score,
    this.detection,
    this.blur, {
    this.fileInfo,
  });

  factory Face.fromFaceResult(
    FaceResult faceResult,
    int fileID,
    Dimensions decodedDimensions,
  ) {
    final detection = Detection(
      box: FaceBox(
        x: faceResult.detection.xMinBox,
        y: faceResult.detection.yMinBox,
        width: faceResult.detection.width,
        height: faceResult.detection.height,
      ),
      landmarks: faceResult.detection.allKeypoints
          .map((keypoint) => Landmark(x: keypoint[0], y: keypoint[1]))
          .toList(),
    );
    return Face(
      faceResult.faceId,
      fileID,
      faceResult.embedding,
      faceResult.detection.score,
      detection,
      faceResult.blurValue,
      fileInfo: FileInfo(
        imageHeight: decodedDimensions.height,
        imageWidth: decodedDimensions.width,
      ),
    );
  }

  factory Face.empty(int fileID, {bool error = false}) {
    return Face(
      "${fileID}_0_0_0_0",
      fileID,
      <double>[],
      error ? -1.0 : 0.0,
      Detection.empty(),
      0.0,
    );
  }

  factory Face.fromJson(Map<String, dynamic> json) {
    final String faceID = json['faceID'] as String;
    final int fileID = getFileIdFromFaceId<int>(faceID);
    return Face(
      faceID,
      fileID,
      parseAsDoubleList(json['embedding'] as List),
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
    'embedding': embedding,
    'detection': detection.toJson(),
    'score': score,
    'blur': blur,
  };
}
