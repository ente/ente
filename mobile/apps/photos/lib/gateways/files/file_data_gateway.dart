import "package:dio/dio.dart";

class FileDataGateway {
  final Dio _enteDio;

  FileDataGateway(this._enteDio);

  Future<void> putFileData({
    required int fileID,
    required String type,
    required String encryptedData,
    required String decryptionHeader,
  }) async {
    await _enteDio.put(
      "/files/data",
      data: {
        "fileID": fileID,
        "type": type,
        "encryptedData": encryptedData,
        "decryptionHeader": decryptionHeader,
      },
    );
  }

  Future<Map<String, dynamic>> fetchFileData({
    required List<int> fileIDs,
    required String type,
  }) async {
    final response = await _enteDio.post(
      "/files/data/fetch",
      data: {"fileIDs": fileIDs, "type": type},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStatusDiff({
    required int lastUpdatedAt,
  }) async {
    final response = await _enteDio.post(
      "/files/data/status-diff",
      data: {"lastUpdatedAt": lastUpdatedAt},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> putVideoData({
    required int fileID,
    required String objectID,
    required int objectSize,
    required String playlist,
    required String playlistHeader,
    CancelToken? cancelToken,
  }) async {
    await _enteDio.put(
      "/files/video-data",
      data: {
        "fileID": fileID,
        "objectID": objectID,
        "objectSize": objectSize,
        "playlist": playlist,
        "playlistHeader": playlistHeader,
      },
      cancelToken: cancelToken,
    );
  }

  Future<({String url, String objectID})> getPreviewUploadUrl({
    required int fileID,
    required String type,
    CancelToken? cancelToken,
  }) async {
    final response = await _enteDio.get(
      "/files/data/preview-upload-url",
      queryParameters: {"fileID": fileID, "type": type},
      cancelToken: cancelToken,
    );
    return (
      url: response.data["url"] as String,
      objectID: response.data["objectID"] as String,
    );
  }

  Future<String> getPreview({required int fileID, required String type}) async {
    final response = await _enteDio.get(
      "/files/data/preview",
      queryParameters: {"fileID": fileID, "type": type},
    );
    return response.data["url"] as String;
  }

  Future<({String encryptedData, String decryptionHeader})>
  fetchSingleFileData({required int fileID, required String type}) async {
    final response = await _enteDio.get(
      "/files/data/fetch",
      queryParameters: {"fileID": fileID, "type": type},
    );
    return (
      encryptedData: response.data["data"]["encryptedData"] as String,
      decryptionHeader: response.data["data"]["decryptionHeader"] as String,
    );
  }

  Future<({String encryptedData, String decryptionHeader})>
  fetchPublicFileData({
    required String baseUrl,
    required int fileID,
    required String type,
    required Map<String, dynamic> headers,
    required Dio nonEnteDio,
  }) async {
    final response = await nonEnteDio.get(
      "$baseUrl/public-collection/files/data/fetch",
      queryParameters: {"fileID": fileID, "type": type},
      options: Options(headers: headers),
    );
    return (
      encryptedData: response.data["data"]["encryptedData"] as String,
      decryptionHeader: response.data["data"]["decryptionHeader"] as String,
    );
  }

  Future<String> getPublicPreview({
    required String baseUrl,
    required int fileID,
    required String type,
    required Map<String, dynamic> headers,
    required Dio nonEnteDio,
  }) async {
    final response = await nonEnteDio.get(
      "$baseUrl/public-collection/files/data/preview",
      queryParameters: {"fileID": fileID, "type": type},
      options: Options(headers: headers),
    );
    return response.data["url"] as String;
  }
}
