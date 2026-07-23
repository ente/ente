import 'dart:io';

import 'package:dio/dio.dart';
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
    return (
      image: await _cacheImagePart(file, parts.image),
      video: await _cacheVideoPart(file, parts.video),
    );
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

Future<File> _cacheImagePart(EnteFile file, LivePhotoArchivePart part) async {
  var fileExtension = _fileExtension(part.fileName);
  File imageFile = part.file;
  if (fileExtension == 'unknown' ||
      (Platform.isAndroid && fileExtension == 'heic')) {
    final compressResult = await FlutterImageCompress.compressAndGetFile(
      imageFile.path,
      '${imageFile.path}.jpg',
      keepExif: true,
    );
    if (compressResult == null) {
      throw Exception('Failed to compress file');
    }
    imageFile = File(compressResult.path);
    fileExtension = 'jpg';
  }
  return DefaultCacheManager().putFileStream(
    file.downloadUrl,
    imageFile.openRead(),
    eTag: file.downloadUrl,
    maxAge: const Duration(days: 365),
    fileExtension: fileExtension,
  );
}

Future<File> _cacheVideoPart(EnteFile file, LivePhotoArchivePart part) {
  return VideoCacheManager.instance.putFileStream(
    file.downloadUrl,
    part.file.openRead(),
    eTag: file.downloadUrl,
    maxAge: const Duration(days: 365),
    fileExtension: _fileExtension(part.fileName),
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
