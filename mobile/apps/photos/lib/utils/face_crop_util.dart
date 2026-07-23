import 'dart:math' show min;

import 'package:photos/models/ml/face/box.dart';
import 'package:photos/models/ml/face/face.dart';

const double _regularPadding = 0.4;
const double _minimumPadding = 0.1;

FaceBox resolveLaneFaceBox(String faceID, {List<Face>? faces}) {
  if (faces != null) {
    for (final face in faces) {
      if (face.faceID == faceID) {
        return face.detection.box;
      }
    }
  }
  return parseFaceBoxFromFaceID(faceID);
}

FaceBox parseFaceBoxFromFaceID(String faceID) {
  try {
    final parts = faceID.split('_');
    if (parts.length < 5) {
      return const FaceBox(x: 0, y: 0, width: 1, height: 1);
    }

    final xMin = int.parse(parts[1]) / 100000.0;
    final yMin = int.parse(parts[2]) / 100000.0;
    final xMax = int.parse(parts[3]) / 100000.0;
    final yMax = int.parse(parts[4]) / 100000.0;
    final width = (xMax - xMin).clamp(0.00001, 1.0);
    final height = (yMax - yMin).clamp(0.00001, 1.0);
    final x = xMin.clamp(0.0, 1.0);
    final y = yMin.clamp(0.0, 1.0);

    return FaceBox(x: x, y: y, width: width, height: height);
  } catch (_) {
    return const FaceBox(x: 0, y: 0, width: 1, height: 1);
  }
}

FaceBox computePaddedFaceCropBox(FaceBox faceBox) {
  if (faceBox.width <= 0 || faceBox.height <= 0) {
    return const FaceBox(x: 0, y: 0, width: 1, height: 1);
  }

  final xCrop = faceBox.x - faceBox.width * _regularPadding;
  final xOvershoot = min(0.0, xCrop).abs() / faceBox.width;
  final widthCrop =
      faceBox.width * (1 + 2 * _regularPadding) -
      2 * min(xOvershoot, _regularPadding - _minimumPadding) * faceBox.width;

  final yCrop = faceBox.y - faceBox.height * _regularPadding;
  final yOvershoot = min(0.0, yCrop).abs() / faceBox.height;
  final heightCrop =
      faceBox.height * (1 + 2 * _regularPadding) -
      2 * min(yOvershoot, _regularPadding - _minimumPadding) * faceBox.height;

  final xCropSafe = xCrop.clamp(0.0, 1.0);
  final yCropSafe = yCrop.clamp(0.0, 1.0);
  final widthCropSafe = widthCrop.clamp(0.0, 1.0 - xCropSafe);
  final heightCropSafe = heightCrop.clamp(0.0, 1.0 - yCropSafe);

  return FaceBox(
    x: xCropSafe,
    y: yCropSafe,
    width: widthCropSafe,
    height: heightCropSafe,
  );
}
