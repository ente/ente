import "dart:async";
import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/core/network/network.dart";
import "package:synchronized/synchronized.dart";

class RemoteAssetsService {
  static final _logger = Logger("RemoteAssetsService");
  static const int _resumableThresholdBytes = 10 * 1024 * 1024;

  bool checkRemovedOldAssets = false;

  RemoteAssetsService._privateConstructor();
  final StreamController<(String, int, int)> _progressController =
      StreamController<(String, int, int)>.broadcast();
  final Map<String, Lock> _assetLocks = {};

  Stream<(String, int, int)> get progressStream => _progressController.stream;

  static final RemoteAssetsService instance =
      RemoteAssetsService._privateConstructor();

  Future<File> getAsset(
    String remotePath, {
    bool refetch = false,
    String? expectedSha256,
  }) async {
    return _lockFor(remotePath).synchronized(() async {
      final path = await _getLocalPath(remotePath);
      final file = File(path);
      if (await file.exists() && !refetch) {
        _logger.info("Returning cached file for $remotePath");
        return file;
      }

      final tempFile = File(_tempPath(path));
      await _downloadFile(remotePath, tempFile.path);
      await _validateDownloadedFileSha256(tempFile, remotePath, expectedSha256);
      await _replaceFile(tempFile, file);
      await _deleteResumeMetadata(tempFile.path);
      return file;
    });
  }

  Future<String> getAssetPath(
    String remotePath, {
    bool refetch = false,
    String? expectedSha256,
  }) async {
    await cleanupOldModelsIfNeeded();
    final file = await getAsset(
      remotePath,
      refetch: refetch,
      expectedSha256: expectedSha256,
    );
    return file.path;
  }

  ///Returns asset if the remote asset is new compared to the local copy of it
  Future<File?> getAssetIfUpdated(
    String remotePath, {
    String? expectedSha256,
  }) async {
    return _lockFor(remotePath).synchronized(() async {
      try {
        final path = await _getLocalPath(remotePath);
        final file = File(path);
        final tempFile = File(_tempPath(path));

        if (!await file.exists()) {
          await _downloadFile(remotePath, tempFile.path);
          await _validateDownloadedFileSha256(
            tempFile,
            remotePath,
            expectedSha256,
          );
          await _replaceFile(tempFile, file);
          await _deleteResumeMetadata(tempFile.path);
          return file;
        }

        final existingFileSize = await file.length();
        await _downloadFile(remotePath, tempFile.path);
        await _validateDownloadedFileSha256(
          tempFile,
          remotePath,
          expectedSha256,
        );
        final newFileSize = await tempFile.length();
        if (existingFileSize != newFileSize) {
          await _replaceFile(tempFile, file);
          await _deleteResumeMetadata(tempFile.path);
          return file;
        }

        await _clearResumeArtifacts(tempFile.path);
        return null;
      } on _RemoteAssetHashMismatchException {
        rethrow;
      } catch (e) {
        _logger.warning("Error getting asset if updated", e);
        return null;
      }
    });
  }

  Future<bool> hasAsset(String remotePath) async {
    return _lockFor(remotePath).synchronized(() async {
      final path = await _getLocalPath(remotePath);
      return File(path).exists();
    });
  }

  Future<String> _getLocalPath(String remotePath) async {
    return (await getApplicationSupportDirectory()).path +
        "/assets/" +
        _urlToFileName(remotePath);
  }

  String _urlToFileName(String url) {
    // Remove the protocol part (http:// or https://)
    String fileName = url
        .replaceAll(RegExp(r'https?://'), '')
        // Replace all non-alphanumeric characters except for underscores and periods with an underscore
        .replaceAll(RegExp(r'[^\w\.]'), '_');
    // Optionally, you might want to trim the resulting string to a certain length

    // Replace periods with underscores for better readability, if desired
    fileName = fileName.replaceAll('.', '_');

    return fileName;
  }

