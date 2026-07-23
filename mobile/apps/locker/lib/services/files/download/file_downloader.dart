import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_network/network.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/files/download/models/task.dart';
import 'package:locker/services/files/download/service_locator.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger("FileDownloader");

String _getTemporaryDecryptedFilePath(EnteFile file) {
  final String tempDir = Configuration.instance.getTempDirectory();
  final String safeDisplayName = p.basename(file.displayName);
  return "$tempDir${file.uploadedFileID}_$safeDisplayName";
}

/// Returns the encrypted offline blob for this device, downloading it only when
/// a usable local copy does not already exist.
Future<File> ensureEncryptedOfflineCopy(
  EnteFile file, {
  ProgressCallback? progressCallback,
}) async {
  final existingFile = await getCurrentOfflineEncryptedCopy(file);
  final String logPrefix = 'File-${file.uploadedFileID}:';
  if (existingFile != null) {
    final existingSize = await existingFile.length();
    progressCallback?.call(existingSize, existingSize);
    return existingFile;
  }

  final String tempDir = Configuration.instance.getTempDirectory();
  final String tempEncryptedFilePath =
      "$tempDir${file.uploadedFileID}.encrypted";
  final String finalEncryptedFilePath = await getOfflineEncryptedFilePath(file);
  final File finalEncryptedFile = File(finalEncryptedFilePath);

  String encryptedFilePath = tempEncryptedFilePath;
  File encryptedFile = File(encryptedFilePath);

  try {
    if (downloadManager.enableResumableDownload(file.fileSize)) {
      final DownloadResult result = await downloadManager.download(
        file.uploadedFileID!,
        file.displayName,
        file.fileSize!,
      );
      if (!result.success || result.task.filePath == null) {
        throw Exception(
          '$logPrefix download failed ${result.task.error} ${result.task.status}',
        );
      }
      encryptedFilePath = result.task.filePath!;
      encryptedFile = File(encryptedFilePath);
      final encryptedSize = await encryptedFile.length();
      progressCallback?.call(encryptedSize, encryptedSize);
    } else {
      late final Response response;
      try {
        response = await Network.instance.getDio().download(
          file.downloadUrl,
          tempEncryptedFilePath,
          options: Options(
            headers: {"X-Auth-Token": Configuration.instance.getToken()},
          ),
          onReceiveProgress: progressCallback,
        );
      } catch (e) {
        try {
          if (await encryptedFile.exists()) {
            await encryptedFile.delete();
          }
        } catch (_) {}
        rethrow;
      }

      if (response.statusCode != 200 || !await encryptedFile.exists()) {
        throw Exception('$logPrefix download failed ${response.toString()}');
      }
    }

    if (await finalEncryptedFile.exists()) {
      await finalEncryptedFile.delete();
    }

    if (encryptedFilePath == finalEncryptedFilePath) {
      return finalEncryptedFile;
    }

    await encryptedFile.copy(finalEncryptedFilePath);
    await encryptedFile.delete();
    return finalEncryptedFile;
  } catch (e, s) {
    _logger.severe('$logPrefix failed to ensure encrypted offline copy', e, s);
    try {
      if (await encryptedFile.exists() &&
          encryptedFile.path != finalEncryptedFilePath) {
        await encryptedFile.delete();
      }
    } catch (_) {}
    try {
      if (await finalEncryptedFile.exists()) {
        await finalEncryptedFile.delete();
      }
    } catch (_) {}
    rethrow;
  }
}

Future<File?> openFile(
  EnteFile file,
  Uint8List fileKey, {
  ProgressCallback? progressCallback,
  bool useTemporaryDecryptedFile = false,
}) async {
  if (!LockerDB.instance.isFileMarkedOffline(file)) {
    return downloadAndDecrypt(
      file,
      fileKey,
      progressCallback: progressCallback,
      shouldUseCache: !useTemporaryDecryptedFile,
    );
  }

  try {
    final offlineEncryptedFile = await ensureEncryptedOfflineCopy(
      file,
      progressCallback: progressCallback,
    );
    final String logPrefix = 'File-${file.uploadedFileID}:';
    final int startTime = DateTime.now().millisecondsSinceEpoch;
    final String decryptedFilePath = useTemporaryDecryptedFile
        ? _getTemporaryDecryptedFilePath(file)
        : getCachedDecryptedFilePath(file);
    final File decryptedFile = File(decryptedFilePath);
    final int sizeInBytes =
        file.fileSize ?? await offlineEncryptedFile.length();

    try {
      if (await decryptedFile.exists()) {
        final decryptedSize = await decryptedFile.length();
        if (decryptedSize > 0) {
          progressCallback?.call(decryptedSize, decryptedSize);
          return decryptedFile;
        }
        await decryptedFile.delete();
      }

      await CryptoUtil.decryptFile(
        offlineEncryptedFile.path,
        decryptedFilePath,
        CryptoUtil.base642bin(file.fileDecryptionHeader!),
        fileKey,
      );

      final double elapsedSeconds =
          (DateTime.now().millisecondsSinceEpoch - startTime) / 1000;
      final double speedInKBps = elapsedSeconds <= 0
          ? 0
          : sizeInBytes / 1024.0 / elapsedSeconds;
      _logger.info(
        '$logPrefix local decrypt completed: ${formatBytes(sizeInBytes)}, avg speed: ${speedInKBps.toStringAsFixed(2)} KB/s',
      );
      return decryptedFile;
    } catch (e, s) {
      _logger.severe("Critical: $logPrefix failed to decrypt", e, s);
      try {
        if (await decryptedFile.exists()) {
          await decryptedFile.delete();
        }
      } catch (_) {}
    }
  } catch (e, s) {
    _logger.warning(
      'Failed to use offline encrypted copy for ${file.uploadedFileID}, falling back to direct download',
      e,
      s,
    );
  }
  return downloadAndDecrypt(
    file,
    fileKey,
    progressCallback: progressCallback,
    shouldUseCache: !useTemporaryDecryptedFile,
  );
}

