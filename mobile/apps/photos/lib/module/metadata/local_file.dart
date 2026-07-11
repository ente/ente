import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/errors.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";

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
