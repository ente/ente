import 'dart:io';
import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';

class MediaUploadData {
  final File sourceFile;
  final Uint8List? thumbnail;
  final bool isDeleted;
  final String fileHash;

  final DerivedMediaMetadata derivedMetadata;

  MediaUploadData({
    required this.sourceFile,
    required this.thumbnail,
    required this.isDeleted,
    required this.fileHash,
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
