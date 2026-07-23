import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:locker/models/file_type.dart';
import 'package:locker/services/files/download/file_url.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:logging/logging.dart';

class EnteFile {
  String? localPath;
  int? uploadedFileID;
  int? ownerID;
  int? collectionID;
  String? title;
  int? creationTime;
  int? modificationTime;
  int? updationTime;
  int? addedTime;
  String? hash;
  int? metadataVersion;
  String? encryptedKey;
  String? keyDecryptionNonce;
  String? fileDecryptionHeader;
  String? thumbnailDecryptionHeader;
  String? metadataDecryptionHeader;
  int? fileSize;
  FileType? fileType;

  String? mMdEncodedJson;
  int mMdVersion = 0;
  MagicMetadata? _mmd;

  MagicMetadata get magicMetadata =>
      _mmd ?? MagicMetadata.fromEncodedJson(mMdEncodedJson ?? '{}');

  set magicMetadata(MagicMetadata? val) => _mmd = val;

  String? pubMmdEncodedJson;
  int pubMmdVersion = 1;
  PubMagicMetadata? _pubMmd;

  PubMagicMetadata get pubMagicMetadata =>
      _pubMmd ?? PubMagicMetadata.fromEncodedJson(pubMmdEncodedJson ?? '{}');

  set pubMagicMetadata(PubMagicMetadata? val) => _pubMmd = val;

  static const kCurrentMetadataVersion = 2;

  static final _logger = Logger('File');

  static EnteFile fromFile(File file) {
    final enteFile = EnteFile();
    enteFile.localPath = file.path;
    enteFile.title = file.path.split('/').last;
    enteFile.creationTime = file.statSync().changed.millisecondsSinceEpoch;
    enteFile.modificationTime = file.statSync().modified.millisecondsSinceEpoch;
    enteFile.fileType = FileType.other;
    return enteFile;
  }

  Map<String, dynamic> get metadata {
    final metadata = <String, dynamic>{};
    metadata["title"] = title;
    metadata["localPath"] = localPath;
    metadata["creationTime"] = creationTime;
    metadata["modificationTime"] = modificationTime;
    if (hash != null) {
      metadata["hash"] = hash;
    }
    if (metadataVersion != null) {
      metadata["version"] = metadataVersion;
    }
    if (fileType != null) {
      metadata["fileType"] = fileType!.index;
    }
    return metadata;
  }

  String get downloadUrl =>
      FileUrl.getUrl(uploadedFileID!, FileUrlType.download);

  String? get caption {
    return pubMagicMetadata.caption;
  }

  String? debugCaption;

  String get displayName {
    if (pubMagicMetadata.editedName != null) {
      return pubMagicMetadata.editedName!;
    }
    if (title == null && kDebugMode) _logger.severe('File title is null');
    return title ?? '';
  }

  bool get isUploaded {
    return uploadedFileID != null;
  }

  void applyMetadata(Map<String, dynamic> metadata) {
    title = metadata["title"];
    localPath = metadata["localPath"];
    creationTime = metadata["creationTime"] ?? 0;
    modificationTime = metadata["modificationTime"] ?? creationTime;
    hash = metadata["hash"];
    metadataVersion = metadata["version"] ?? 0;
    if (metadata["fileType"] != null) {
      fileType = getFileType(metadata["fileType"]);
    } else {
      fileType = FileType.other;
    }
  }

  @override
  String toString() {
    return '''File(title: $title, uploadedFileId: $uploadedFileID, 
      modificationTime: $modificationTime, ownerID: $ownerID,
      collectionID: $collectionID, updationTime: $updationTime)''';
  }

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is EnteFile && o.uploadedFileID == uploadedFileID;
  }

  @override
  int get hashCode {
    return uploadedFileID.hashCode;
  }
}
