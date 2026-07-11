import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:ente_crypto/ente_crypto.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/gateways/collections/models/metadata.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/metadata/exif.dart";
import 'package:photos/module/metadata/panorama.dart';
import "package:photos/module/upload/model/media_upload_data.dart";

Future<Map<String, dynamic>> buildUploadMetadata(
  EnteFile file,
  MediaUploadData mediaUploadData,
  ParsedExifDateTime? exifTime,
) async {
  final asset = await file.getAsset;
  // asset can be null for files shared to app
  if (asset != null) {
    file.fileSubType = asset.subtype;
    if (file.fileType == FileType.video) {
      file.duration = asset.duration;
    }
  }
  final hasExifTime = exifTime != null;
  if (exifTime != null) {
    file.creationTime = exifTime.time.microsecondsSinceEpoch;
  }
  if (mediaUploadData.exifData != null) {
    mediaUploadData.isPanorama = isPanoramaFromExif(mediaUploadData.exifData);
  }
  if (mediaUploadData.isPanorama != true &&
      file.fileType == FileType.image &&
      mediaUploadData.sourceFile != null) {
    try {
      final xmpData = await readXmp(mediaUploadData.sourceFile!);
      mediaUploadData.isPanorama = isPanoramaFromXmp(xmpData);
    } catch (_) {}
    mediaUploadData.isPanorama ??= false;
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
  file.hash = mediaUploadData.hashData?.fileHash;
  return file.metadata;
}

Future<MetadataRequest> buildPublicMetadataRequest(
  EnteFile file,
  Map<String, dynamic> newData,
  Uint8List fileKey,
) async {
  final Map<String, dynamic> jsonToUpdate = jsonDecode(
    file.pubMmdEncodedJson ?? '{}',
  );
  newData.forEach((key, value) {
    jsonToUpdate[key] = value;
  });

  // update the local information so that it's reflected on UI
  file.pubMmdEncodedJson = jsonEncode(jsonToUpdate);
  file.pubMagicMetadata = PubMagicMetadata.fromJson(jsonToUpdate);
  final encryptedMMd = await CryptoUtil.encryptChaCha(
    utf8.encode(jsonEncode(jsonToUpdate)),
    fileKey,
  );
  return MetadataRequest(
    version: file.pubMmdVersion == 0 ? 1 : file.pubMmdVersion,
    count: jsonToUpdate.length,
    data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
    header: CryptoUtil.bin2base64(encryptedMMd.header!),
  );
}
