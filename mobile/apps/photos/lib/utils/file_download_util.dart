import "dart:async";
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import 'package:logging/logging.dart';
import 'package:path/path.dart' as file_path;
import "package:photo_manager/photo_manager.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/core/event_bus.dart";
import 'package:photos/core/network/network.dart';
import "package:photos/db/device_files_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/local_photos_updated_event.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";
import "package:photos/models/ignored_file.dart";
import "package:photos/module/download/file_url.dart";
import "package:photos/module/download/manager.dart";
import "package:photos/module/download/task.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/utils/apple_photos_errors.dart";
import "package:photos/utils/file_key.dart";
import "package:photos/utils/file_util.dart";

final _logger = Logger("file_download_util");

class DownloadFailedError implements Exception {
  final String message;

  DownloadFailedError(this.message);

  @override
  String toString() => message;
}

class DownloadNoConnectionError extends DownloadFailedError {
  DownloadNoConnectionError() : super("No connection");
}

class DownloadNotEnoughStorageError extends DownloadFailedError {
  DownloadNotEnoughStorageError() : super("Not enough storage");
}

class DownloadUnavailableError extends DownloadFailedError {
  DownloadUnavailableError() : super("Unavailable");
}

/// Use this instead of `file.displayName` directly for skip toasts.
///
/// Rationale:
/// 1. We prefer the original title for stable, filename-like copy in the toast.
String getDownloadSkipToastFileName(EnteFile file) {
  final title = (file.title ?? "").trim();
  final displayName = file.displayName.trim();
  return title.isNotEmpty ? title : displayName;
}

String _getGallerySaveTitle(EnteFile file, String fallbackPath) {
  final displayName = file.displayName;
  if (displayName.trim().isNotEmpty) {
    return displayName;
  }
  final title = file.title;
  if (title != null && title.trim().isNotEmpty) {
    return title;
  }
  return file_path.basename(fallbackPath);
}

String _sanitizeAndroidVideoGalleryTitle(String title) {
  final fragmentIndex = title.lastIndexOf("#");
  if (!Platform.isAndroid ||
      fragmentIndex < 0 ||
      title.lastIndexOf(".") <= fragmentIndex) {
    return title;
  }
  // Android's MIME guesser treats # as a URL fragment delimiter.
  return title.replaceAll("#", "_");
}

Future<String?> getExistingLocalFolderNameForDownloadSkipToast(
  EnteFile file,
) async {
  if (file.localID == null) {
    return null;
  }
  final asset = await file.getAsset;
  if (asset == null || !(await asset.exists)) {
    return null;
  }
  final folderNames = await FilesDB.instance.getDeviceCollectionNamesForLocalID(
    file.localID!,
  );
  if (folderNames.isNotEmpty) {
    return folderNames.last;
  }
  // The asset exists on device but no device-collection mapping is recorded
  // yet (e.g. LocalSyncService hasn't ingested it). Treat this as "not
  // skippable" rather than crashing; a duplicate save is preferable to an
  // unhandled StateError surfacing in the download flow.
  _logger.severe(
    "No device collection name found for localID=${file.localID} "
    "despite asset existing on device.",
  );
  return null;
}

