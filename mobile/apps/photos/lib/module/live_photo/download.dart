import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/decrypt.dart';
import 'package:photos/module/live_photo/archive.dart';
import 'package:photos/utils/device_info.dart';

typedef LivePhotoFiles = ({File image, File video});

final _logger = Logger('FileUtil');

Future<bool> canRefreshLivePhotoStill(
  EnteFile file, {
  String? imageName,
}) async =>
    Platform.isAndroid &&
    file.fileType == FileType.livePhoto &&
    (extension(file.title ?? '').toLowerCase() == '.heic' ||
        extension(imageName ?? '').toLowerCase() == '.heic') &&
    !await isAndroidSDKVersionLowerThan(28);

Future<LivePhotoFiles?> downloadLivePhotoFiles(
  EnteFile file, {
  ProgressCallback? progressCallback,
  bool forGalleryDownload = false,
}) async {
  File? decryptedFile;
  Directory? extractionDirectory;
  try {
    decryptedFile = await downloadAndDecrypt(
      file,
      progressCallback: progressCallback,
      forceResumableDownload: forGalleryDownload,
      throwOnFailure: forGalleryDownload,
    );
    if (decryptedFile == null) {
      return null;
    }
    _logger.info('Decoded zipped live photo from ${decryptedFile.path}');
    extractionDirectory = await Directory(
      Configuration.instance.getTempDirectory(),
    ).createTemp('live_photo_${file.uploadedFileID}_');
    final parts = await extractLivePhotoArchive(
      archiveFile: decryptedFile,
      outputDirectory: extractionDirectory,
    );
    final checkRotation = await canRefreshLivePhotoStill(
      file,
      imageName: parts.image.fileName,
    );
    return await _cacheParts(file, parts.image, parts.video, checkRotation);
  } catch (error, stackTrace) {
    _logger.warning(
      'failed to download live photos : ${file.tag}',
      error,
      stackTrace,
    );
    rethrow;
  } finally {
    if (decryptedFile != null) {
      await _deleteDecryptedArchive(decryptedFile);
    }
    if (extractionDirectory != null) {
      await _deleteExtractionDirectory(extractionDirectory);
    }
  }
}

Future<LivePhotoFiles> _cacheParts(
  EnteFile file,
  LivePhotoArchivePart image,
  LivePhotoArchivePart video,
  bool checkRotation,
) async {
  var fileExtension = _fileExtension(image.fileName);
  File imageFile = image.file;
  var stillUrl = file.downloadUrl;
  final isAndroidHeic = Platform.isAndroid && fileExtension == 'heic';
  int? rotation;
  if (checkRotation) {
    try {
      if (isAndroidHeic || fileExtension == 'unknown') {
        // Rust can replace this check once its JPEGs preserve orientation,
        // resolution, and EXIF. Older cached JPEGs still need a refresh.
        rotation = await LocalMediaClient.instance.missingHeicRotation(
          imageFile.path,
        );
      }
      stillUrl += '#live-photo-still-v2';
    } on Exception catch (error, stackTrace) {
      _logger.warning('Failed to read HEIC rotation', error, stackTrace);
    }
  }
  if (fileExtension == 'unknown' || isAndroidHeic) {
    final compressResult = await FlutterImageCompress.compressAndGetFile(
      imageFile.path,
      '${imageFile.path}.jpg',
      rotate: rotation ?? 0,
      autoCorrectionAngle: rotation == null,
      keepExif: true,
    );
    if (compressResult == null) {
      throw Exception('Failed to compress file');
    }
    imageFile = File(compressResult.path);
    fileExtension = 'jpg';
  }
  const maxAge = Duration(days: 365);
  final key = file.downloadUrl;
  final videoCache = VideoCacheManager.instance;
  final existingClip = checkRotation
      ? await videoCache.getFileFromCache(key)
      : null;
  if (existingClip != null) {
    await video.file.rename(existingClip.file.path);
  }
  final cache = DefaultCacheManager();
  final existing = checkRotation
      ? await cache.store.retrieveCacheData(key)
      : null;
  final File still;
  if (existing == null) {
    still = await cache.putFileStream(
      stillUrl,
      imageFile.openRead(),
      key: key,
      eTag: key,
      maxAge: maxAge,
      fileExtension: fileExtension,
    );
  } else {
    final target = await cache.config.fileSystem.createFile(
      existing.relativePath,
    );
    still = await imageFile.rename(target.path);
    await cache.store.putFile(
      existing.copyWith(url: stillUrl, validTill: DateTime.now().add(maxAge)),
    );
  }
  return (
    image: still,
    video:
        existingClip?.file ??
        await videoCache.putFileStream(
          key,
          video.file.openRead(),
          eTag: key,
          maxAge: maxAge,
          fileExtension: _fileExtension(video.fileName),
        ),
  );
}

Future<void> _deleteDecryptedArchive(File file) async {
  try {
    await file.delete();
  } catch (error, stackTrace) {
    _logger.warning(
      'Failed to delete decrypted live photo archive',
      error,
      stackTrace,
    );
  }
}

Future<void> _deleteExtractionDirectory(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } catch (error, stackTrace) {
    _logger.warning(
      'Failed to delete extracted live photo files',
      error,
      stackTrace,
    );
  }
}

String _fileExtension(String nameOrPath) {
  try {
    return extension(nameOrPath).substring(1).toLowerCase();
  } catch (_) {
    _logger.severe('Could not capture file extension');
    return 'unknown';
  }
}
