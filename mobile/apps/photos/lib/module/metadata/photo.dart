import "dart:io";

import "package:logging/logging.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/src/rust/api/metadata_api.dart";

final _logger = Logger("PhotoMetadata");

Future<PhotoMetadata?> tryReadPhotoMetadata(File file) async {
  try {
    return await readPhotoMetadata(filePath: file.path);
  } catch (e, s) {
    _logger.warning("Failed to read photo metadata", e, s);
    return null;
  }
}

extension PhotoMetadataValues on PhotoMetadata {
  ParsedExifDateTime? get creationDateTime {
    final date = captureDateTime;
    if (date == null) return null;
    final timestamp = date.timestampMicros;
    return ParsedExifDateTime(
      timestamp == null
          ? DateTime.parse(date.dateTime)
          : DateTime.fromMicrosecondsSinceEpoch(timestamp.toInt()),
      date.dateTime,
      date.offsetTime,
    );
  }

  Location? get embeddedLocation {
    final value = location;
    return value == null
        ? null
        : Location(latitude: value.latitude, longitude: value.longitude);
  }
}
