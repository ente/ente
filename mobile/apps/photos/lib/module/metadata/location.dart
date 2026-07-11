import "dart:io";

import "package:exif_reader/exif_reader.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/module/metadata/video.dart";

/// Adds Android location metadata to [file], preferring valid EXIF data.
Future<void> updateLocationFromEmbeddedMetadata(
  EnteFile file,
  File sourceFile,
  Map<String, IfdTag>? exifData,
) async {
  if (!Platform.isAndroid) {
    return;
  }
  if (exifData != null) {
    final exifLocation = locationFromExif(exifData);
    if (Location.isValidLocation(exifLocation)) {
      file.location = exifLocation;
      return;
    }
  }
  if (!file.hasLocation && file.isVideo) {
    final videoLocation = (await getVideoProps(sourceFile))?.location;
    if (videoLocation != null) {
      file.location = videoLocation;
    }
  }
}
