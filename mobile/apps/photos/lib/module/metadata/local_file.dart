import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/errors.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/metadata/exif.dart";

final _logger = Logger("LocalFileMetadata");

EnteFile fileFromAsset(String deviceFolder, AssetEntity asset) {
  return EnteFile()
    ..localID = asset.id
    ..title = asset.title
    ..deviceFolder = deviceFolder
    ..location = Location(latitude: asset.latitude, longitude: asset.longitude)
    ..fileType = fileTypeFromAsset(asset)
    ..creationTime = _creationTimeFromAsset(asset)
    ..modificationTime = _microsecondsSinceEpoch(
      asset.modifiedDateTime,
      asset,
      "modificationTime",
    )
    ..fileSubType = asset.subtype
    ..metadataVersion = -1;
}

/// Applies creation-time precedence without fetching or decoding more media.
/// Offline import runs this in batches and persists only this derived field.
void applyCreationTimeMetadata(EnteFile file, ParsedExifDateTime? exifTime) {
  final hasExifTime = exifTime != null;
  if (exifTime != null) {
    file.creationTime = exifTime.time.microsecondsSinceEpoch;
  }

  // Try to get the timestamp from fileName. In case of iOS, file names are
  // generic IMG_XXXX, so only parse it on Android devices
  if (!hasExifTime && Platform.isAndroid && file.title != null) {
    final timeFromFileName = parseDateTimeFromFileNameV2(file.title!);
    if (timeFromFileName != null) {
      // only use timeFromFileName if the existing creationTime and
      // timeFromFilename belongs to different date.
      // This is done because many times the fileTimeStamp will only give us
      // the date, not time value but the photo_manager's creation time will
      // contain the time.
      final bool useFileTimeStamp =
          file.creationTime == null ||
          !areFromSameDay(
            file.creationTime!,
            timeFromFileName.microsecondsSinceEpoch,
          );
      if (useFileTimeStamp) {
        file.creationTime = timeFromFileName.microsecondsSinceEpoch;
      }
    }
  }
}

int _creationTimeFromAsset(AssetEntity asset) {
  var creationTime = _microsecondsSinceEpoch(
    asset.createDateTime,
    asset,
    "createDateTime",
  );
  final modificationTime = _microsecondsSinceEpoch(
    asset.modifiedDateTime,
    asset,
    "modificationTime",
  );
  if (creationTime >= jan011981Time) {
    // Copied files can retain an older modification time while gaining a new
    // filesystem creation time. Embedded metadata may replace this on upload.
    if (modificationTime >= jan011981Time && modificationTime < creationTime) {
      _logger.info(
        "LocalID: ${asset.id} modification time is less than creation time. "
        "Using modification time as creation time",
      );
      creationTime = modificationTime;
    }
    return creationTime;
  }

  creationTime = modificationTime >= jan011981Time
      ? modificationTime
      : DateTime.now().toUtc().microsecondsSinceEpoch;
  try {
    final parsedDateTime = parseDateTimeFromFileNameV2(
      basenameWithoutExtension(asset.title ?? ""),
    );
    return parsedDateTime?.microsecondsSinceEpoch ?? creationTime;
  } catch (_) {
    return creationTime;
  }
}

int _microsecondsSinceEpoch(
  DateTime dateTime,
  AssetEntity asset,
  String field,
) {
  try {
    return dateTime.microsecondsSinceEpoch;
  } on RangeError catch (e) {
    throw InvalidDateTimeError(
      assetId: asset.id,
      assetTitle: asset.title,
      field: field,
      originalError: e.message ?? e.toString(),
    );
  }
}