  Future<void> _downloadFile(
    String url,
    String savePath, {
    bool allowResume = true,
  }) async {
    _logger.info("Downloading " + url);
    if (!allowResume && _shouldLogProbeDiagnosticsFor(url)) {
      _logger.info(
        "Retrying $url with single-shot download after disabling resumable mode",
      );
    }
    final probe = await _probeRemoteAsset(url, savePath);
    final useResumable = allowResume && _shouldUseResumableDownload(probe);
    if (probe != null &&
        probe.totalBytes > _resumableThresholdBytes &&
        _shouldLogProbeDiagnosticsFor(url)) {
      _logger.info(
        useResumable
            ? "Using resumable download for $url (${probe.totalBytes} bytes)"
            : "Using single-shot download for $url despite resumable "
                  "downloads being enabled (size: ${probe.totalBytes} bytes, "
                  "acceptsRanges: ${probe.acceptsRanges}, "
                  "strongEtag: ${probe.ifRangeValidator != null})",
      );
    }
    if (useResumable) {
      await _downloadFileResumable(url, savePath, probe!);
    } else {
      await _downloadFileSingleShot(url, savePath);
    }

    _logger.info("Downloaded " + url);
  }

  Future<void> _downloadFileSingleShot(String url, String savePath) async {
    await _clearResumeArtifacts(savePath);

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        _emitProgress(url, received, total);
      },
    );
  }

  Future<void> cleanupOldModelsIfNeeded() async {
    if (checkRemovedOldAssets) return;
    const oldModelNames = [
      "https://models.ente.io/clip-image-vit-32-float32.onnx",
      "https://models.ente.io/clip-text-vit-32-uint8.onnx",
      "https://models.ente.io/mobileclip_s2_image_opset18_rgba_sim.onnx",
      "https://models.ente.io/mobileclip_s2_image_opset18_rgba_opt.onnx",
      "https://models.ente.io/mobileclip_s2_text_int32.onnx",
      "https://models.ente.io/yolov5s_face_opset18_rgba_opt.onnx",
      "https://models.ente.io/yolov5s_face_opset18_rgba_opt_nosplits.onnx",
      "https://models.ente.io/yolov5s_face_640_640_dynamic.onnx",
      "https://models.ente.io/mobilefacenet_opset15.onnx",
      "https://models.ente.com/yolov5s_face_640_640_dynamic.onnx",
      "https://models.ente.com/mobilefacenet_opset15.onnx",
      "https://models.ente.io/mobileclip_s2_image.onnx",
      "https://models.ente.com/mobileclip_s2_image.onnx",
    ];

    await cleanupSelectedModels(oldModelNames);

    checkRemovedOldAssets = true;
    _logger.info("Old ML models cleaned up");
  }

  Future<void> cleanupSelectedModels(List<String> modelRemotePaths) async {
    for (final remotePath in modelRemotePaths) {
      final localPath = await _getLocalPath(remotePath);
      final hasArtifacts =
          await File(localPath).exists() ||
          await File(_tempPath(localPath)).exists() ||
          await File(_resumeMetadataPath(_tempPath(localPath))).exists();
      if (hasArtifacts) {
        _logger.info(
          'Removing unused ML model ${remotePath.split('/').last} at $localPath',
        );
        await _deleteAssetArtifacts(localPath);
      }
    }
  }

  Dio get _dio => NetworkClient.instance.downloadDio;

  bool get _resumableDownloadsEnabled => true;

  Lock _lockFor(String remotePath) =>
      _assetLocks.putIfAbsent(remotePath, Lock.new);

  String _tempPath(String finalPath) => "$finalPath.temp";

  String _resumeMetadataPath(String tempPath) => "$tempPath.resume.json";

  bool _shouldUseResumableDownload(_RemoteAssetProbe? probe) {
    if (!_resumableDownloadsEnabled || probe == null) {
      return false;
    }
    return probe.totalBytes > _resumableThresholdBytes && probe.canResume;
  }

  Future<_RemoteAssetProbe?> _probeRemoteAsset(
    String url,
    String savePath,
  ) async {
    if (!_resumableDownloadsEnabled) {
      return null;
    }

    try {
      final response = await _dio.head<void>(url);
      final probe = _RemoteAssetProbe.fromHeaders(url, response.headers);
      if (_shouldLogProbeDiagnosticsFor(url)) {
        final contentLength =
            response.headers.value(HttpHeaders.contentLengthHeader) ??
            "missing";
        final acceptRanges =
            response.headers.value("accept-ranges")?.trim() ?? "missing";
        final etag = response.headers.value(HttpHeaders.etagHeader)?.trim();
        if (probe == null) {
          _logger.info(
            "HEAD probe did not qualify $url for resumable download "
            "(contentLength: $contentLength, acceptRanges: $acceptRanges, "
            "strongEtag: ${_strongETag(etag) != null})",
          );
        } else {
          _logger.info(
            "HEAD probe succeeded for $url "
            "(contentLength: ${probe.totalBytes}, "
            "acceptsRanges: ${probe.acceptsRanges}, "
            "strongEtag: ${probe.ifRangeValidator != null})",
          );
        }
      }
      return probe;
    } catch (e, s) {
      final hasResumeArtifacts = await _hasCompleteResumeArtifacts(savePath);
      if (_isConnectionFailure(e) && hasResumeArtifacts) {
        if (_shouldLogProbeDiagnosticsFor(url)) {
          _logger.warning(
            "HEAD probe connection failed for $url, preserving resume "
            "artifacts for retry "
            "(tempBytes: ${await _safeFileLength(savePath)}, "
            "metadataExists: ${await _resumeMetadataExists(savePath)})",
            e,
            s,
          );
        }
        Error.throwWithStackTrace(e, s);
      }
      if (_shouldLogProbeDiagnosticsFor(url)) {
        _logger.warning(
          _isConnectionFailure(e)
              ? "HEAD probe connection failed for $url without complete "
                    "resume artifacts, falling back to single-shot download"
              : "HEAD probe failed for $url, falling back to single-shot "
                    "download",
          e,
          s,
        );
      } else {
        _logger.fine("HEAD probe failed for $url: $e");
      }
      return null;
    }
  }

  Future<void> _downloadFileResumable(
    String url,
    String savePath,
    _RemoteAssetProbe probe,
  ) async {
    final tempFile = File(savePath);
    final existingBytes = await _prepareTempFileForResume(tempFile, probe);
    if (existingBytes > 0 && _shouldLogProbeDiagnosticsFor(url)) {
      _logger.info(
        "Resuming download for $url from $existingBytes / ${probe.totalBytes} bytes",
      );
    }

    await _writeResumeMetadata(savePath, probe);

    if (existingBytes == probe.totalBytes) {
      _emitProgress(url, existingBytes, probe.totalBytes);
      return;
    }
    if (existingBytes > 0) {
      _emitProgress(url, existingBytes, probe.totalBytes);
    }

    try {
      await _startResumableDownload(url, savePath, probe, existingBytes);
    } on DioException catch (e, s) {
      if (existingBytes > 0 && _shouldRestartDownloadFromScratch(e)) {
        _logger.info("Restarting resumable download from scratch for $url");
        await _clearResumeArtifacts(savePath);
        await _downloadFile(url, savePath, allowResume: false);
        return;
      }
      if (_shouldLogProbeDiagnosticsFor(url)) {
        _logger.severe(
          "Resumable download failed for $url "
          "(startBytes: $existingBytes, "
          "tempBytes: ${await _safeFileLength(savePath)}, "
          "expectedBytes: ${probe.totalBytes})",
          e,
          s,
        );
      }
      rethrow;
    } on _ResumeValidationException catch (e, s) {
      if (existingBytes > 0) {
        _logger.warning(
          "Resumed download validation failed for $url, restarting from scratch",
          e,
          s,
        );
        await _clearResumeArtifacts(savePath);
        await _downloadFile(url, savePath, allowResume: false);
        return;
      }
      await _clearResumeArtifacts(savePath);
      rethrow;
    }
  }

  Future<int> _prepareTempFileForResume(
    File tempFile,
    _RemoteAssetProbe probe,
  ) async {
    final metadataFile = File(_resumeMetadataPath(tempFile.path));
    final tempExists = await tempFile.exists();
    final metadataExists = await metadataFile.exists();

    if (!tempExists) {
      if (metadataExists) {
        await metadataFile.delete();
      }
      return 0;
    }

    if (!metadataExists) {
      await _clearResumeArtifacts(tempFile.path);
      return 0;
    }

    final storedProbe = await _readResumeMetadata(tempFile.path);
    if (storedProbe == null || !storedProbe.matches(probe)) {
      await _clearResumeArtifacts(tempFile.path);
      return 0;
    }

    final existingBytes = await tempFile.length();
    if (existingBytes <= 0 || existingBytes > probe.totalBytes) {
      await _clearResumeArtifacts(tempFile.path);
      return 0;
    }

    return existingBytes;
  }

  Future<void> _startResumableDownload(
    String url,
    String savePath,
    _RemoteAssetProbe probe,
    int existingBytes,
  ) async {
    if (existingBytes > 0) {
      // Revalidate the representation at request time so we never append
      // bytes from a different asset revision to an older partial file.
      final response = await _dio.download(
        url,
        savePath,
        deleteOnError: false,
        fileAccessMode: FileAccessMode.append,
        options: Options(
          receiveDataWhenStatusError: false,
          headers: {
            HttpHeaders.rangeHeader: "bytes=$existingBytes-",
            HttpHeaders.ifRangeHeader: probe.ifRangeValidator!,
          },
          validateStatus: (status) => status == HttpStatus.partialContent,
        ),
        onReceiveProgress: (received, _) {
          _emitProgress(url, existingBytes + received, probe.totalBytes);
        },
      );
      _validateResumedResponseHeaders(
        response.headers,
        expectedStart: existingBytes,
        expectedTotalBytes: probe.totalBytes,
      );
      await _validateDownloadedFileLength(savePath, probe.totalBytes);
      return;
    }

    await _dio.download(
      url,
      savePath,
      deleteOnError: false,
      onReceiveProgress: (received, total) {
        _emitProgress(
          url,
          received,
          probe.totalBytes > 0 ? probe.totalBytes : total,
        );
      },
    );
    await _validateDownloadedFileLength(savePath, probe.totalBytes);
  }

  bool _shouldRestartDownloadFromScratch(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return false;
    }
    final statusCode = error.response?.statusCode;
    return statusCode == HttpStatus.ok ||
        statusCode == HttpStatus.requestedRangeNotSatisfiable;
  }

  Future<_RemoteAssetProbe?> _readResumeMetadata(String tempPath) async {
    final file = File(_resumeMetadataPath(tempPath));
    if (!await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      return _RemoteAssetProbe.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e, s) {
      _logger.warning("Failed to parse resume metadata for $tempPath", e, s);
      return null;
    }
  }

  Future<void> _writeResumeMetadata(
    String tempPath,
    _RemoteAssetProbe metadata,
  ) async {
    final file = File(_resumeMetadataPath(tempPath));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(metadata.toJson()), flush: true);
  }

  Future<void> _deleteResumeMetadata(String tempPath) async {
    await _deleteFileIfExists(File(_resumeMetadataPath(tempPath)));
  }

  Future<void> _validateDownloadedFileLength(
    String savePath,
    int expectedTotalBytes,
  ) async {
    final actualBytes = await File(savePath).length();
    if (actualBytes != expectedTotalBytes) {
      throw _ResumeValidationException(
        "Expected $expectedTotalBytes bytes, found $actualBytes",
      );
    }
  }

  Future<void> _validateDownloadedFileSha256(
    File file,
    String url,
    String? expectedSha256,
  ) async {
    if (expectedSha256 == null) {
      return;
    }

    try {
      await _validateExpectedSha256(file, url, expectedSha256);
    } on _RemoteAssetHashMismatchException {
      await _clearResumeArtifacts(file.path);
      rethrow;
    }
  }

  Future<void> _validateExpectedSha256(
    File file,
    String url,
    String expectedSha256,
  ) async {
    final actualSha256 = await _sha256Hex(file);
    if (!_hashesMatch(actualSha256, expectedSha256)) {
      throw _RemoteAssetHashMismatchException(
        url: url,
        expectedSha256: expectedSha256,
        actualSha256: actualSha256,
      );
    }
  }

  Future<String> _sha256Hex(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  bool _hashesMatch(String actualSha256, String expectedSha256) =>
      actualSha256.toLowerCase() == expectedSha256.toLowerCase();

  void _validateResumedResponseHeaders(
    Headers headers, {
    required int expectedStart,
    required int expectedTotalBytes,
  }) {
    final contentRange = headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange == null) {
      throw const _ResumeValidationException(
        "Missing Content-Range on resumed response",
      );
    }

    final match = RegExp(r"bytes\s+(\d+)-(\d+)/(\d+)").firstMatch(contentRange);
    final start = int.tryParse(match?.group(1) ?? "");
    final end = int.tryParse(match?.group(2) ?? "");
    final total = int.tryParse(match?.group(3) ?? "");
    if (start != expectedStart ||
        end == null ||
        end < expectedStart ||
        end >= expectedTotalBytes ||
        total != expectedTotalBytes) {
      throw _ResumeValidationException(
        "Unexpected Content-Range '$contentRange' for resume from "
        "$expectedStart of $expectedTotalBytes bytes",
      );
    }
  }

  Future<void> _clearResumeArtifacts(String tempPath) async {
    await _deleteFileIfExists(File(tempPath));
    await _deleteResumeMetadata(tempPath);
  }

  Future<bool> _hasCompleteResumeArtifacts(String tempPath) async {
    return await File(tempPath).exists() &&
        await File(_resumeMetadataPath(tempPath)).exists();
  }

  Future<bool> _resumeMetadataExists(String tempPath) async {
    return File(_resumeMetadataPath(tempPath)).exists();
  }

  Future<int> _safeFileLength(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return 0;
      }
      return await file.length();
    } catch (_) {
      return -1;
    }
  }

  bool _isConnectionFailure(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return true;
      }
      final innerError = error.error;
      if (innerError != null && !identical(innerError, error)) {
        return _isConnectionFailure(innerError);
      }
    }
    return false;
  }

  Future<void> _replaceFile(File source, File target) async {
    await target.parent.create(recursive: true);
    // Keep the swap atomic so readers never observe the target path missing.
    await source.rename(target.path);
  }

  Future<void> _deleteAssetArtifacts(String localPath) async {
    await _deleteFileIfExists(File(localPath));
    await _clearResumeArtifacts(_tempPath(localPath));
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _emitProgress(String url, int received, int total) {
    if (received > 0 && total > 0) {
      final boundedReceived = received > total ? total : received;
      _progressController.add((url, boundedReceived, total));
    } else if (kDebugMode) {
      debugPrint("$url Received: $received, Total: $total");
    }
  }

  bool _shouldLogProbeDiagnosticsFor(String url) {
    final host = Uri.tryParse(url)?.host;
    return host == "models.ente.com";
  }
}