Future<File?> downloadAndDecrypt(
  EnteFile file,
  Uint8List fileKey, {
  ProgressCallback? progressCallback,
  bool shouldFakeProgress = false,
  bool shouldUseCache = false,
}) async {
  final String logPrefix = 'File-${file.uploadedFileID}:';
  _logger.info('$logPrefix starting download');

  final String tempDir = Configuration.instance.getTempDirectory();

  final String cachedEncryptedFilePath = getCachedEncryptedFilePath(file);
  final String cachedDecryptedFilePath = getCachedDecryptedFilePath(file);
  final String tempEncryptedFilePath =
      "$tempDir${file.uploadedFileID}.encrypted";
  String encryptedFilePath = tempEncryptedFilePath;
  File encryptedFile = File(encryptedFilePath);
  bool usingCachedEncryptedFile = false;
  bool downloadedFreshEncryptedFile = false;

  final String decryptedFilePath = shouldUseCache
      ? cachedDecryptedFilePath
      : _getTemporaryDecryptedFilePath(file);
  final File decryptedFile = File(decryptedFilePath);

  final startTime = DateTime.now().millisecondsSinceEpoch;

  try {
    if (shouldUseCache && await decryptedFile.exists()) {
      final decryptedSize = await decryptedFile.length();
      if (decryptedSize > 0) {
        progressCallback?.call(decryptedSize, decryptedSize);
        return decryptedFile;
      } else {
        await decryptedFile.delete();
      }
    }

    bool shouldDownload = true;
    if (shouldUseCache) {
      final cachedEncryptedFile = File(cachedEncryptedFilePath);
      if (await cachedEncryptedFile.exists()) {
        final encryptedSize = await cachedEncryptedFile.length();
        if (encryptedSize > 0) {
          shouldDownload = false;
          usingCachedEncryptedFile = true;
          encryptedFilePath = cachedEncryptedFilePath;
          encryptedFile = cachedEncryptedFile;
        } else {
          await cachedEncryptedFile.delete();
        }
      }
    }

    if (shouldDownload) {
      if (downloadManager.enableResumableDownload(file.fileSize)) {
        final DownloadResult result = await downloadManager.download(
          file.uploadedFileID!,
          file.displayName,
          file.fileSize!,
        );
        if (result.success) {
          encryptedFilePath = result.task.filePath!;
          encryptedFile = File(encryptedFilePath);
          downloadedFreshEncryptedFile = true;
        } else {
          _logger.warning(
            '$logPrefix download failed ${result.task.error} ${result.task.status}',
          );
          return null;
        }
      } else {
        final response = await Network.instance.getDio().download(
          file.downloadUrl,
          tempEncryptedFilePath,
          options: Options(
            headers: {"X-Auth-Token": Configuration.instance.getToken()},
          ),
          onReceiveProgress: (a, b) {
            progressCallback?.call(a, b);
          },
        );
        encryptedFilePath = tempEncryptedFilePath;
        encryptedFile = File(encryptedFilePath);
        downloadedFreshEncryptedFile = true;
        if (response.statusCode != 200 || !encryptedFile.existsSync()) {
          _logger.warning('$logPrefix download failed ${response.toString()}');
          return null;
        }
      }
    }

    final int sizeInBytes = file.fileSize ?? await encryptedFile.length();
    final double elapsedSeconds =
        (DateTime.now().millisecondsSinceEpoch - startTime) / 1000;
    final double speedInKBps = sizeInBytes / 1024.0 / elapsedSeconds;

    _logger.info(
      '$logPrefix download completed: ${formatBytes(sizeInBytes)}, avg speed: ${speedInKBps.toStringAsFixed(2)} KB/s',
    );

    final FakePeriodicProgress? fakeProgress = shouldFakeProgress
        ? FakePeriodicProgress(
            callback: (_) {
              progressCallback?.call(sizeInBytes, sizeInBytes);
            },
            duration: const Duration(milliseconds: 5000),
          )
        : null;
    try {
      fakeProgress?.start();
      if (await decryptedFile.exists()) {
        await decryptedFile.delete();
      }
      await CryptoUtil.decryptFile(
        encryptedFilePath,
        decryptedFilePath,
        CryptoUtil.base642bin(file.fileDecryptionHeader!),
        fileKey,
      );
      fakeProgress?.stop();
    } catch (e, s) {
      fakeProgress?.stop();
      _logger.severe("Critical: $logPrefix failed to decrypt", e, s);
      try {
        if (await decryptedFile.exists()) {
          await decryptedFile.delete();
        }
      } catch (_) {}
      if (downloadedFreshEncryptedFile) {
        try {
          await encryptedFile.delete();
        } catch (_) {}
      } else if (usingCachedEncryptedFile) {
        try {
          await encryptedFile.delete();
        } catch (_) {}
      }
      return null;
    }

    if (shouldUseCache && downloadedFreshEncryptedFile) {
      try {
        if (encryptedFilePath != cachedEncryptedFilePath) {
          await encryptedFile.copy(cachedEncryptedFilePath);
          await encryptedFile.delete();
        }
      } catch (e, s) {
        _logger.warning(
          '$logPrefix failed to persist encrypted file cache',
          e,
          s,
        );
      }
    } else if (!shouldUseCache) {
      await encryptedFile.delete();
    }
    return decryptedFile;
  } catch (e, s) {
    _logger.severe("$logPrefix failed to download or decrypt", e, s);
    return null;
  }
}
