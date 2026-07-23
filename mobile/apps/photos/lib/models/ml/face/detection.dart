import "dart:math" show min, max;

import "package:photos/models/ml/face/box.dart";
import "package:photos/models/ml/face/landmark.dart";
import "package:photos/services/machine_learning/face_ml/face_detection/detection.dart";

/// Stores the face detection data, notably the bounding box and landmarks.
///
/// - Bounding box: [FaceBox] with x, y (minimum, so top left corner), width, height
/// - Landmarks: list of [Landmark]s, namely leftEye, rightEye, nose, leftMouth, rightMouth
///
/// WARNING: All coordinates are relative to the image size, so in the range [0, 1]!
class Detection {
  FaceBox box;
  List<Landmark> landmarks;

  Detection({required this.box, required this.landmarks});

  bool get isEmpty => box.width == 0 && box.height == 0 && landmarks.isEmpty;

  // empty box
  Detection.empty()
    : box = const FaceBox(x: 0, y: 0, width: 0, height: 0),
      landmarks = [];

  Map<String, dynamic> toJson() => {
    'box': box.toJson(),
    'landmarks': landmarks.map((x) => x.toJson()).toList(),
  };

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      box: FaceBox.fromJson(json['box'] as Map<String, dynamic>),
      landmarks: List<Landmark>.from(
        json['landmarks'].map(
          (x) => Landmark.fromJson(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  FaceDirection getFaceDirection() {
    if (isEmpty) {
      return FaceDirection.straight;
    }
    final leftEye = [landmarks[0].x, landmarks[0].y];
    final rightEye = [landmarks[1].x, landmarks[1].y];
    final nose = [landmarks[2].x, landmarks[2].y];
    final leftMouth = [landmarks[3].x, landmarks[3].y];
    final rightMouth = [landmarks[4].x, landmarks[4].y];

    final double eyeDistanceX = (rightEye[0] - leftEye[0]).abs();
    final double eyeDistanceY = (rightEye[1] - leftEye[1]).abs();
    final double mouthDistanceY = (rightMouth[1] - leftMouth[1]).abs();

    final bool faceIsUpright =
        (max(leftEye[1], rightEye[1]) + 0.5 * eyeDistanceY < nose[1]) &&
        (nose[1] + 0.5 * mouthDistanceY < min(leftMouth[1], rightMouth[1]));

    final bool noseStickingOutLeft =
        (nose[0] < min(leftEye[0], rightEye[0])) &&
        (nose[0] < min(leftMouth[0], rightMouth[0]));
    final bool noseStickingOutRight =
        (nose[0] > max(leftEye[0], rightEye[0])) &&
        (nose[0] > max(leftMouth[0], rightMouth[0]));

    final bool noseCloseToLeftEye =
        (nose[0] - leftEye[0]).abs() < 0.2 * eyeDistanceX;
    final bool noseCloseToRightEye =
        (nose[0] - rightEye[0]).abs() < 0.2 * eyeDistanceX;

    // if (faceIsUpright && (noseStickingOutLeft || noseCloseToLeftEye)) {
    if (noseStickingOutLeft || (faceIsUpright && noseCloseToLeftEye)) {
      return FaceDirection.left;
      // } else if (faceIsUpright && (noseStickingOutRight || noseCloseToRightEye)) {
    } else if (noseStickingOutRight || (faceIsUpright && noseCloseToRightEye)) {
      return FaceDirection.right;
    }

    return FaceDirection.straight;
  }

  bool faceIsSideways() {
    if (isEmpty) {
      return false;
    }
    final leftEye = [landmarks[0].x, landmarks[0].y];
    final rightEye = [landmarks[1].x, landmarks[1].y];
    final nose = [landmarks[2].x, landmarks[2].y];
    final leftMouth = [landmarks[3].x, landmarks[3].y];
    final rightMouth = [landmarks[4].x, landmarks[4].y];

    final double eyeDistanceX = (rightEye[0] - leftEye[0]).abs();
    final double eyeDistanceY = (rightEye[1] - leftEye[1]).abs();
    final double mouthDistanceY = (rightMouth[1] - leftMouth[1]).abs();

    final bool faceIsUpright =
        (max(leftEye[1], rightEye[1]) + 0.5 * eyeDistanceY < nose[1]) &&
        (nose[1] + 0.5 * mouthDistanceY < min(leftMouth[1], rightMouth[1]));

    final bool noseStickingOutLeft =
        (nose[0] < min(leftEye[0], rightEye[0]) - 0.5 * eyeDistanceX) &&
        (nose[0] < min(leftMouth[0], rightMouth[0]));
    final bool noseStickingOutRight =
        (nose[0] > max(leftEye[0], rightEye[0]) + 0.5 * eyeDistanceX) &&
        (nose[0] > max(leftMouth[0], rightMouth[0]));

    return faceIsUpright && (noseStickingOutLeft || noseStickingOutRight);
  }
}
