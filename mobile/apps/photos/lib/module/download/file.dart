import 'dart:async';
import 'dart:io';

import "package:dio/dio.dart";
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
import 'package:photos/module/download/decrypt.dart';
import 'package:photos/module/live_photo/download.dart';

final _logger = Logger("FileUtil");

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
final Map<String, ProgressCallback?> _progressCallbacks = {};

Future<T> _runOncePerKey<K, T>(
  Map<K, Future<T>> inProgress,
  K key,
  Future<T> Function() start, {
  void Function()? onComplete,
}) {
  final existing = inProgress[key];
  if (existing != null) {
    return existing;
  }
  final download = start();
  inProgress[key] = download;

  void removeIfCurrent() {
    if (identical(inProgress[key], download)) {
      inProgress.remove(key);
      onComplete?.call();
    }
  }

  unawaited(
    download.then<void>(
      (_) => removeIfCurrent(),
      onError: (_, _) => removeIfCurrent(),
    ),
  );
  return download;
}

void removeDownloadCallback(EnteFile file) {
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

  return _runOncePerKey(
    _fileDownloadsInProgress,
    downloadID,
    () {
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
      return downloadFuture;
    },
    onComplete: () => _progressCallbacks.remove(downloadID),
  );
}

Future<bool> isFileCached(EnteFile file, {bool liveVideo = false}) async {
  final cacheManager = (file.fileType == FileType.video || liveVideo)
      ? VideoCacheManager.instance
      : DefaultCacheManager();
  final fileInfo = await cacheManager.getFileFromCache(file.downloadUrl);
  return fileInfo != null;
}

final Map<int, Future<LivePhotoFiles?>> _livePhotoDownloadsTracker =
    <int, Future<LivePhotoFiles?>>{};

Future<File?> _getLivePhotoFromServer(
  EnteFile file, {
  ProgressCallback? progressCallback,
  required bool needLiveVideo,
  bool forGalleryDownload = false,
}) async {
  final downloadID = file.uploadedFileID!;
  try {
    final livePhoto = await _runOncePerKey(
      _livePhotoDownloadsTracker,
      downloadID,
      () => downloadLivePhotoFiles(
        file,
        progressCallback: progressCallback,
        forGalleryDownload: forGalleryDownload,
      ),
    );
    if (livePhoto == null) {
      return null;
    }
    return needLiveVideo ? livePhoto.video : livePhoto.image;
  } catch (e, s) {
    _logger.warning("live photo get failed", e, s);
    if (forGalleryDownload) {
      rethrow;
    }
    return null;
  }
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
