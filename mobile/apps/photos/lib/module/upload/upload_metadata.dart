import "dart:convert";
import "dart:typed_data";

import "package:ente_crypto/ente_crypto.dart";
import "package:photos/gateways/collections/models/metadata.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/module/metadata/local_file.dart";
import 'package:photos/module/metadata/panorama.dart';
import "package:photos/module/upload/model/media_upload_data.dart";

Future<Map<String, dynamic>> buildUploadMetadata(
  EnteFile file,
  MediaUploadData mediaUploadData,
  ParsedExifDateTime? exifTime,
) async {
  applyCreationTimeMetadata(file, exifTime);
  if (mediaUploadData.exifData != null) {
    mediaUploadData.isPanorama = isPanoramaFromExif(mediaUploadData.exifData);
  }
  if (mediaUploadData.isPanorama != true && file.fileType == FileType.image) {
    try {
      final xmpData = await readXmp(mediaUploadData.sourceFile);
      mediaUploadData.isPanorama = isPanoramaFromXmp(xmpData);
    } catch (_) {}
    mediaUploadData.isPanorama ??= false;
  }
  file.hash = mediaUploadData.hashData.fileHash;
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
