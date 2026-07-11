import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import "package:dio/dio.dart";
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:motionphoto/motionphoto.dart';
import 'package:path/path.dart';
import 'package:photos/core/cache/image_cache.dart';
import 'package:photos/core/cache/thumbnail_in_memory_cache.dart';
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/live_photo/archive.dart';
import 'package:photos/utils/file_download_util.dart';

final _logger = Logger("FileUtil");

const Set<String> _rawImageExtensions = {
  'arw', // Sony
  'cr2', 'cr3', // Canon
  'nef', 'nrw', // Nikon
  'dng', // Adobe/generic
  'orf', // Olympus
  'raf', // Fuji
  'rw2', // Panasonic
  'pef', // Pentax
  'srw', // Samsung
  '3fr', 'fff', // Hasselblad
  'rwl', // Leica
  'x3f', // Sigma
  'iiq', // Phase One
  'kdc', 'dcr', // Kodak
  'mrw', // Minolta
  'erf', // Epson
  'mef', // Mamiya
  'raw', // Generic
};

bool isRawImageExtension(String extension) {
  return _rawImageExtensions.contains(extension.toLowerCase());
}

void preloadFile(EnteFile file) {
  if (file.fileType == FileType.video) {
    return;
  }
  getFile(file);
}

// IMPORTANT: Delete the returned file if `isOrigin` is set to true
// https://github.com/CaiJingLong/flutter_photo_manager#cache-problem-of-ios
Future<File?> getFile(
  EnteFile file, {
  bool liveVideo = false,
  bool isOrigin = false,
  bool forGalleryDownload = false, // only relevant for live photos
}) async {
  try {
    if (file.isRemoteOnlyFile) {
      return getFileFromServer(
        file,
        liveVideo: liveVideo,
        forGalleryDownload: forGalleryDownload,
      );
    } else {
      final String key = file.tag + liveVideo.toString() + isOrigin.toString();
      final cachedFile = FileLruCache.get(key);
      if (cachedFile == null) {
        final diskFile = await _getLocalDiskFile(
          file,
          liveVideo: liveVideo,
          isOrigin: isOrigin,
        );
        // do not cache origin file for IOS as they are immediately deleted
        // after usage
        if (!(isOrigin && Platform.isIOS) && diskFile != null) {
          FileLruCache.put(key, diskFile);
        }
        return diskFile;
      }
      return cachedFile;
    }
  } catch (e, s) {
    _logger.warning("Failed to get file", e, s);
    if (forGalleryDownload) {
      rethrow;
    }
    return null;
  }
}

Future<bool> doesLocalFileExist(EnteFile file) async {
  return await _getLocalDiskFile(file) != null;
}

Future<File?> _getLocalDiskFile(
  EnteFile file, {
  bool liveVideo = false,
  bool isOrigin = false,
}) {
  if (file.isSharedMediaToAppSandbox) {
    final localFile = File(getSharedMediaFilePath(file));
    return localFile.exists().then((exist) {
      return exist ? localFile : null;
    });
  } else if (file.fileType == FileType.livePhoto && liveVideo) {
    return Motionphoto.getLivePhotoFile(file.localID!);
  } else {
    return file.getAsset.then((asset) async {
      if (asset == null || !(await asset.exists)) {
        if (isOrigin && file.isVideo) {
          _logger.warning(
            "Failed to get file for assetID: ${file.localID}, is asset null: ${asset == null}",
          );
        }
        return null;
      }
      return isOrigin ? asset.originFile : asset.file;
    });
  }
}

String getSharedMediaFilePath(EnteFile file) {
  return getSharedMediaPathFromLocalID(file.localID!);
}

String getSharedMediaPathFromLocalID(String localID) {
  return Configuration.instance.getSharedMediaDirectory() +
      "/" +
      localID.replaceAll(sharedMediaIdentifier, '');
}

final Map<String, Future<File?>> _fileDownloadsInProgress =
    <String, Future<File?>>{};
Map<String, ProgressCallback?> _progressCallbacks = {};

void removeCallBack(EnteFile file) {
  if (!file.isUploaded) {
    return;
  }
  String id = file.uploadedFileID.toString() + false.toString();
  _progressCallbacks.remove(id);
  if (file.isLivePhoto) {
    id = file.uploadedFileID.toString() + true.toString();
    _progressCallbacks.remove(id);
  }
}

