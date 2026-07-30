import "dart:async";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/errors.dart";
import "package:photos/gateways/files/file_upload_gateway.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/upload/model/upload_url.dart";

typedef UploadDelay = Future<void> Function(Duration duration);

class UploadCommitData {
  const UploadCommitData({
    required this.fileObjectKey,
    required this.fileDecryptionHeader,
    required this.fileSize,
    required this.thumbnailObjectKey,
    required this.thumbnailDecryptionHeader,
    required this.thumbnailSize,
    required this.encryptedMetadata,
    required this.metadataDecryptionHeader,
  });

  final String fileObjectKey;
  final String fileDecryptionHeader;
  final int fileSize;
  final String thumbnailObjectKey;
  final String thumbnailDecryptionHeader;
  final int thumbnailSize;
  final String encryptedMetadata;
  final String metadataDecryptionHeader;
}

class UploadTransport {
  UploadTransport(
    this._dio,
    this._gateway, {
    required bool Function() shouldUseUploadProxy,
    required void Function(Error) clearQueue,
    UploadDelay? delay,
  }) : _shouldUseUploadProxy = shouldUseUploadProxy,
       _clearQueue = clearQueue,
       _delay = delay ?? Future<void>.delayed;

  static const maximumAttempts = 4;
  static const apiRetryDelay = Duration(seconds: 3);

  final _logger = Logger("UploadTransport");
  final Dio _dio;
  final FileUploadGateway _gateway;
  final bool Function() _shouldUseUploadProxy;
  final void Function(Error) _clearQueue;
  final UploadDelay _delay;

  Future<String> uploadSinglePart(
    File file,
    int fileSize, {
    required String contentMd5,
  }) async {
    final uploadURL = await _getUploadURL(
      contentLength: fileSize,
      contentMd5: contentMd5,
    );
    return _putFile(
      uploadURL,
      file,
      fileSize,
      contentMd5: contentMd5,
      attempt: 1,
    );
  }

  Future<UploadURL> _getUploadURL({
    required int contentLength,
    required String contentMd5,
  }) async {
    if (contentMd5.isEmpty) {
      throw StateError("Missing MD5 for checksum-protected upload URL");
    }
    try {
      final uploadURL = await _gateway.getUploadUrl(
        contentLength: contentLength,
        contentMd5: contentMd5,
      );
      return uploadURL;
    } on DioException catch (error) {
      if (error.response?.statusCode == 402) {
        final subscriptionError = NoActiveSubscriptionError();
        _clearQueue(subscriptionError);
        throw subscriptionError;
      } else if (error.response?.statusCode == 426) {
        final storageError = StorageLimitExceededError();
        _clearQueue(storageError);
        throw storageError;
      }
      rethrow;
    }
  }

  Future<EnteFile> createFile({
    required EnteFile file,
    required int collectionID,
    required String encryptedKey,
    required String keyDecryptionNonce,
    required UploadCommitData data,
    Map<String, dynamic>? pubMagicMetadata,
  }) => _createFile(
    file: file,
    collectionID: collectionID,
    encryptedKey: encryptedKey,
    keyDecryptionNonce: keyDecryptionNonce,
    data: data,
    pubMagicMetadata: pubMagicMetadata,
    attempt: 1,
  );

  Future<EnteFile> updateFile({
    required EnteFile file,
    required UploadCommitData data,
  }) => _updateFile(file: file, data: data, attempt: 1);

