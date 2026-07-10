import 'dart:io';
import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';

class MediaUploadData {
  final File? sourceFile;
  final Uint8List? thumbnail;
  final bool isDeleted;
  final FileHashData? hashData;
  final int? height;
  final int? width;
  final String? cameraMake;
  final String? cameraModel;

  // For android motion photos, the startIndex is the index of the first frame
  // For iOS, this value will be always null.
  final int? motionPhotoStartIndex;

  final Map<String, IfdTag>? exifData;

  bool? isPanorama;

  MediaUploadData(
    this.sourceFile,
    this.thumbnail,
    this.isDeleted,
    this.hashData, {
    this.height,
    this.width,
    this.cameraMake,
    this.cameraModel,
    this.motionPhotoStartIndex,
    this.isPanorama,
    this.exifData,
  });
}

class FileHashData {
  // For livePhotos, the fileHash value will be imageHash:videoHash
  final String? fileHash;

  // zipHash is used to take care of existing live photo uploads from older
  // mobile clients
  String? zipHash;

  FileHashData(this.fileHash, {this.zipHash});
}
