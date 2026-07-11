import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/location/location.dart';
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/download/file_url.dart";

//Todo: files with no location data have lat and long set to 0.0. This should ideally be null.
class EnteFile {
  int? generatedID;
  int? uploadedFileID;
  int? ownerID;
  int? collectionID;
  String? localID;
  String? title;
  String? deviceFolder;
  int? creationTime;
  int? modificationTime;
  int? updationTime;
  int? addedTime;
  Location? location;
  late FileType fileType;
  int? fileSubType;
  int? duration;
  String? exif;
  String? hash;
  int? metadataVersion;
  String? encryptedKey;
  String? keyDecryptionNonce;
  String? fileDecryptionHeader;
  String? thumbnailDecryptionHeader;
  String? metadataDecryptionHeader;
  int? fileSize;

  String? _mMdEncodedJson;
  String? get mMdEncodedJson => _mMdEncodedJson;

  set mMdEncodedJson(String? value) {
    if (_mMdEncodedJson == value) return;
    _mMdEncodedJson = value;
    _mmd = null;
  }

  int mMdVersion = 0;
  MagicMetadata? _mmd;

  MagicMetadata get magicMetadata =>
      _mmd ??= MagicMetadata.fromEncodedJson(mMdEncodedJson ?? '{}');

  set magicMetadata(MagicMetadata? val) => _mmd = val;

  // public magic metadata is shared if during file/album sharing
  String? _pubMmdEncodedJson;
  String? get pubMmdEncodedJson => _pubMmdEncodedJson;

  set pubMmdEncodedJson(String? value) {
    if (_pubMmdEncodedJson == value) return;
    _pubMmdEncodedJson = value;
    _pubMmd = null;
  }

  int pubMmdVersion = 0;
  PubMagicMetadata? _pubMmd;

  PubMagicMetadata? get pubMagicMetadata =>
      _pubMmd ??= PubMagicMetadata.fromEncodedJson(pubMmdEncodedJson ?? '{}');

  set pubMagicMetadata(PubMagicMetadata? val) => _pubMmd = val;

  // in Version 1, live photo hash is stored as zip's hash.
  // in V2: LivePhoto hash is stored as imgHash:vidHash
  // in V3: Safeguard for concurrent multipart uploads
  static const kCurrentMetadataVersion = 3;
  static const kMetadataSimplifiedEncVersion = 4;

  static final _logger = Logger('File');

  EnteFile();

  Future<AssetEntity?> get getAsset {
    if (localID == null) {
      return Future.value(null);
    }
    return AssetEntity.fromId(localID!);
  }

  void applyMetadata(Map<String, dynamic> metadata) {
    localID = metadata["localID"];
    title = metadata["title"];
    deviceFolder = metadata["deviceFolder"];
    creationTime = metadata["creationTime"] ?? 0;
    modificationTime = metadata["modificationTime"] ?? creationTime;
    final latitude = double.tryParse(metadata["latitude"].toString());
    final longitude = double.tryParse(metadata["longitude"].toString());
    if (latitude == null || longitude == null) {
      location = null;
    } else {
      location = Location(latitude: latitude, longitude: longitude);
    }
    fileType = getFileType(metadata["fileType"] ?? -1);
    fileSubType = metadata["subType"] ?? -1;
    duration = metadata["duration"] ?? 0;
    exif = metadata["exif"];
    hash = metadata["hash"];
    // handle past live photos upload from web client
    if (hash == null &&
        fileType == FileType.livePhoto &&
        metadata.containsKey('imageHash') &&
        metadata.containsKey('videoHash')) {
      // convert to imgHash:vidHash
      hash =
          '${metadata['imageHash']}$kLivePhotoHashSeparator${metadata['videoHash']}';
    }
    metadataVersion = metadata["version"] ?? 0;
  }

  Map<String, dynamic> get metadata {
    final metadata = <String, dynamic>{};
    metadata["localID"] = isSharedMediaToAppSandbox ? null : localID;
    metadata["title"] = title;
    metadata["deviceFolder"] = deviceFolder;
    metadata["creationTime"] = creationTime;
    metadata["modificationTime"] = modificationTime;
    metadata["fileType"] = fileType.index;
    if (location != null &&
        location!.latitude != null &&
        location!.longitude != null) {
      metadata["latitude"] = location!.latitude;
      metadata["longitude"] = location!.longitude;
    }
    if (fileSubType != null) {
      metadata["subType"] = fileSubType;
    }
    if (duration != null) {
      metadata["duration"] = duration;
    }
    if (hash != null) {
      metadata["hash"] = hash;
    }
    if (metadataVersion != null) {
      metadata["version"] = metadataVersion;
    }
    return metadata;
  }

  String get downloadUrl =>
      FileUrl.getUrl(uploadedFileID!, FileUrlType.download);

  String? get caption {
    return pubMagicMetadata?.caption;
  }

  String? debugCaption;

  String get displayName {
    if (pubMagicMetadata != null && pubMagicMetadata!.editedName != null) {
      return pubMagicMetadata!.editedName!;
    }
    if (title == null && kDebugMode) _logger.severe('File title is null');
    return title ?? '';
  }

  // return 0 if the height is not available
  int get height {
    return pubMagicMetadata?.h ?? 0;
  }

  int get width {
    return pubMagicMetadata?.w ?? 0;
  }

  bool get hasDimensions {
    return height != 0 && width != 0;
  }

  bool get isRemoteOnlyFile => localID == null && uploadedFileID != null;

