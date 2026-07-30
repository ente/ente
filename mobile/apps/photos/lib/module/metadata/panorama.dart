import "dart:io";

import "package:exif_reader/exif_reader.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/services/file_magic_service.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";

final _logger = Logger('PanoramaUtil');

Future<Map<String, dynamic>> readXmp(File file) =>
    extractXmp(filePath: file.path);

/// Check if the file is a panorama image.
Future<bool> _isPanorama(EnteFile enteFile) async {
  if (enteFile.fileType != FileType.image) {
    return false;
  }
  final file = await getFile(enteFile);
  if (file == null) {
    return false;
  }
  try {
    final xmpData = await readXmp(file);
    if (isPanoramaFromXmp(xmpData)) {
      return true;
    }
  } catch (_) {}

  final exifData = await readExifAsync(file);
  return isPanoramaFromExif(exifData) ?? false;
}

bool? isPanoramaFromExif(Map<String, IfdTag>? exifData) {
  final customRendered = exifData?["EXIF CustomRendered"]?.printable;
  if (customRendered == null) {
    return null;
  }
  return customRendered == "6";
}

bool isPanoramaFromXmp(Map<String, dynamic> xmpData) {
  final projectionType = xmpData["GPano:ProjectionType"];
  return projectionType == "cylindrical" || projectionType == "equirectangular";
}

/// Detects and persists panorama metadata if it has not been checked yet.
Future<void> guardedCheckPanorama(EnteFile file) async {
  if (!file.canEditMetaInfo || file.isPanorama() != null) {
    return;
  }
  _logger.info(
    "Checking panorama for ${file.uploadedFileID ?? file.localID ?? file.generatedID}",
  );
  final isPanorama = await _isPanorama(file);

  // Update the metadata if it is not updated
  if (file.canEditMetaInfo && file.isPanorama() == null) {
    final mediaType =
        (file.pubMagicMetadata?.mediaType ?? 0) | (isPanorama ? 1 : 0);

    FileMagicService.instance
        .updatePublicMagicMetadata([file], {mediaTypeKey: mediaType})
        .ignore();
  }
}
