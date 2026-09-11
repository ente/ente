import "dart:convert";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/metadata/asset_date_times.dart";
import "package:photos/module/metadata/exif.dart";

EnteFile fileFromAsset(String deviceFolder, AssetEntity asset) {
  final resolvedDateTimes = resolveAssetDateTimes(asset);
  final file = EnteFile()
    ..localID = asset.id
    ..title = asset.title
    ..deviceFolder = deviceFolder
    ..location = Location(latitude: asset.latitude, longitude: asset.longitude)
    ..fileType = fileTypeFromAsset(asset)
    ..creationTime = resolvedDateTimes.creationTime
    ..modificationTime = resolvedDateTimes.modificationTime
    ..fileSubType = asset.subtype
    ..metadataVersion = -1;
  applyDisplayDimensions(file, asset.orientatedWidth, asset.orientatedHeight);
  return file;
}

void applyDisplayDimensions(EnteFile file, int width, int height) {
  if (width <= 0 || height <= 0) return;
  file.pubMmdEncodedJson = jsonEncode({
    ...jsonDecode(file.pubMmdEncodedJson ?? '{}') as Map<String, dynamic>,
    widthKey: width,
    heightKey: height,
  });
}

void applyMediaTypeMetadata(
  EnteFile file,
  bool isPanorama,
  int? motionVideoIndex,
) {
  file.pubMmdEncodedJson = jsonEncode({
    ...jsonDecode(file.pubMmdEncodedJson ?? '{}') as Map<String, dynamic>,
    mediaTypeKey: isPanorama ? 1 : 0,
    motionVideoIndexKey: motionVideoIndex,
  });
}

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
      // Filename dates often omit the time; keep photo_manager's timestamp
      // when both values fall on the same day.
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
