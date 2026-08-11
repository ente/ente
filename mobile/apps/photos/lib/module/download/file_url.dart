import "package:dio/dio.dart";
import "package:photos/core/constants.dart";
import "package:photos/service_locator.dart";

const _v3RetryDelay = Duration(hours: 1);
DateTime? _v3RetryAfter;

enum FileUrlType {
  download,
  publicDownload,
  thumbnail,
  publicThumbnail,
  directDownload,
}

class FileUrl {
  static Future<String?> tryGetV3Url(
    Dio dio,
    int fileID,
    FileUrlType type, {
    required Map<String, dynamic> headers,
    CancelToken? cancelToken,
  }) async {
    final usesWorker =
        type != FileUrlType.directDownload &&
        endpointConfig.endpoint == kDefaultProductionEndpoint &&
        !flagService.disableCFWorker;
    if (usesWorker || (_v3RetryAfter?.isAfter(DateTime.now()) ?? false)) {
      return null;
    }

    final response = await dio.get<Object?>(
      _v3Path(fileID, type),
      options: Options(
        headers: headers,
        validateStatus: (status) => status == 200 || status == 404,
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode == 404) {
      // TODO(migration): Remove the legacy fallback once all supported Museum
      // versions provide the v3 file URL endpoints. Started 4 Aug 2026.
      _v3RetryAfter = DateTime.now().add(_v3RetryDelay);
      return null;
    }
    return (response.data as Map<String, dynamic>)["url"] as String;
  }

  static String getLegacyUrl(int fileID, FileUrlType type) {
    final endpoint = endpointConfig.endpoint;
    final disableWorker =
        endpoint != kDefaultProductionEndpoint || flagService.disableCFWorker;

    switch (type) {
      case FileUrlType.directDownload:
        return "$endpoint/files/download/$fileID";
      case FileUrlType.download:
        return disableWorker
            ? "$endpoint/files/download/$fileID"
            : "https://files.ente.com/?fileID=$fileID";

      case FileUrlType.publicDownload:
        return disableWorker
            ? "$endpoint/public-collection/files/download/$fileID"
            : "https://public-albums.ente.com/download/?fileID=$fileID";

      case FileUrlType.thumbnail:
        return disableWorker
            ? "$endpoint/files/preview/$fileID"
            : "https://thumbnails.ente.com/?fileID=$fileID";

      case FileUrlType.publicThumbnail:
        return disableWorker
            ? "$endpoint/public-collection/files/preview/$fileID"
            : "https://public-albums.ente.com/preview/?fileID=$fileID";
    }
  }

  static String _v3Path(int fileID, FileUrlType type) {
    switch (type) {
      case FileUrlType.download:
      case FileUrlType.directDownload:
        return "/files/download/v3/$fileID";
      case FileUrlType.publicDownload:
        return "/public-collection/files/download/v3/$fileID";
      case FileUrlType.thumbnail:
        return "/files/thumbnail/v3/$fileID";
      case FileUrlType.publicThumbnail:
        return "/public-collection/files/thumbnail/v3/$fileID";
    }
  }
}