String? _strongETag(String? etag) {
  if (etag == null || etag.startsWith("W/") || etag.startsWith("w/")) {
    return null;
  }
  return etag;
}

class _RemoteAssetProbe {
  const _RemoteAssetProbe({
    required this.url,
    required this.totalBytes,
    required this.acceptsRanges,
    required this.etag,
  });

  static _RemoteAssetProbe? fromHeaders(String url, Headers headers) {
    final contentLength = headers.value(HttpHeaders.contentLengthHeader);
    final totalBytes = int.tryParse(contentLength ?? "");
    if (totalBytes == null || totalBytes <= 0) {
      return null;
    }

    final acceptRanges = headers.value("accept-ranges")?.trim();
    return _RemoteAssetProbe(
      url: url,
      totalBytes: totalBytes,
      acceptsRanges: acceptRanges == "bytes",
      etag: headers.value(HttpHeaders.etagHeader)?.trim(),
    );
  }

  factory _RemoteAssetProbe.fromJson(Map<String, dynamic> json) {
    return _RemoteAssetProbe(
      url: json["url"] as String,
      totalBytes: json["totalBytes"] as int,
      acceptsRanges: false,
      etag: json["etag"] as String?,
    );
  }

  final String url;
  final int totalBytes;
  final bool acceptsRanges;
  final String? etag;

  String? get ifRangeValidator => _strongETag(etag);

  bool get canResume => acceptsRanges && ifRangeValidator != null;

  Map<String, dynamic> toJson() {
    return {"url": url, "totalBytes": totalBytes, "etag": etag};
  }

  bool matches(_RemoteAssetProbe other) {
    return url == other.url &&
        totalBytes == other.totalBytes &&
        ifRangeValidator == other.ifRangeValidator;
  }
}

class _ResumeValidationException implements Exception {
  const _ResumeValidationException(this.message);

  final String message;

  @override
  String toString() => "ResumeValidationException: $message";
}

class _RemoteAssetHashMismatchException implements Exception {
  const _RemoteAssetHashMismatchException({
    required this.url,
    required this.expectedSha256,
    required this.actualSha256,
  });

  final String url;
  final String expectedSha256;
  final String actualSha256;

  @override
  String toString() {
    return "RemoteAssetHashMismatchException: Expected SHA-256 "
        "$expectedSha256 for $url, found $actualSha256";
  }
}
