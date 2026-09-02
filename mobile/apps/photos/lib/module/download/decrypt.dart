import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/download_error.dart';
import 'package:photos/module/download/file_url.dart';
import 'package:photos/module/download/manager.dart';
import 'package:photos/module/download/task.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/utils/device_storage_error.dart';
import 'package:photos/utils/file_key.dart';

export 'package:photos/module/download/download_error.dart';

final _logger = Logger('file_download_util');

Future<File?> _downloadAndDecryptPublicFile(
  EnteFile file, {
  ProgressCallback? progressCallback,
}) async {
  final logPrefix = 'Public File-${file.uploadedFileID}:';
  _logger.info(
    '$logPrefix starting download ${formatBytes(file.fileSize ?? 0)}',
  );

  final tempDir = Configuration.instance.getTempDirectory();
  final encryptedFilePath = '$tempDir${file.uploadedFileID}.encrypted';
  final decryptedFilePath = '$tempDir${file.uploadedFileID}.decrypted';

  try {
    final headers = CollectionsService.instance.publicCollectionHeaders(
      file.collectionID!,
    );
    final signedUrl = await FileUrl.tryGetV3Url(
      NetworkClient.instance.enteDio,
      file.uploadedFileID!,
      FileUrlType.publicDownload,
      headers: headers,
    );
    final response = await NetworkClient.instance.downloadDio.download(
      signedUrl ??
          FileUrl.getLegacyUrl(
            file.uploadedFileID!,
            FileUrlType.publicDownload,
          ),
      encryptedFilePath,
      options: Options(
        headers: signedUrl == null ? headers : null,
        responseType: ResponseType.bytes,
      ),
      onReceiveProgress: (received, total) {
        progressCallback?.call(received, total);
      },
    );

    if (response.statusCode != 200) {
      _logger.warning('$logPrefix download failed ${response.toString()}');
      return null;
    }

    final sizeInBytes = file.fileSize!;
    final fakeProgress = file.fileType == FileType.video
        ? FakePeriodicProgress(
            callback: (_) {
              progressCallback?.call(sizeInBytes, sizeInBytes);
            },
            duration: const Duration(seconds: 5),
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
    } catch (error, stackTrace) {
      fakeProgress?.stop();
      final metadata = await _fileMetadataForLogging(file, encryptedFilePath);
      _logger.severe(
        'Critical: $logPrefix failed to decrypt, ${metadata.log}',
        error,
        stackTrace,
      );
      if (error is StreamPullErr && metadata.encryptedFileSha1 != null) {
        throw DownloadDecryptionError(metadata.encryptedFileSha1!);
      }
      return null;
    }
    return File(decryptedFilePath);
  } catch (error, stackTrace) {
    if (error is DownloadDecryptionError) {
      rethrow;
    }
    _logger.severe('$logPrefix failed to download', error, stackTrace);
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
    return _downloadAndDecryptPublicFile(
      file,
      progressCallback: progressCallback,
    );
  }

  final logPrefix = 'File-${file.uploadedFileID}:';
  _logger.info(
    '$logPrefix starting download ${formatBytes(file.fileSize ?? 0)}',
  );
  final tempDir = Configuration.instance.getTempDirectory();
  var encryptedFilePath = '$tempDir${file.generatedID}.encrypted';
  var encryptedFile = File(encryptedFilePath);

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
      final headers = <String, dynamic>{
        'X-Auth-Token': Configuration.instance.getToken(),
      };
      final signedUrl = await FileUrl.tryGetV3Url(
        NetworkClient.instance.enteDio,
        file.uploadedFileID!,
        FileUrlType.download,
        headers: headers,
      );
      final response = await NetworkClient.instance.downloadDio.download(
        signedUrl ?? file.downloadUrl,
        encryptedFilePath,
        options: Options(headers: signedUrl == null ? headers : null),
        onReceiveProgress: (received, total) {
          progressCallback?.call(received, total);
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

    final sizeInBytes = file.fileSize ?? await encryptedFile.length();
    final elapsedSeconds =
        (DateTime.now().millisecondsSinceEpoch - startTime) / 1000;
    final speedInKBps = sizeInBytes / 1024.0 / elapsedSeconds;

    _logger.info(
      '$logPrefix download completed: ${formatBytes(sizeInBytes)}, avg speed: ${speedInKBps.toStringAsFixed(2)} KB/s',
    );

    final decryptedFilePath = '$tempDir${file.generatedID}.decrypted';
    final fakeProgress = file.fileType == FileType.video
        ? FakePeriodicProgress(
            callback: (_) {
              progressCallback?.call(sizeInBytes, sizeInBytes);
            },
            duration: const Duration(seconds: 5),
          )
        : null;
    try {
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
    } catch (error, stackTrace) {
      fakeProgress?.stop();
      final metadata = await _fileMetadataForLogging(file, encryptedFilePath);
      _logger.severe(
        'Critical: $logPrefix failed to decrypt, ${metadata.log}',
        error,
        stackTrace,
      );
      await _deleteFailedDecryptionArtifacts(
        file,
        encryptedFilePath,
        decryptedFilePath,
      );
      if (error is StreamPullErr && metadata.encryptedFileSha1 != null) {
        throw DownloadDecryptionError(metadata.encryptedFileSha1!);
      }
      if (throwOnFailure) {
        throw DownloadFailedError('Failed to decrypt downloaded file');
      }
      return null;
    }
    await encryptedFile.delete();
    return File(decryptedFilePath);
  } catch (error, stackTrace) {
    if (error is DownloadDecryptionError) {
      rethrow;
    }
    _logger.severe(
      '$logPrefix failed to download or decrypt',
      error,
      stackTrace,
    );
    if (throwOnFailure) {
      if (error is DownloadFailedError) {
        rethrow;
      }
      if (isDeviceStorageFullError(error)) {
        throw const DeviceStorageFullException();
      }
      throw DownloadFailedError(error.toString());
    }
    return null;
  }
}

Exception _toDownloadFailure(String? error) {
  if (error == DownloadManager.noConnectionError) {
    return DownloadNoConnectionError();
  }
  if (error == DownloadManager.notEnoughStorageError) {
    return const DeviceStorageFullException();
  }
  if (error == DownloadManager.unavailableError) {
    return DownloadUnavailableError();
  }
  return DownloadFailedError(error ?? 'Download failed');
}

Future<({String log, String? encryptedFileSha1})> _fileMetadataForLogging(
  EnteFile file,
  String encryptedFilePath,
) async {
  final buffer = StringBuffer();
  final encryptedFile = File(encryptedFilePath);
  String? encryptedFileSha1;
  if (encryptedFile.existsSync()) {
    encryptedFileSha1 = (await sha1.bind(encryptedFile.openRead()).first)
        .toString();
    buffer.write('encFileSha1: $encryptedFileSha1, ');
  } else {
    buffer.write('encFileSha1: file not found, ');
  }
  buffer.write('metadataVersion: ${file.metadataVersion}, ');
  buffer.write('fileSize: ${file.fileSize ?? "null"}, ');
  buffer.write('viaMobile: ${(file.deviceFolder ?? '') != ''}');
  return (log: buffer.toString(), encryptedFileSha1: encryptedFileSha1);
}

Future<void> _deleteFailedDecryptionArtifacts(
  EnteFile file,
  String encryptedFilePath,
  String decryptedFilePath,
) async {
  try {
    await downloadManager.cancel(file.uploadedFileID!);
    for (final path in [encryptedFilePath, decryptedFilePath]) {
      final artifact = File(path);
      if (await artifact.exists()) {
        await artifact.delete();
      }
    }
  } catch (error, stackTrace) {
    _logger.warning(
      'Failed to delete decryption artifacts for File-${file.uploadedFileID}',
      error,
      stackTrace,
    );
  }
}
