import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/module/download/decrypt.dart';
import 'package:photos/module/live_photo/archive.dart';

typedef LivePhotoFiles = ({File image, File video});

final _logger = Logger('FileUtil');

Future<LivePhotoFiles?> downloadLivePhotoFiles(
  EnteFile file, {
  ProgressCallback? progressCallback,
  bool forGalleryDownload = false,
}) async {
  File? decryptedFile;
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
    File? imageFileCache;
    File? videoFileCache;
    final parts = decodeLivePhotoArchive(await decryptedFile.readAsBytes());
    final tempPath = Configuration.instance.getTempDirectory();
    for (final part in parts) {
      final fileExtension = _fileExtension(part.fileName);
      final decodePath = '$tempPath${file.uploadedFileID}${part.fileName}';
      if (part.type == LivePhotoArchivePartType.image) {
        final imageFile = File(decodePath);
        await imageFile.create(recursive: true);
        await imageFile.writeAsBytes(part.bytes);
        File imageConvertedFile = imageFile;
        if (fileExtension == 'unknown' ||
            (Platform.isAndroid && fileExtension == 'heic')) {
          final compressResult = await FlutterImageCompress.compressAndGetFile(
            decodePath,
            '$decodePath.jpg',
            keepExif: true,
          );
          await imageFile.delete();
          if (compressResult == null) {
            throw Exception('Failed to compress file');
          }
          imageConvertedFile = File(compressResult.path);
        }
        imageFileCache = await DefaultCacheManager().putFile(
          file.downloadUrl,
          await imageConvertedFile.readAsBytes(),
          eTag: file.downloadUrl,
          maxAge: const Duration(days: 365),
          fileExtension: fileExtension,
        );
        await imageConvertedFile.delete();
      } else {
        final videoFile = File(decodePath);
        await videoFile.create(recursive: true);
        await videoFile.writeAsBytes(part.bytes);
        videoFileCache = await VideoCacheManager.instance.putFileStream(
          file.downloadUrl,
          videoFile.openRead(),
          eTag: file.downloadUrl,
          maxAge: const Duration(days: 365),
          fileExtension: fileExtension,
        );
        await videoFile.delete();
      }
    }
    if (imageFileCache != null && videoFileCache != null) {
      return (image: imageFileCache, video: videoFileCache);
    }
    debugPrint(
      'Warning: ${file.tag} either image ${imageFileCache == null} or video ${videoFileCache == null} is missing from remoteLive',
    );
    return null;
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
  }
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

String _fileExtension(String nameOrPath) {
  try {
    return extension(nameOrPath).substring(1).toLowerCase();
  } catch (_) {
    _logger.severe('Could not capture file extension');
    return 'unknown';
  }
}
