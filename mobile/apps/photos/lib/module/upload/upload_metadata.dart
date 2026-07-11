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

class PreparedUploadMetadata {
  final Map<String, dynamic> canonicalMetadata;
  final Map<String, dynamic> publicMetadata;

  PreparedUploadMetadata({
    required Map<String, dynamic> canonicalMetadata,
    required Map<String, dynamic> publicMetadata,
  }) : canonicalMetadata = Map.unmodifiable(canonicalMetadata),
       publicMetadata = Map.unmodifiable(publicMetadata);
}

Future<PreparedUploadMetadata> prepareUploadMetadata(
  EnteFile file,
  MediaUploadData mediaUploadData,
  ParsedExifDateTime? exifTime,
) async {
  applyCreationTimeMetadata(file, exifTime);
  final derivedMetadata = mediaUploadData.derivedMetadata;
  bool? isPanorama;
  if (derivedMetadata.exifData != null) {
    isPanorama = isPanoramaFromExif(derivedMetadata.exifData);
  }
  if (isPanorama != true && file.fileType == FileType.image) {
    try {
      final xmpData = await readXmp(mediaUploadData.sourceFile);
      isPanorama = isPanoramaFromXmp(xmpData);
    } catch (_) {}
    isPanorama ??= false;
  }
  file.hash = mediaUploadData.hashData.fileHash;
  return PreparedUploadMetadata(
    canonicalMetadata: file.metadata,
    publicMetadata: _buildPublicMetadata(
      derivedMetadata,
      exifTime,
      isPanorama: isPanorama == true,
      hasThumbnail: mediaUploadData.thumbnail != null,
    ),
  );
}

Map<String, dynamic> _buildPublicMetadata(
  DerivedMediaMetadata derivedMetadata,
  ParsedExifDateTime? exifTime, {
  required bool isPanorama,
  required bool hasThumbnail,
}) {
  final Map<String, dynamic> publicMetadata = {};
  if ((derivedMetadata.height ?? 0) != 0 && (derivedMetadata.width ?? 0) != 0) {
    publicMetadata[heightKey] = derivedMetadata.height;
    publicMetadata[widthKey] = derivedMetadata.width;
    publicMetadata[mediaTypeKey] = isPanorama ? 1 : 0;
  }
  if (derivedMetadata.motionPhotoStartIndex != null) {
    publicMetadata[motionVideoIndexKey] = derivedMetadata.motionPhotoStartIndex;
  }
  if (!hasThumbnail) {
    publicMetadata[noThumbKey] = true;
  }
  if (exifTime != null) {
    if (exifTime.dateTime != null) {
      publicMetadata[dateTimeKey] = exifTime.dateTime;
    }
    if (exifTime.offsetTime != null) {
      publicMetadata[offsetTimeKey] = exifTime.offsetTime;
    }
  }
  if ((derivedMetadata.cameraMake ?? '').isNotEmpty) {
    publicMetadata[cameraMakeKey] = derivedMetadata.cameraMake;
  }
  if ((derivedMetadata.cameraModel ?? '').isNotEmpty) {
    publicMetadata[cameraModelKey] = derivedMetadata.cameraModel;
  }
  return publicMetadata;
}

class PreparedPublicMetadata {
  final String encodedJson;
  final PubMagicMetadata decodedMetadata;
  final MetadataRequest request;

  const PreparedPublicMetadata({
    required this.encodedJson,
    required this.decodedMetadata,
    required this.request,
  });
}

Future<PreparedPublicMetadata> preparePublicMetadata(
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

  final encodedJson = jsonEncode(jsonToUpdate);
  final encryptedMMd = await CryptoUtil.encryptChaCha(
    utf8.encode(encodedJson),
    fileKey,
  );
  return PreparedPublicMetadata(
    encodedJson: encodedJson,
    decodedMetadata: PubMagicMetadata.fromJson(jsonToUpdate),
    request: MetadataRequest(
      version: file.pubMmdVersion == 0 ? 1 : file.pubMmdVersion,
      count: jsonToUpdate.length,
      data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
      header: CryptoUtil.bin2base64(encryptedMMd.header!),
    ),
  );
}