Future<File?> downloadAndDecryptPublicFile(
  EnteFile file, {
  ProgressCallback? progressCallback,
}) async {
  final String logPrefix = 'Public File-${file.uploadedFileID}:';
  _logger.info(
    '$logPrefix starting download ${formatBytes(file.fileSize ?? 0)}',
  );

  final String tempDir = Configuration.instance.getTempDirectory();
  final String encryptedFilePath = "$tempDir${file.uploadedFileID}.encrypted";
  final String decryptedFilePath = "$tempDir${file.uploadedFileID}.decrypted";

  try {
    final headers = CollectionsService.instance.publicCollectionHeaders(
      file.collectionID!,
    );
    final response = (await NetworkClient.instance.downloadDio.download(
      FileUrl.getUrl(file.uploadedFileID!, FileUrlType.publicDownload),
      encryptedFilePath,
      options: Options(headers: headers, responseType: ResponseType.bytes),
      onReceiveProgress: (a, b) {
        progressCallback?.call(a, b);
      },
    ));

    if (response.statusCode != 200) {
      _logger.warning('$logPrefix download failed ${response.toString()}');
      return null;
    }

    final int sizeInBytes = file.fileSize!;
    final FakePeriodicProgress? fakeProgress = file.fileType == FileType.video
        ? FakePeriodicProgress(
            callback: (count) {
              progressCallback?.call(sizeInBytes, sizeInBytes);
            },
            duration: const Duration(milliseconds: 5000),
          )
        : null;
    try {
      fakeProgress?.start();
      await CryptoUtil.decryptFile(
        encryptedFilePath,
        decryptedFilePath,
        CryptoUtil.base642bin(file.fileDecryptionHeader!),
        getPublicFileKey(file),
      );
      fakeProgress?.stop();
      _logger.info('$logPrefix file saved at $decryptedFilePath');
    } catch (e, s) {
      fakeProgress?.stop();
      final metadata = await _getFileMetadataForLogging(
        file,
        encryptedFilePath,
      );
      _logger.severe("Critical: $logPrefix failed to decrypt, $metadata", e, s);
      return null;
    }
    return File(decryptedFilePath);
  } catch (e, s) {
    _logger.severe("$logPrefix failed to download", e, s);
    return null;
  }
}

Future<File?> downloadAndDecrypt(
  EnteFile file, {
  ProgressCallback? progressCallback,
  bool forceResumableDownload = false,
  bool throwOnFailure = false,
}) async {
  if (CollectionsService.instance.isSharedPublicLink(file.collectionID!)) {
    return await downloadAndDecryptPublicFile(
      file,
      progressCallback: progressCallback,
    );
  }

  final String logPrefix = 'File-${file.uploadedFileID}:';
  _logger.info(
    '$logPrefix starting download ${formatBytes(file.fileSize ?? 0)}',
  );
  final String tempDir = Configuration.instance.getTempDirectory();
  String encryptedFilePath = "$tempDir${file.generatedID}.encrypted";
  File encryptedFile = File(encryptedFilePath);

  final startTime = DateTime.now().millisecondsSinceEpoch;

  try {
    if (forceResumableDownload ||
        downloadManager.enableResumableDownload(file.fileSize)) {
      final DownloadResult result = await downloadManager.download(
        file.uploadedFileID!,
        file.displayName,
        file.fileSize!,
      );
      if (result.success) {
        encryptedFilePath = result.task.filePath!;
        encryptedFile = File(encryptedFilePath);
      } else {
        _logger.warning(
          '$logPrefix download failed ${result.task.error} ${result.task.status}',
        );
        if (throwOnFailure) {
          throw _toDownloadFailure(result.task.error);
        }
        return null;
      }
    } else {
      // If the file is small, download it directly to the final location
      final response = await NetworkClient.instance.downloadDio.download(
        file.downloadUrl,
        encryptedFilePath,
        options: Options(
          headers: {"X-Auth-Token": Configuration.instance.getToken()},
        ),
        onReceiveProgress: (a, b) {
          if (kDebugMode && a >= 0 && b >= 0) {
            // _logger.info(
            //   "$logPrefix download progress: ${formatBytes(a)} / ${formatBytes(b)}",
            // );
          }
          progressCallback?.call(a, b);
        },
      );
      if (response.statusCode != 200 || !encryptedFile.existsSync()) {
        _logger.warning('$logPrefix download failed ${response.toString()}');
        if (throwOnFailure) {
          throw DownloadFailedError(response.toString());
        }
        return null;
      }
    }

    final int sizeInBytes = file.fileSize ?? await encryptedFile.length();
    final double elapsedSeconds =
        (DateTime.now().millisecondsSinceEpoch - startTime) / 1000;
    final double speedInKBps = sizeInBytes / 1024.0 / elapsedSeconds;

    _logger.info(
      '$logPrefix download completed: ${formatBytes(sizeInBytes)}, avg speed: ${speedInKBps.toStringAsFixed(2)} KB/s',
    );

    final String decryptedFilePath = "$tempDir${file.generatedID}.decrypted";
    // As decryption can take time, emit fake progress for large files during
    // decryption
    final FakePeriodicProgress? fakeProgress = file.fileType == FileType.video
        ? FakePeriodicProgress(
            callback: (count) {
              progressCallback?.call(sizeInBytes, sizeInBytes);
            },
            duration: const Duration(milliseconds: 5000),
          )
        : null;
    try {
      // Start the periodic callback after initial 5 seconds
      fakeProgress?.start();
      await CryptoUtil.decryptFile(
        encryptedFilePath,
        decryptedFilePath,
        CryptoUtil.base642bin(file.fileDecryptionHeader!),
        getFileKey(file),
      );
      fakeProgress?.stop();
      _logger.info(
        '$logPrefix decryption completed (genID ${file.generatedID})',
      );
    } catch (e, s) {
      fakeProgress?.stop();
      final metadata = await _getFileMetadataForLogging(
        file,
        encryptedFilePath,
      );
      _logger.severe("Critical: $logPrefix failed to decrypt, $metadata", e, s);
      if (throwOnFailure) {
        throw DownloadFailedError("Failed to decrypt downloaded file");
      }
      return null;
    }
    await encryptedFile.delete();
    return File(decryptedFilePath);
  } catch (e, s) {
    _logger.severe("$logPrefix failed to download or decrypt", e, s);
    if (throwOnFailure) {
      if (e is DownloadFailedError) {
        rethrow;
      }
      if (_isStorageError(e)) {
        throw DownloadNotEnoughStorageError();
      }
      throw DownloadFailedError(e.toString());
    }
    return null;
  }
}

