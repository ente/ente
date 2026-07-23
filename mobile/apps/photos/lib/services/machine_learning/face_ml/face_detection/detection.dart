import 'dart:math' show max, min;

import "package:photos/models/ml/face/dimension.dart";

enum FaceDirection { left, right, straight }

extension FaceDirectionExtension on FaceDirection {
  String toDirectionString() {
    switch (this) {
      case FaceDirection.left:
        return 'Left';
      case FaceDirection.right:
        return 'Right';
      case FaceDirection.straight:
        return 'Straight';
    }
  }
}

abstract class Detection {
  final double score;

  Detection({required this.score});

  const Detection.empty() : score = 0;

  double get width;
  double get height;

  @override
  String toString();
}

/// This class represents a face detection with relative coordinates in the range [0, 1].
/// The coordinates are relative to the image size. The pattern for the coordinates is always [x, y], where x is the horizontal coordinate and y is the vertical coordinate.
///
/// The [score] attribute is a double representing the confidence of the face detection.
///
/// The [box] attribute is a list of 4 doubles, representing the coordinates of the bounding box of the face detection.
/// The four values of the box in order are: [xMinBox, yMinBox, xMaxBox, yMaxBox].
///
/// The [allKeypoints] attribute is a list of 6 lists of 2 doubles, representing the coordinates of the keypoints of the face detection.
/// The six lists of two values in order are: [leftEye, rightEye, nose, mouth, leftEar, rightEar]. Again, all in [x, y] order.
class FaceDetectionRelative extends Detection {
  final List<double> box;
  final List<List<double>> allKeypoints;

  double get xMinBox => box[0];
  double get yMinBox => box[1];
  double get xMaxBox => box[2];
  double get yMaxBox => box[3];

  List<double> get leftEye => allKeypoints[0];
  List<double> get rightEye => allKeypoints[1];
  List<double> get nose => allKeypoints[2];
  List<double> get leftMouth => allKeypoints[3];
  List<double> get rightMouth => allKeypoints[4];

  FaceDetectionRelative({
    required super.score,
    required List<double> box,
    required List<List<double>> allKeypoints,
  }) : assert(
         box.every((e) => e >= -0.1 && e <= 1.1),
         "Bounding box values must be in the range [0, 1], with only a small margin of error allowed.",
       ),
       assert(
         allKeypoints.every(
           (sublist) => sublist.every((e) => e >= -0.1 && e <= 1.1),
         ),
         "All keypoints must be in the range [0, 1], with only a small margin of error allowed.",
       ),
       box = List<double>.from(box.map((e) => e.clamp(0.0, 1.0))),
       allKeypoints = allKeypoints
           .map(
             (sublist) =>
                 List<double>.from(sublist.map((e) => e.clamp(0.0, 1.0))),
           )
           .toList();

  void correctForMaintainedAspectRatio(
    Dimensions originalSize,
    Dimensions newSize,
  ) {
    // Return if both are the same size, meaning no scaling was done on both width and height
    if (originalSize == newSize) {
      return;
    }

    // Calculate the scaling
    final double scaleX = originalSize.width / newSize.width;
    final double scaleY = originalSize.height / newSize.height;
    const double translateX = 0;
    const double translateY = 0;

    // Transform Box
    _transformBox(box, scaleX, scaleY, translateX, translateY);

    // Transform All Keypoints
    for (int i = 0; i < allKeypoints.length; i++) {
      allKeypoints[i] = _transformPoint(
        allKeypoints[i],
        scaleX,
        scaleY,
        translateX,
        translateY,
      );
    }
  }

  void _transformBox(
    List<double> box,
    double scaleX,
    double scaleY,
    double translateX,
    double translateY,
  ) {
    box[0] = ((box[0] + translateX) * scaleX).clamp(0.0, 1.0);
    box[1] = ((box[1] + translateY) * scaleY).clamp(0.0, 1.0);
    box[2] = ((box[2] + translateX) * scaleX).clamp(0.0, 1.0);
    box[3] = ((box[3] + translateY) * scaleY).clamp(0.0, 1.0);
  }

  List<double> _transformPoint(
    List<double> point,
    double scaleX,
    double scaleY,
    double translateX,
    double translateY,
  ) {
    return [
      ((point[0] + translateX) * scaleX).clamp(0.0, 1.0),
      ((point[1] + translateY) * scaleY).clamp(0.0, 1.0),
    ];
  }

  FaceDetectionAbsolute toAbsolute({
    required int imageWidth,
    required int imageHeight,
  }) {
    final scoreCopy = score;
    final boxCopy = List<double>.from(box, growable: false);
    final allKeypointsCopy = allKeypoints
        .map((sublist) => List<double>.from(sublist, growable: false))
        .toList();

    boxCopy[0] *= imageWidth;
    boxCopy[1] *= imageHeight;
    boxCopy[2] *= imageWidth;
    boxCopy[3] *= imageHeight;
    // final intbox = boxCopy.map((e) => e.toInt()).toList();

    for (List<double> keypoint in allKeypointsCopy) {
      keypoint[0] *= imageWidth;
      keypoint[1] *= imageHeight;
    }
    // final intKeypoints =
    //     allKeypointsCopy.map((e) => e.map((e) => e.toInt()).toList()).toList();
    return FaceDetectionAbsolute(
      score: scoreCopy,
      box: boxCopy,
      allKeypoints: allKeypointsCopy,
    );
  }

