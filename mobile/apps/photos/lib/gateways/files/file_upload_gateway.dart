import "package:dio/dio.dart";
import "package:photos/module/upload/model/multipart.dart";
import "package:photos/module/upload/model/upload_url.dart";

class FileUploadGateway {
  final Dio _enteDio;

  FileUploadGateway(this._enteDio);

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

  Future<void> validateUploadEligibility() async {
    try {
      await _enteDio.get("/files/upload-eligibility");
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Fall back for older servers without the eligibility endpoint.
        await _enteDio.get("/files/upload-urls", queryParameters: {"count": 1});
        return;
      }
      rethrow;
    }
  }

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