  bool get isUploaded {
    return uploadedFileID != null;
  }

  bool get isSharedMediaToAppSandbox {
    return localID != null && localID!.startsWith(sharedMediaIdentifier);
  }

  bool get hasLocation {
    return location != null &&
        ((location!.longitude ?? 0) != 0 || (location!.latitude ?? 0) != 0);
  }

  @override
  String toString() {
    return '''File(generatedID: $generatedID, localID: $localID, title: $title, 
      type: $fileType, uploadedFileId: $uploadedFileID, modificationTime: $modificationTime, 
      ownerID: $ownerID, collectionID: $collectionID, updationTime: $updationTime)''';
  }

  /// Mutates this file in place with upload-result fields from [uploadedFile].
  /// Used by the gallery's soft refresh path so that all existing references
  /// (GalleryGroups sub-lists, GalleryFileWidget.widget.file, etc.) see the
  /// updated state without needing to rebuild GalleryGroups.
  void applyUploadedData(EnteFile uploadedFile) {
    uploadedFileID = uploadedFile.uploadedFileID;
    collectionID = uploadedFile.collectionID;
    updationTime = uploadedFile.updationTime;
    ownerID = uploadedFile.ownerID;
    encryptedKey = uploadedFile.encryptedKey;
    keyDecryptionNonce = uploadedFile.keyDecryptionNonce;
    fileDecryptionHeader = uploadedFile.fileDecryptionHeader;
    thumbnailDecryptionHeader = uploadedFile.thumbnailDecryptionHeader;
    metadataDecryptionHeader = uploadedFile.metadataDecryptionHeader;
    if (uploadedFile.metadataVersion != null) {
      metadataVersion = uploadedFile.metadataVersion;
    }
    if (uploadedFile.fileSize != null) {
      fileSize = uploadedFile.fileSize;
    }
  }

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is EnteFile &&
        o.generatedID == generatedID &&
        o.uploadedFileID == uploadedFileID &&
        o.localID == localID;
  }

  @override
  int get hashCode {
    return generatedID.hashCode ^ uploadedFileID.hashCode ^ localID.hashCode;
  }

  String get tag {
    return "local_" +
        localID.toString() +
        ":remote_" +
        uploadedFileID.toString() +
        ":generated_" +
        generatedID.toString();
  }

  String cacheKey() {
    // todo: Neeraj: 19thJuly'22: evaluate and add fileHash as the key?
    return localID ?? uploadedFileID?.toString() ?? generatedID.toString();
  }

  EnteFile copyWith({
    int? generatedID,
    int? uploadedFileID,
    int? ownerID,
    int? collectionID,
    String? localID,
    String? title,
    String? deviceFolder,
    int? creationTime,
    int? modificationTime,
    int? updationTime,
    int? addedTime,
    Location? location,
    FileType? fileType,
    int? fileSubType,
    int? duration,
    String? exif,
    String? hash,
    int? metadataVersion,
    String? encryptedKey,
    String? keyDecryptionNonce,
    String? fileDecryptionHeader,
    String? thumbnailDecryptionHeader,
    String? metadataDecryptionHeader,
    int? fileSize,
    String? mMdEncodedJson,
    int? mMdVersion,
    MagicMetadata? magicMetadata,
    String? pubMmdEncodedJson,
    int? pubMmdVersion,
    PubMagicMetadata? pubMagicMetadata,
  }) {
    return EnteFile()
      ..generatedID = generatedID ?? this.generatedID
      ..uploadedFileID = uploadedFileID ?? this.uploadedFileID
      ..ownerID = ownerID ?? this.ownerID
      ..collectionID = collectionID ?? this.collectionID
      ..localID = localID ?? this.localID
      ..title = title ?? this.title
      ..deviceFolder = deviceFolder ?? this.deviceFolder
      ..creationTime = creationTime ?? this.creationTime
      ..modificationTime = modificationTime ?? this.modificationTime
      ..updationTime = updationTime ?? this.updationTime
      ..addedTime = addedTime ?? this.addedTime
      ..location = location ?? this.location
      ..fileType = fileType ?? this.fileType
      ..fileSubType = fileSubType ?? this.fileSubType
      ..duration = duration ?? this.duration
      ..exif = exif ?? this.exif
      ..hash = hash ?? this.hash
      ..metadataVersion = metadataVersion ?? this.metadataVersion
      ..encryptedKey = encryptedKey ?? this.encryptedKey
      ..keyDecryptionNonce = keyDecryptionNonce ?? this.keyDecryptionNonce
      ..fileDecryptionHeader = fileDecryptionHeader ?? this.fileDecryptionHeader
      ..thumbnailDecryptionHeader =
          thumbnailDecryptionHeader ?? this.thumbnailDecryptionHeader
      ..metadataDecryptionHeader =
          metadataDecryptionHeader ?? this.metadataDecryptionHeader
      ..fileSize = fileSize ?? this.fileSize
      ..mMdEncodedJson = mMdEncodedJson ?? this.mMdEncodedJson
      ..mMdVersion = mMdVersion ?? this.mMdVersion
      ..magicMetadata = magicMetadata ?? this.magicMetadata
      ..pubMmdEncodedJson = pubMmdEncodedJson ?? this.pubMmdEncodedJson
      ..pubMmdVersion = pubMmdVersion ?? this.pubMmdVersion
      ..pubMagicMetadata = pubMagicMetadata ?? this.pubMagicMetadata;
  }
}