DownloadFailedError _toDownloadFailure(String? error) {
  if (error == DownloadManager.noConnectionError) {
    return DownloadNoConnectionError();
  }
  if (error == DownloadManager.notEnoughStorageError) {
    return DownloadNotEnoughStorageError();
  }
  if (error == DownloadManager.unavailableError) {
    return DownloadUnavailableError();
  }
  return DownloadFailedError(error ?? "Download failed");
}

bool _isStorageError(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    return code == 28 || code == 112;
  }
  if (error is DioException && error.error != null) {
    return _isStorageError(error.error!);
  }
  return false;
}

Future<String> _getFileMetadataForLogging(
  EnteFile file,
  String encFilePath,
) async {
  final buffer = StringBuffer();
  if (File(encFilePath).existsSync()) {
    buffer.write('encFileSha1: ${await computeSha1(encFilePath)}, ');
  } else {
    buffer.write('encFileSha1: file not found, ');
  }
  buffer.write('metadataVersion: ${file.metadataVersion}, ');
  buffer.write(
    'fileSize: ${file.fileSize != null ? file.fileSize! : "null"}, ',
  );
  buffer.write('viaMobile: ${(file.deviceFolder ?? "") != ""}');
  return buffer.toString();
}

// Note: callers that tap Download repeatedly on a public-link file
// (persistToFilesDB == false) may produce duplicate on-device copies, because
// the in-memory EnteFile they hold is not updated with the saved localID and
// LocalSyncService ingests the asset as a new local row rather than marking
// the existing remote entry. Revisit if this surfaces as a user complaint.
Future<void> downloadToGallery(
  EnteFile file, {
  bool forceResumableDownload = false,
  bool persistToFilesDB = true,
}) async {
  try {
    final FileType type = file.fileType;
    final bool downloadLivePhotoOnDroid =
        type == FileType.livePhoto && Platform.isAndroid;
    AssetEntity? savedAsset;
    final File? fileToSave = await getFile(
      file,
      forGalleryDownload: forceResumableDownload,
    );
    if (fileToSave == null) {
      throw DownloadFailedError("Unable to fetch file for gallery download");
    }
    final galleryTitle = _getGallerySaveTitle(file, fileToSave.path);
    // We use a lock to prevent synchronisation to occur while it is downloading
    // as this introduces wrong entry in FilesDB due to race condition
    // This is a fix for https://github.com/ente/ente/issues/4296
    await LocalSyncService.instance.getLock().synchronized(() async {
      //Disabling notifications for assets changing to insert the file into
      //files db before triggering a sync.
      await PhotoManager.stopChangeNotify();
      if (type == FileType.image) {
        savedAsset = await PhotoManager.editor.saveImageWithPath(
          fileToSave.path,
          title: galleryTitle,
        );
      } else if (type == FileType.video) {
        savedAsset = await PhotoManager.editor.saveVideo(
          fileToSave,
          title: _sanitizeAndroidVideoGalleryTitle(galleryTitle),
        );
      } else if (type == FileType.livePhoto) {
        final File? liveVideoFile = await getFileFromServer(
          file,
          liveVideo: true,
          forGalleryDownload: forceResumableDownload,
        );
        if (liveVideoFile == null) {
          throw AssertionError("Live video can not be null");
        }
        if (downloadLivePhotoOnDroid) {
          await _saveLivePhotoOnDroid(fileToSave, liveVideoFile, file);
        } else {
          savedAsset = await PhotoManager.editor.darwin.saveLivePhoto(
            imageFile: fileToSave,
            videoFile: liveVideoFile,
            title: galleryTitle,
          );
        }
      }

      if (savedAsset != null) {
        // Public-link downloads should be discovered by local sync so they are
        // materialized as true on-device files instead of remote/shared
        // entries in FilesDB.
        if (persistToFilesDB) {
          file.localID = savedAsset!.id;
          await FilesDB.instance.insert(file);
          Bus.instance.fire(
            LocalPhotosUpdatedEvent([file], source: "download"),
          );
        }
      } else if (!downloadLivePhotoOnDroid && savedAsset == null) {
        _logger.severe('Failed to save assert of type $type');
      }
    });
  } catch (e, s) {
    if (forceResumableDownload && _isStorageError(e)) {
      _logger.severe("Failed to save file due to storage limit", e, s);
      throw DownloadNotEnoughStorageError();
    }
    if (isPHPhotosUnsupportedResourceError(e)) {
      _logger.warning(
        "Failed to save file because Apple Photos rejected the resource",
        e,
        s,
      );
      throw DownloadFailedError(
        DownloadManager.applePhotosUnsupportedResourceError,
      );
    }
    _logger.severe("Failed to save file", e, s);
    rethrow;
  } finally {
    await PhotoManager.startChangeNotify();
    LocalSyncService.instance.checkAndSync().ignore();
  }
}

