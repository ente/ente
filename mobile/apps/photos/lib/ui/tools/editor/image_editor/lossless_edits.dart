import "dart:io";
import "dart:math";
import "dart:typed_data";
import "dart:ui";

import "package:exif_reader/exif_reader.dart";
import "package:image/image.dart" as img;
import "package:photos/models/file/file.dart";
import "package:photos/utils/exif_util.dart";
import "package:photos/utils/file_util.dart";
import "package:pro_image_editor/pro_image_editor.dart";

bool isTransformOnlyRotation(TransformConfigs t) {
  final fullImageRect = Rect.fromLTWH(
    0,
    0,
    t.originalSize.width,
    t.originalSize.height,
  );

  final isRotationOnly =
      t.originalSize.width.isFinite &&
      t.originalSize.height.isFinite &&
      t.cropRect.left.isFinite &&
      t.cropRect.top.isFinite &&
      t.cropRect.right.isFinite &&
      t.cropRect.bottom.isFinite &&
      t.angle != 0 &&
      t.cropRect == fullImageRect &&
      t.scaleUser == 1 &&
      t.aspectRatio == -1 &&
      t.flipX == false &&
      t.flipY == false &&
      t.offset == Offset.zero;

  if (!isRotationOnly) {
    print(
      "[aspizu] lossless rotation transform rejected: "
      "originalSize=${t.originalSize}, cropRect=${t.cropRect}, "
      "fullImageRect=$fullImageRect, angle=${t.angle}, "
      "scaleUser=${t.scaleUser}, scaleRotation=${t.scaleRotation}, "
      "aspectRatio=${t.aspectRatio}, flipX=${t.flipX}, flipY=${t.flipY}, "
      "offset=${t.offset}",
    );
  }

  return isRotationOnly;
}

int? getTurnsIfOnlyRotated(ProImageEditorState editorState) {
  if (editorState.activeLayers.isNotEmpty) {
    print(
      "[aspizu] lossless rotation skipped: "
      "editor has ${editorState.activeLayers.length} layers",
    );
    return null;
  }

  final blur =
      editorState.stateHistory.lastWhere((e) => e.blur != null).blur ?? 0.0;

  final filters = editorState.stateHistory
      .lastWhere(
        (e) => e.filters.isNotEmpty,
        orElse: () => EditorStateHistory(),
      )
      .filters;

  final tuneAdjustments = editorState.stateHistory
      .lastWhere(
        (e) => e.tuneAdjustments.isNotEmpty,
        orElse: () => EditorStateHistory(),
      )
      .tuneAdjustments;

  final transformConfigs =
      editorState.stateHistory
          .lastWhere(
            (e) => e.transformConfigs != null,
            orElse: () => EditorStateHistory(),
          )
          .transformConfigs ??
      TransformConfigs.empty();

  if (blur != 0.0 || filters.isNotEmpty || tuneAdjustments.isNotEmpty) {
    print(
      "[aspizu] lossless rotation skipped: "
      "blur=$blur, filters=${filters.length}, "
      "tuneAdjustments=${tuneAdjustments.length}",
    );
    return null;
  }

  if (!isTransformOnlyRotation(transformConfigs)) return null;

  const quarterTurn = pi / 2;
  final rotations = transformConfigs.angle / quarterTurn;

  if (rotations != rotations.roundToDouble()) {
    print(
      "[aspizu] lossless rotation skipped: "
      "angle is not quarter turn, angle=${transformConfigs.angle}, "
      "rotations=$rotations",
    );
    return null;
  }

  return rotations.toInt();
}

void clearEditorExifTags(img.ExifData exif) {
  final imageIfdKeys = [
    "Orientation",
    "WhitePoint",
    "PrimaryChromaticities",
    "PhotometricInterpretation",
    "BitsPerSample",
    "SamplesPerPixel",
    "Compression",
    "ImageWidth",
    "ImageHeight",
    "YCbCrPositioning",
    "YCbCrSubSampling",
    "YCbCrCoefficients",
    "ReferenceBlackWhite",
    "XResolution",
    "YResolution",
    "ResolutionUnit",
  ];
  final thumbnailIfdKeys = [
    "JPEGInterchangeFormat",
    "JPEGInterchangeFormatLength",
  ];
  final exifIfdKeys = [
    "ColorSpace",
    "Gamma",
    "ExifImageWidth",
    "ExifImageHeight",
    "ExifImageLength",
    "ComponentsConfiguration",
    "CustomRendered",
    "SceneCaptureType",
    "WhiteBalance",
    "LightSource",
    "Flash",
    "GainControl",
    "Contrast",
    "Saturation",
    "Sharpness",
    "SubjectDistanceRange",
  ];

  void clear(img.IfdDirectory ifd, List<String> keys) {
    for (final key in keys) {
      ifd[key] = null;
    }
  }

  clear(exif.imageIfd, imageIfdKeys);
  clear(exif.thumbnailIfd, thumbnailIfdKeys);
  clear(exif.exifIfd, exifIfdKeys);
}

