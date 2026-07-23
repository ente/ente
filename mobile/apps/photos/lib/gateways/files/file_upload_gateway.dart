import "package:dio/dio.dart";
import "package:photos/module/upload/model/multipart.dart";
import "package:photos/module/upload/model/upload_url.dart";

/// Gateway for file upload API endpoints.
///
/// Handles upload URL generation and file creation/update operations.
class FileUploadGateway {
  final Dio _enteDio;

  FileUploadGateway(this._enteDio);

  /// Gets a checksum-protected upload URL for a single file.
  ///
  /// [contentLength] - The size of the file in bytes.
  /// [contentMd5] - The MD5 hash of the file content.
  ///
  /// Returns an [UploadURL] containing the presigned URL and object key.
  Future<UploadURL> getUploadUrl({
    required int contentLength,
    required String contentMd5,
  }) async {
    final response = await _enteDio.post(
      "/files/upload-url",
      data: {"contentLength": contentLength, "contentMD5": contentMd5},
    );
    return UploadURL.fromMap((response.data as Map).cast<String, dynamic>());
  }

  /// Validates that the user can upload without minting an upload URL.
  ///
  /// Throws 402 (no subscription) or 426 (storage exceeded) on failure.
  /// Falls back to the legacy upload-urls endpoint when the eligibility
  /// endpoint is not available on older servers.
  Future<void> validateUploadEligibility() async {
    try {
      await _enteDio.get("/files/upload-eligibility");
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        await _enteDio.get("/files/upload-urls", queryParameters: {"count": 1});
        return;
      }
      rethrow;
    }
  }

  /// Creates a new file entry on the server after upload.
  ///
  /// [collectionID] - The collection to add the file to.
  /// [encryptedKey] - The encrypted file key.
  /// [keyDecryptionNonce] - The nonce for decrypting the file key.
  /// [fileObjectKey] - The S3 object key for the file.
  /// [fileDecryptionHeader] - The header for decrypting the file.
  /// [fileSize] - The size of the encrypted file.
  /// [thumbnailObjectKey] - The S3 object key for the thumbnail.
  /// [thumbnailDecryptionHeader] - The header for decrypting the thumbnail.
  /// [thumbnailSize] - The size of the encrypted thumbnail.
  /// [encryptedMetadata] - The encrypted file metadata.
  /// [metadataDecryptionHeader] - The header for decrypting metadata.
  /// [pubMagicMetadata] - Optional public magic metadata.
  ///
  /// Returns a map containing the file ID, owner ID, and updation time.
  Future<Map<String, dynamic>> createFile({
    required int collectionID,
    required String encryptedKey,
    required String keyDecryptionNonce,
    required String fileObjectKey,
    required String fileDecryptionHeader,
    required int fileSize,
    required String thumbnailObjectKey,
    required String thumbnailDecryptionHeader,
    required int thumbnailSize,
    required String encryptedMetadata,
    required String metadataDecryptionHeader,
    Map<String, dynamic>? pubMagicMetadata,
  }) async {
    final request = {
      "collectionID": collectionID,
      "encryptedKey": encryptedKey,
      "keyDecryptionNonce": keyDecryptionNonce,
      "file": {
        "objectKey": fileObjectKey,
        "decryptionHeader": fileDecryptionHeader,
        "size": fileSize,
      },
      "thumbnail": {
        "objectKey": thumbnailObjectKey,
        "decryptionHeader": thumbnailDecryptionHeader,
        "size": thumbnailSize,
      },
      "metadata": {
        "encryptedData": encryptedMetadata,
        "decryptionHeader": metadataDecryptionHeader,
      },
    };
    if (pubMagicMetadata != null) {
      request["pubMagicMetadata"] = pubMagicMetadata;
    }
    final response = await _enteDio.post("/files", data: request);
    return response.data as Map<String, dynamic>;
  }

  /// Updates an existing file entry on the server.
  ///
  /// [fileID] - The uploaded file ID to update.
  /// [fileObjectKey] - The new S3 object key for the file.
  /// [fileDecryptionHeader] - The header for decrypting the file.
  /// [fileSize] - The size of the encrypted file.
  /// [thumbnailObjectKey] - The S3 object key for the thumbnail.
  /// [thumbnailDecryptionHeader] - The header for decrypting the thumbnail.
  /// [thumbnailSize] - The size of the encrypted thumbnail.
  /// [encryptedMetadata] - The encrypted file metadata.
  /// [metadataDecryptionHeader] - The header for decrypting metadata.
  ///
  /// Returns a map containing the file ID and updation time.
  Future<Map<String, dynamic>> updateFile({
    required int fileID,
    required String fileObjectKey,
    required String fileDecryptionHeader,
    required int fileSize,
    required String thumbnailObjectKey,
    required String thumbnailDecryptionHeader,
    required int thumbnailSize,
    required String encryptedMetadata,
    required String metadataDecryptionHeader,
  }) async {
    final request = {
      "id": fileID,
      "file": {
        "objectKey": fileObjectKey,
        "decryptionHeader": fileDecryptionHeader,
        "size": fileSize,
      },
      "thumbnail": {
        "objectKey": thumbnailObjectKey,
        "decryptionHeader": thumbnailDecryptionHeader,
        "size": thumbnailSize,
      },
      "metadata": {
        "encryptedData": encryptedMetadata,
        "decryptionHeader": metadataDecryptionHeader,
      },
    };
    final response = await _enteDio.put("/files/update", data: request);
    return response.data as Map<String, dynamic>;
  }

  /// Gets a checksum-protected multipart upload URL.
  ///
  /// [contentLength] - The total size of the file in bytes.
  /// [partLength] - The size of each part.
  /// [partMd5s] - List of MD5 hashes for each part.
  ///
  /// Returns a [MultipartUploadURLs] containing URLs for all parts.
  Future<MultipartUploadURLs> getMultipartUploadUrl({
    required int contentLength,
    required int partLength,
    required List<String> partMd5s,
  }) async {
    final response = await _enteDio.post(
      "/files/multipart-upload-url",
      data: {
        "contentLength": contentLength,
        "partLength": partLength,
        "partMd5s": partMd5s,
      },
    );
    return MultipartUploadURLs.fromMap(
      (response.data as Map).cast<String, dynamic>(),
    );
  }
}
