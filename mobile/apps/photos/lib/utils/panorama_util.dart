import "dart:io";

import "package:exif_reader/exif_reader.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/services/file_magic_service.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";
import "package:photos/utils/file_util.dart";

final _logger = Logger("PanoramaUtil");

Future<Map<String, dynamic>> getXmp(File file) async {
  return extractXmp(filePath: file.path);
}

/// Check if the file is a panorama image.
Future<bool> checkIfPanorama(EnteFile enteFile) async {
  if (enteFile.fileType != FileType.image) {
    return false;
  }
  final file = await getFile(enteFile);
  if (file == null) {
    return false;
  }
  try {
    final xmpData = await getXmp(file);
    if (checkPanoramaFromXMP(xmpData)) {
      return true;
    }
  } catch (_) {}

  final exifData = await readExifAsync(file);
  return checkPanoramaFromEXIF(exifData) ?? false;
}

bool? checkPanoramaFromEXIF(Map<String, IfdTag>? exifData) {
  final element = exifData?["EXIF CustomRendered"];
  if (element?.printable == null) return null;
  return element?.printable == "6";
}

bool checkPanoramaFromXMP(Map<String, dynamic> xmpData) {
  final projectionType = xmpData["GPano:ProjectionType"];
  return projectionType == "cylindrical" || projectionType == "equirectangular";
}

// guardedCheckPanorama() method is used to check if the file is a panorama image.
Future<void> guardedCheckPanorama(EnteFile file) async {
  if (!file.canEditMetaInfo || file.isPanorama() != null) {
    return;
  }
  _logger.info(
    "Checking panorama for ${file.uploadedFileID ?? file.localID ?? file.generatedID}",
  );
  final result = await checkIfPanorama(file);

  // Update the metadata if it is not updated
  if (file.canEditMetaInfo && file.isPanorama() == null) {
    int? mediaType = file.pubMagicMetadata?.mediaType;
    mediaType ??= 0;

    mediaType = mediaType | (result ? 1 : 0);

    FileMagicService.instance
        .updatePublicMagicMetadata([file], {mediaTypeKey: mediaType})
        .ignore();
  }
}