Future<void> _saveLivePhotoOnDroid(
  File image,
  File video,
  EnteFile enteFile,
) async {
  debugPrint("Downloading LivePhoto on Droid");
  final imageTitle = _getGallerySaveTitle(enteFile, image.path);
  AssetEntity? savedAsset =
      await (PhotoManager.editor.saveImageWithPath(
        image.path,
        title: imageTitle,
      )).catchError((err) {
        throw Exception("Failed to save image of live photo: $err");
      });
  IgnoredFile ignoreVideoFile = IgnoredFile(
    savedAsset.id,
    savedAsset.title ?? '',
    savedAsset.relativePath ?? 'remoteDownload',
    "remoteDownload",
  );
  await IgnoredFilesService.instance.cacheAndInsert([ignoreVideoFile]);
  final videoTitle = _sanitizeAndroidVideoGalleryTitle(
    file_path.basenameWithoutExtension(imageTitle) +
        file_path.extension(video.path),
  );
  savedAsset = (await (PhotoManager.editor.saveVideo(video, title: videoTitle))
      .catchError((err) {
        _logger.warning('Failed to save video $videoTitle of live photo');
        throw Exception("Failed to save video of live photo: $err");
      }));

  ignoreVideoFile = IgnoredFile(
    savedAsset.id,
    savedAsset.title ?? videoTitle,
    savedAsset.relativePath ?? 'remoteDownload',
    "remoteDownload",
  );
  await IgnoredFilesService.instance.cacheAndInsert([ignoreVideoFile]);
}