Future<File?> getFileFromServer(
  EnteFile file, {
  ProgressCallback? progressCallback,
  bool liveVideo = false, // only needed in case of live photos
  bool forGalleryDownload = false,
}) async {
  final cacheManager = (file.fileType == FileType.video || liveVideo)
      ? VideoCacheManager.instance
      : DefaultCacheManager();
  final fileFromCache = await cacheManager.getFileFromCache(file.downloadUrl);
  if (fileFromCache != null) {
    return fileFromCache.file;
  }
  final downloadID = file.uploadedFileID.toString() + liveVideo.toString();

  if (progressCallback != null) {
    _progressCallbacks[downloadID] = progressCallback;
  }

  if (!_fileDownloadsInProgress.containsKey(downloadID)) {
    final completer = Completer<File?>();
    _fileDownloadsInProgress[downloadID] = completer.future;

    Future<File?> downloadFuture;
    if (file.fileType == FileType.livePhoto) {
      downloadFuture = _getLivePhotoFromServer(
        file,
        progressCallback: (count, total) {
          _progressCallbacks[downloadID]?.call(count, total);
        },
        needLiveVideo: liveVideo,
        forGalleryDownload: forGalleryDownload,
      );
    } else {
      downloadFuture = _downloadAndCache(
        file,
        cacheManager,
        progressCallback: (count, total) {
          _progressCallbacks[downloadID]?.call(count, total);
        },
        forGalleryDownload: forGalleryDownload,
      );
    }
    unawaited(
      downloadFuture
          .then((downloadedFile) {
            if (!completer.isCompleted) {
              completer.complete(downloadedFile);
            }
          })
          .catchError((error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          })
          .whenComplete(() {
            _fileDownloadsInProgress.remove(downloadID);
            _progressCallbacks.remove(downloadID);
          }),
    );
  }
  return _fileDownloadsInProgress[downloadID];
}

Future<bool> isFileCached(EnteFile file, {bool liveVideo = false}) async {
  final cacheManager = (file.fileType == FileType.video || liveVideo)
      ? VideoCacheManager.instance
      : DefaultCacheManager();
  final fileInfo = await cacheManager.getFileFromCache(file.downloadUrl);
  return fileInfo != null;
}

final Map<int, Future<_LivePhoto?>> _livePhotoDownloadsTracker =
    <int, Future<_LivePhoto?>>{};

Future<File?> _getLivePhotoFromServer(
  EnteFile file, {
  ProgressCallback? progressCallback,
  required bool needLiveVideo,
  bool forGalleryDownload = false,
}) async {
  final downloadID = file.uploadedFileID!;
  try {
    if (!_livePhotoDownloadsTracker.containsKey(downloadID)) {
      _livePhotoDownloadsTracker[downloadID] = _downloadLivePhoto(
        file,
        progressCallback: progressCallback,
        forGalleryDownload: forGalleryDownload,
      );
    }
    final livePhoto = await _livePhotoDownloadsTracker[file.uploadedFileID];
    await _livePhotoDownloadsTracker.remove(downloadID);
    if (livePhoto == null) {
      return null;
    }
    return needLiveVideo ? livePhoto.video : livePhoto.image;
  } catch (e, s) {
    _logger.warning("live photo get failed", e, s);
    await _livePhotoDownloadsTracker.remove(downloadID);
    if (forGalleryDownload) {
      rethrow;
    }
    return null;
  }
}

