import "dart:io";
import "dart:math";
import "dart:typed_data";
import "dart:ui";

import "package:image/image.dart" as img;
import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/file.dart";
import "package:pro_image_editor/pro_image_editor.dart";

final _logger = Logger("lossless_edits");

const _flipXOrientation = [0, 2, 1, 4, 3, 8, 7, 6, 5];
const _flipYOrientation = [0, 4, 3, 2, 1, 6, 5, 8, 7];
const _rotateCwOrientation = [0, 6, 5, 8, 7, 4, 3, 2, 1];

typedef LosslessEditTransform = ({bool flipX, bool flipY, int turns});

Future<Uint8List?> tryTransformFileLossless(
  EnteFile src,
  LosslessEditTransform transform,
) async {
  try {
    return await _transformFileLossless(src, transform);
  } catch (e, s) {
    _logger.warning("Failed to transform file losslessly", e, s);
    return null;
  }
}

bool _isJpegFile(Uint8List bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
}

Future<Uint8List> _transformFileLossless(
  EnteFile src,
  LosslessEditTransform transform,
) async {
  File? f;
  try {
    f = await getFile(src, isOrigin: true);
    if (f == null) {
      throw Exception("Failed to get file");
    }
    final bytes = await f.readAsBytes();
    final exif = _isJpegFile(bytes)
        ? img.decodeJpgExif(bytes) ?? img.ExifData()
        : null;
    if (exif == null) {
      throw Exception("Failed to decode JPEG EXIF");
    }
    _applyTransformToExif(exif, transform);
    final out = img.injectJpgExif(bytes, exif);
    if (out == null) {
      throw Exception("Failed to inject JPEG EXIF");
    }
    return out;
  } finally {
    if (f != null && !src.isRemoteOnlyFile && Platform.isIOS) {
      f.delete().ignore();
    }
  }
}

void _applyTransformToExif(img.ExifData exif, LosslessEditTransform transform) {
  var orientation = exif.imageIfd.orientation ?? 1;
  if (orientation < 1 || orientation > 8) {
    throw Exception("Unsupported EXIF orientation");
  }

  if (transform.flipX) orientation = _flipXOrientation[orientation];
  if (transform.flipY) orientation = _flipYOrientation[orientation];
  for (var i = 0; i < (transform.turns % 4 + 4) % 4; i++) {
    orientation = _rotateCwOrientation[orientation];
  }
  exif.imageIfd.orientation = orientation;
}

bool isTransformOnlyLossless(TransformConfigs t) {
  final fullImageRect = Rect.fromLTWH(
    0,
    0,
    t.originalSize.width,
    t.originalSize.height,
  );

  final isLosslessTransformOnly =
      t.originalSize.width.isFinite &&
      t.originalSize.height.isFinite &&
      t.cropRect.left.isFinite &&
      t.cropRect.top.isFinite &&
      t.cropRect.right.isFinite &&
      t.cropRect.bottom.isFinite &&
      (t.angle != 0 || t.flipX || t.flipY) &&
      t.isRectangularCropper &&
      _isSameRect(t.cropRect, fullImageRect) &&
      _isSameDouble(t.scaleUser, 1) &&
      t.aspectRatio == -1 &&
      _isSameOffset(t.offset, Offset.zero);

  return isLosslessTransformOnly;
}

LosslessEditTransform? getLosslessTransform(ProImageEditorState editorState) {
  final stateManager = editorState.stateManager;

  if (stateManager.activeLayers.isNotEmpty) {
    return null;
  }

  final blur = stateManager.activeBlur;
  final filters = stateManager.activeFilters;
  final tuneAdjustments = stateManager.activeTuneAdjustments;
  final transformConfigs = stateManager.transformConfigs;

  if (blur != 0.0 || filters.isNotEmpty || tuneAdjustments.isNotEmpty) {
    return null;
  }

  if (!isTransformOnlyLossless(transformConfigs)) return null;

  const quarterTurn = pi / 2;
  final rotations = transformConfigs.angle / quarterTurn;

  if (rotations != rotations.roundToDouble()) {
    return null;
  }

  final transform = (
    turns: rotations.toInt(),
    flipX: transformConfigs.flipX,
    flipY: transformConfigs.flipY,
  );
  if (transform.turns == 0 && !transform.flipX && !transform.flipY) {
    return null;
  }

  return transform;
}

bool _isSameDouble(double a, double b) {
  return (a - b).abs() < 0.001;
}

bool _isSameOffset(Offset a, Offset b) {
  return _isSameDouble(a.dx, b.dx) && _isSameDouble(a.dy, b.dy);
}

bool _isSameRect(Rect a, Rect b) {
  return _isSameDouble(a.left, b.left) &&
      _isSameDouble(a.top, b.top) &&
      _isSameDouble(a.right, b.right) &&
      _isSameDouble(a.bottom, b.bottom);
}
