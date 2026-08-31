import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/metadata/asset_date_times.dart";
import "package:photos/module/metadata/exif.dart";

EnteFile fileFromAsset(String deviceFolder, AssetEntity asset) {
  final resolvedDateTimes = resolveAssetDateTimes(asset);
  return EnteFile()
    ..localID = asset.id
    ..title = asset.title
    ..deviceFolder = deviceFolder
    ..location = Location(latitude: asset.latitude, longitude: asset.longitude)
    ..fileType = fileTypeFromAsset(asset)
    ..creationTime = resolvedDateTimes.creationTime
    ..modificationTime = resolvedDateTimes.modificationTime
    ..fileSubType = asset.subtype
    ..metadataVersion = -1;
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