void copyCameraExif(Map<String, IfdTag> tags, img.ExifData exif) {
  for (final entry in {"Image Make": "Make", "Image Model": "Model"}.entries) {
    final value = tags[entry.key]?.toString();
    if (value != null) {
      exif.imageIfd[entry.value] = value;
    }
  }

  for (final entry in {
    "EXIF FocalLength": "FocalLength",
    "EXIF FNumber": "FNumber",
    "EXIF ExposureTime": "ExposureTime",
  }.entries) {
    final value = tags[entry.key]?.values.toList().firstOrNull;
    if (value is Ratio) {
      exif.exifIfd[entry.value] = img.IfdValueRational(
        value.numerator,
        value.denominator,
      );
    }
  }

  final iso = tags["EXIF ISOSpeedRatings"]?.values;
  if (iso != null && iso.length > 0) {
    exif.exifIfd["ISOSpeed"] = iso.firstAsInt();
  }
}

void applyRotationTurnsToExifOrientation(
  img.ExifData exif,
  int turns, {
  int? originalOrientation,
}) {
  final originalTurns = _orientationToTurns(originalOrientation);
  final updatedTurns = (originalTurns + turns) % 4;
  final updatedOrientation = _turnsToOrientation(updatedTurns);
  print(
    "[aspizu] lossless rotation exif orientation: "
    "$originalOrientation -> $updatedOrientation, turns: $turns",
  );
  exif.imageIfd.orientation = updatedOrientation;
}

int _orientationToTurns(int? orientation) {
  return switch (orientation) {
    6 => 1,
    3 => 2,
    8 => 3,
    _ => 0,
  };
}

int _turnsToOrientation(int turns) {
  return switch (turns % 4) {
    1 => 6,
    2 => 3,
    3 => 8,
    _ => 1,
  };
}

Future<Uint8List?> tryRotateFileLossless(EnteFile file, int turns) async {
  File? f;
  try {
    print("[aspizu] trying lossless rotation, turns: $turns");
    f = await getFile(file, isOrigin: true);
    if (f == null) {
      print("[aspizu] lossless rotation failed: original file is null");
      return null;
    }
    final bytes = await f.readAsBytes();
    final exif = img.decodeJpgExif(bytes);
    if (exif == null) {
      print("[aspizu] lossless rotation failed: could not decode jpeg exif");
      return null;
    }
    final originalOrientation = exif.imageIfd.orientation;
    clearEditorExifTags(exif);
    copyCameraExif(await getExif(file), exif);
    applyRotationTurnsToExifOrientation(
      exif,
      turns,
      originalOrientation: originalOrientation,
    );
    final result = img.injectJpgExif(bytes, exif);
    if (result == null) {
      print("[aspizu] lossless rotation failed to inject exif");
    } else {
      print(
        "[aspizu] lossless rotation produced bytes: "
        "input=${bytes.length}, output=${result.length}",
      );
    }
    return result;
  } catch (e, s) {
    print("[aspizu] lossless rotation failed with error: $e\n$s");
    rethrow;
  } finally {
    if (!file.isRemoteOnlyFile && Platform.isIOS && f != null) {
      print("[aspizu] lossless rotation deleting temp original file");
      try {
        await f.delete();
        print("[aspizu] lossless rotation deleted temp original file");
      } on PathNotFoundException {
        print("[aspizu] lossless rotation cleanup skipped: temp file missing");
      }
    } else {
      print(
        "[aspizu] lossless rotation cleanup skipped: "
        "isRemoteOnly=${file.isRemoteOnlyFile}, "
        "isIOS=${Platform.isIOS}, fileIsNull=${f == null}",
      );
    }
  }
}
