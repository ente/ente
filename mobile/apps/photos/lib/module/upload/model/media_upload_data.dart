import 'dart:io';
import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';

class MediaUploadData {
  final File sourceFile;
  final Uint8List? thumbnail;
  final bool isDeleted;
  final FileHashData hashData;

  final DerivedMediaMetadata derivedMetadata;

  MediaUploadData({
    required this.sourceFile,
    required this.thumbnail,
    required this.isDeleted,
    required this.hashData,
    required this.derivedMetadata,
  });
}

class DerivedMediaMetadata {
  final int? height;
  final int? width;
  final String? cameraMake;
  final String? cameraModel;

  // For android motion photos, the startIndex is the index of the first frame
  // For iOS, this value will be always null.
  final int? motionPhotoStartIndex;

  final Map<String, IfdTag>? exifData;

  const DerivedMediaMetadata({
    this.height,
    this.width,
    this.cameraMake,
    this.cameraModel,
    this.motionPhotoStartIndex,
    this.exifData,
  });
}

class FileHashData {
  // For livePhotos, the fileHash value will be imageHash:videoHash
  final String fileHash;

  // zipHash is used to take care of existing live photo uploads from older
  // mobile clients
  final String? zipHash;

  FileHashData(this.fileHash, {this.zipHash});
}