  String toFaceID({required int fileID}) {
    // Assert that the values are within the expected range
    assert(
      (xMinBox >= 0 && xMinBox <= 1) &&
          (yMinBox >= 0 && yMinBox <= 1) &&
          (xMaxBox >= 0 && xMaxBox <= 1) &&
          (yMaxBox >= 0 && yMaxBox <= 1),
      "Bounding box values must be in the range [0, 1]",
    );

    // Extract bounding box values
    final String xMin = xMinBox
        .clamp(0.0, 0.999999)
        .toStringAsFixed(5)
        .substring(2);
    final String yMin = yMinBox
        .clamp(0.0, 0.999999)
        .toStringAsFixed(5)
        .substring(2);
    final String xMax = xMaxBox
        .clamp(0.0, 0.999999)
        .toStringAsFixed(5)
        .substring(2);
    final String yMax = yMaxBox
        .clamp(0.0, 0.999999)
        .toStringAsFixed(5)
        .substring(2);

    // Convert the bounding box values to string and concatenate
    final String rawID = "${xMin}_${yMin}_${xMax}_$yMax";

    final faceID = fileID.toString() + '_' + rawID.toString();

    // Return the hexadecimal representation of the hash
    return faceID;
  }

  @override
  String toString() {
    return 'FaceDetectionRelative( with relative coordinates: \n score: $score \n Box: xMinBox: $xMinBox, yMinBox: $yMinBox, xMaxBox: $xMaxBox, yMaxBox: $yMaxBox, \n Keypoints: leftEye: $leftEye, rightEye: $rightEye, nose: $nose, leftMouth: $leftMouth, rightMouth: $rightMouth \n )';
  }

  Map<String, dynamic> toJson() {
    return {'score': score, 'box': box, 'allKeypoints': allKeypoints};
  }

  factory FaceDetectionRelative.fromJson(Map<String, dynamic> json) {
    return FaceDetectionRelative(
      score: (json['score'] as num).toDouble(),
      box: List<double>.from(json['box']),
      allKeypoints: (json['allKeypoints'] as List)
          .map((item) => List<double>.from(item))
          .toList(),
    );
  }

  @override
  /// The width of the bounding box of the face detection, in relative range [0, 1].
  double get width => xMaxBox - xMinBox;

  @override
  /// The height of the bounding box of the face detection, in relative range [0, 1].
  double get height => yMaxBox - yMinBox;
}

/// This class represents a face detection with absolute coordinates in pixels, in the range [0, imageWidth] for the horizontal coordinates and [0, imageHeight] for the vertical coordinates.
/// The pattern for the coordinates is always [x, y], where x is the horizontal coordinate and y is the vertical coordinate.
///
/// The [score] attribute is a double representing the confidence of the face detection.
///
/// The [box] attribute is a list of 4 integers, representing the coordinates of the bounding box of the face detection.
/// The four values of the box in order are: [xMinBox, yMinBox, xMaxBox, yMaxBox].
///
/// The [allKeypoints] attribute is a list of 6 lists of 2 integers, representing the coordinates of the keypoints of the face detection.
/// The six lists of two values in order are: [leftEye, rightEye, nose, mouth, leftEar, rightEar]. Again, all in [x, y] order.
class FaceDetectionAbsolute extends Detection {
  final List<double> box;
  final List<List<double>> allKeypoints;

  double get xMinBox => box[0];
  double get yMinBox => box[1];
  double get xMaxBox => box[2];
  double get yMaxBox => box[3];

  List<double> get leftEye => allKeypoints[0];
  List<double> get rightEye => allKeypoints[1];
  List<double> get nose => allKeypoints[2];
  List<double> get leftMouth => allKeypoints[3];
  List<double> get rightMouth => allKeypoints[4];

  FaceDetectionAbsolute({
    required super.score,
    required this.box,
    required this.allKeypoints,
  });

  @override
  String toString() {
    return 'FaceDetectionAbsolute( with absolute coordinates: \n score: $score \n Box: xMinBox: $xMinBox, yMinBox: $yMinBox, xMaxBox: $xMaxBox, yMaxBox: $yMaxBox, \n Keypoints: leftEye: $leftEye, rightEye: $rightEye, nose: $nose, leftMouth: $leftMouth, rightMouth: $rightMouth \n )';
  }

  @override
  /// The width of the bounding box of the face detection, in number of pixels, range [0, imageWidth].
  double get width => xMaxBox - xMinBox;
  @override
  /// The height of the bounding box of the face detection, in number of pixels, range [0, imageHeight].
  double get height => yMaxBox - yMinBox;

  FaceDirection getFaceDirection() {
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
}

List<FaceDetectionAbsolute> relativeToAbsoluteDetections({
  required List<FaceDetectionRelative> relativeDetections,
  required int imageWidth,
  required int imageHeight,
}) {
  final absoluteDetections = <FaceDetectionAbsolute>[];
  for (var i = 0; i < relativeDetections.length; i++) {
    final absoluteDetection = relativeDetections[i].toAbsolute(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    absoluteDetections.add(absoluteDetection);
  }
  return absoluteDetections;
}