  Future<String> _putFile(
    UploadURL uploadURL,
    File file,
    int fileSize, {
    required String contentMd5,
    required int attempt,
  }) async {
    if (contentMd5.isEmpty) {
      throw StateError("Missing MD5 for checksum-protected upload");
    }
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final fileName = basename(file.path);
    var bytesSent = 0;
    try {
      final useUploadProxy = _shouldUseUploadProxy();
      final headers = <String, dynamic>{Headers.contentLengthHeader: fileSize};
      if (useUploadProxy) {
        headers["UPLOAD-URL"] = uploadURL.url;
      }
      headers[useUploadProxy ? "CONTENT-MD5" : "Content-MD5"] = contentMd5;

      await _dio.put(
        useUploadProxy ? "$kUploadProxyEndpoint/file-upload" : uploadURL.url,
        data: file.openRead(),
        options: Options(headers: headers),
        onSendProgress: (sent, total) {
          bytesSent = sent;
        },
      );
      _logger.info(
        "Uploaded object $fileName of size: ${formatBytes(fileSize)} at speed: "
        "${(fileSize / (DateTime.now().millisecondsSinceEpoch - startTime)).toStringAsFixed(2)} KB/s",
      );
      return uploadURL.objectKey;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400 &&
              error.response?.data.toString().contains("BadDigest") == true ||
          error.response?.data.toString().contains("InvalidDigest") == true) {
        final recomputedMd5 = await computeMd5(file.path);
        throw BadMD5DigestError(
          "Failed ${error.response?.data}, sent: $contentMd5, "
          "computed: $recomputedMd5",
        );
      } else if (error.message?.startsWith("HttpException: Content size") ??
          false) {
        rethrow;
      } else if (attempt < maximumAttempts) {
        _logger.info(
          "Upload failed for $fileName after sending ${formatBytes(bytesSent)} "
          "of ${formatBytes(fileSize)}, retrying attempt ${attempt + 1}",
        );
        final newUploadURL = await _getUploadURL(
          contentLength: fileSize,
          contentMd5: contentMd5,
        );
        return _putFile(
          newUploadURL,
          file,
          fileSize,
          contentMd5: contentMd5,
          attempt: attempt + 1,
        );
      }
      _logger.info(
        "Failed to upload file $fileName after $attempt attempts",
        error,
      );
      rethrow;
    }
  }

  Future<EnteFile> _createFile({
    required EnteFile file,
    required int collectionID,
    required String encryptedKey,
    required String keyDecryptionNonce,
    required UploadCommitData data,
    required Map<String, dynamic>? pubMagicMetadata,
    required int attempt,
  }) async {
    try {
      final response = await _gateway.createFile(
        collectionID: collectionID,
        encryptedKey: encryptedKey,
        keyDecryptionNonce: keyDecryptionNonce,
        fileObjectKey: data.fileObjectKey,
        fileDecryptionHeader: data.fileDecryptionHeader,
        fileSize: data.fileSize,
        thumbnailObjectKey: data.thumbnailObjectKey,
        thumbnailDecryptionHeader: data.thumbnailDecryptionHeader,
        thumbnailSize: data.thumbnailSize,
        encryptedMetadata: data.encryptedMetadata,
        metadataDecryptionHeader: data.metadataDecryptionHeader,
        pubMagicMetadata: pubMagicMetadata == null
            ? null
            : Map<String, dynamic>.of(pubMagicMetadata),
      );
      file.uploadedFileID = response["id"];
      file.collectionID = collectionID;
      file.updationTime = response["updationTime"];
      file.ownerID = response["ownerID"];
      file.encryptedKey = encryptedKey;
      file.keyDecryptionNonce = keyDecryptionNonce;
      file.fileDecryptionHeader = data.fileDecryptionHeader;
      file.thumbnailDecryptionHeader = data.thumbnailDecryptionHeader;
      file.metadataDecryptionHeader = data.metadataDecryptionHeader;
      return file;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? -1;
      if (statusCode == 413) {
        throw FileTooLargeForPlanError();
      } else if (statusCode == 426) {
        _throwStorageLimitExceeded();
      } else if (attempt < maximumAttempts && statusCode == -1) {
        _logger.info(
          "Upload file (${file.tag}) failed, will retry in 3 seconds",
        );
        await _delay(apiRetryDelay);
        return _createFile(
          file: file,
          collectionID: collectionID,
          encryptedKey: encryptedKey,
          keyDecryptionNonce: keyDecryptionNonce,
          data: data,
          pubMagicMetadata: pubMagicMetadata,
          attempt: attempt + 1,
        );
      }
      _logger.severe("Failed to upload file ${file.tag}", error);
      rethrow;
    }
  }

  Future<EnteFile> _updateFile({
    required EnteFile file,
    required UploadCommitData data,
    required int attempt,
  }) async {
    try {
      final response = await _gateway.updateFile(
        fileID: file.uploadedFileID!,
        fileObjectKey: data.fileObjectKey,
        fileDecryptionHeader: data.fileDecryptionHeader,
        fileSize: data.fileSize,
        thumbnailObjectKey: data.thumbnailObjectKey,
        thumbnailDecryptionHeader: data.thumbnailDecryptionHeader,
        thumbnailSize: data.thumbnailSize,
        encryptedMetadata: data.encryptedMetadata,
        metadataDecryptionHeader: data.metadataDecryptionHeader,
      );
      file.uploadedFileID = response["id"];
      file.updationTime = response["updationTime"];
      file.fileDecryptionHeader = data.fileDecryptionHeader;
      file.thumbnailDecryptionHeader = data.thumbnailDecryptionHeader;
      file.metadataDecryptionHeader = data.metadataDecryptionHeader;
      return file;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? -1;
      if (statusCode == 426) {
        _throwStorageLimitExceeded();
      } else if (attempt < maximumAttempts && statusCode == -1) {
        _logger.info(
          "Update file (${file.tag}) failed, will retry in 3 seconds",
        );
        await _delay(apiRetryDelay);
        return _updateFile(file: file, data: data, attempt: attempt + 1);
      }
      _logger.severe("Failed to update file ${file.tag}", error);
      rethrow;
    }
  }

  Never _throwStorageLimitExceeded() {
    _clearQueue(StorageLimitExceededError());
    throw StorageLimitExceededError();
  }
}