Future<_LivePhoto?> _downloadLivePhoto(
  EnteFile file, {
  ProgressCallback? progressCallback,
  bool forGalleryDownload = false,
}) async {
  return downloadAndDecrypt(
        file,
        progressCallback: progressCallback,
        forceResumableDownload: forGalleryDownload,
        throwOnFailure: forGalleryDownload,
      )
      .then((decryptedFile) async {
        if (decryptedFile == null) {
          return null;
        }
        _logger.info("Decoded zipped live photo from " + decryptedFile.path);
        File? imageFileCache, videoFileCache;
        final List<int> bytes = await decryptedFile.readAsBytes();
        final parts = decodeLivePhotoArchive(bytes);
        final tempPath = Configuration.instance.getTempDirectory();
        for (final part in parts) {
          final String fileExtension = getExtension(part.fileName);
          final String decodePath =
              tempPath + file.uploadedFileID.toString() + part.fileName;
          if (part.type == LivePhotoArchivePartType.image) {
            final imageFile = File(decodePath);
            await imageFile.create(recursive: true);
            await imageFile.writeAsBytes(part.bytes);
            File imageConvertedFile = imageFile;
            if ((fileExtension == "unknown") ||
                (Platform.isAndroid && fileExtension == "heic")) {
              final compressResult =
                  await FlutterImageCompress.compressAndGetFile(
                    decodePath,
                    decodePath + ".jpg",
                    keepExif: true,
                  );
              await imageFile.delete();
              if (compressResult == null) {
                throw Exception("Failed to compress file");
              } else {
                imageConvertedFile = File(compressResult.path);
              }
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
          return _LivePhoto(imageFileCache, videoFileCache);
        } else {
          debugPrint(
            "Warning: ${file.tag} either image ${imageFileCache == null} or video ${videoFileCache == null} is missing from remoteLive",
          );
          return null;
        }
      })
      .catchError((e) {
        _logger.warning("failed to download live photos : ${file.tag}", e);
        throw e;
      });
}

Future<File?> _downloadAndCache(
  EnteFile file,
  BaseCacheManager cacheManager, {
  required ProgressCallback progressCallback,
  bool forGalleryDownload = false,
}) async {
  return downloadAndDecrypt(
        file,
        progressCallback: progressCallback,
        forceResumableDownload: forGalleryDownload,
        throwOnFailure: forGalleryDownload,
      )
      .then((decryptedFile) async {
        if (decryptedFile == null) {
          return null;
        }
        final decryptedFilePath = decryptedFile.path;
        final String fileExtension = getExtension(file.title ?? '');
        File outputFile = decryptedFile;
        if ((fileExtension == "unknown" && file.fileType == FileType.image)) {
          final compressResult = await FlutterImageCompress.compressAndGetFile(
            decryptedFilePath,
            decryptedFilePath + ".jpg",
            keepExif: true,
          );
          if (compressResult == null) {
            throw Exception("Failed to convert heic to jpg");
          } else {
            outputFile = File(compressResult.path);
          }
          await decryptedFile.delete();
        }
        final cachedFile = await cacheManager.putFileStream(
          file.downloadUrl,
          outputFile.openRead(),
          eTag: file.downloadUrl,
          maxAge: const Duration(days: 365),
          fileExtension: fileExtension,
        );
        await outputFile.delete();
        return cachedFile;
      })
      .catchError((e) {
        _logger.warning("failed to download file : ${file.tag}", e);
        throw e;
      });
}

String getExtension(String nameOrPath) {
  var fileExtension = "unknown";
  try {
    fileExtension = extension(nameOrPath).substring(1).toLowerCase();
  } catch (e) {
    _logger.severe("Could not capture file extension");
  }
  return fileExtension;
}

Future<void> clearCache(EnteFile file) async {
  if (file.fileType == FileType.video) {
    await VideoCacheManager.instance.removeFile(file.downloadUrl);
  } else {
    await DefaultCacheManager().removeFile(file.downloadUrl);
  }
  final cachedThumbnail = File(
    Configuration.instance.getThumbnailCacheDirectory() +
        "/" +
        file.uploadedFileID.toString(),
  );
  if (cachedThumbnail.existsSync()) {
    await cachedThumbnail.delete();
  }
  ThumbnailInMemoryLruCache.clearCache(file);
}

class _LivePhoto {
  final File image;
  final File video;

  _LivePhoto(this.image, this.video);
}

Set<int> filesToUploadedFileIDs(List<EnteFile> files) {
  final uploadedFileIDs = <int>{};
  for (final file in files) {
    if (file.isUploaded) {
      uploadedFileIDs.add(file.uploadedFileID!);
    }
  }
  return uploadedFileIDs;
}

Future<String> computeSha1(String filePath) async {
  final file = File(filePath);
  final input = file.openRead();
  final hash = await sha1.bind(input).first;
  return hash.toString();
}

/// Computes the MD5 hash of a file or a portion of it.
///
/// [filePath] - Path to the file
/// [start] - Optional starting byte position for partial hash computation
/// [end] - Optional ending byte position for partial hash computation
