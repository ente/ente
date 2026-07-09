import "package:dio/dio.dart";
import "package:photos/core/constants.dart";

class ApiResponseShapeInterceptor extends Interceptor {
  ApiResponseShapeInterceptor(this._endpoint);

  final String _endpoint;

  static final RegExp _collectionObjectPath = RegExp(
    r"^/collections(?:/\d+|/v2(?:/diff)?)?$",
  );

  static const Set<String> _objectPaths = {
    "/billing/user-plans",
    "/collection-actions/delete-suggestions",
    "/collection-actions/pending-remove",
    "/comments-reactions/updated-at",
    "/files/data/fetch",
    "/files/data/preview",
    "/files/data/preview-upload-url",
    "/files/data/status-diff",
    "/memory-share",
    "/public-collection/files/data/fetch",
    "/public-collection/files/data/preview",
    "/user-entity/entity/diff",
    "/users/details/v2",
  };

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final routePath = _objectRoutePath(response.requestOptions.uri.path);
    if (routePath == null || !_isConfiguredEndpoint(response.requestOptions)) {
      handler.next(response);
      return;
    }
    final data = response.data;
    if (data is! String) {
      handler.next(response);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: ApiResponseFormatException(response, routePath, data),
      ),
    );
  }

  bool _isConfiguredEndpoint(RequestOptions options) {
    final endpointUri = Uri.tryParse(_endpoint);
    return endpointUri != null &&
        options.uri.scheme == endpointUri.scheme &&
        options.uri.host == endpointUri.host;
  }

  static String? _objectRoutePath(String path) {
    final normalizedPath = path.length > 1 && path.endsWith("/")
        ? path.substring(0, path.length - 1)
        : path;
    if (_objectPaths.contains(normalizedPath)) return normalizedPath;
    if (!_collectionObjectPath.hasMatch(normalizedPath)) return null;
    return RegExp(r"^/collections/\d+$").hasMatch(normalizedPath)
        ? "/collections/:collectionID"
        : normalizedPath;
  }
}

class ApiResponseFormatException implements Exception {
  ApiResponseFormatException(
    Response<dynamic> response,
    this.path,
    Object? actual,
  ) : shouldReport =
          response.requestOptions.uri.host ==
          Uri.parse(kDefaultProductionEndpoint).host,
      statusCode = response.statusCode,
      contentType = response.headers.value("content-type"),
      requestID =
          response.headers.value("x-request-id") ??
          response.requestOptions.headers["x-request-id"]?.toString(),
      cfRay = response.headers.value("cf-ray"),
      redirectCount = response.redirects.length,
      actualType = actual == null ? "null" : actual.runtimeType.toString(),
      bodyLength = actual is String ? actual.length : null;

  final String path;
  final bool shouldReport;
  final String actualType;
  final int? statusCode;
  final String? contentType;
  final String? requestID;
  final String? cfRay;
  final int redirectCount;
  final int? bodyLength;

  String get endpointKind => shouldReport ? "production" : "custom";

  Map<String, dynamic> get sentryContext => {
    "path": path,
    "expected": "JSON object",
    "actual_type": actualType,
    "endpoint_kind": endpointKind,
    "redirect_count": redirectCount,
    if (statusCode != null) "status_code": statusCode,
    if (contentType != null) "content_type": contentType,
    if (requestID != null) "x_request_id": requestID,
    if (cfRay != null) "cf_ray": cfRay,
    if (bodyLength != null) "body_length": bodyLength,
  };

  @override
  String toString() {
    return "ApiResponseFormatException: expected JSON object at "
        "$path.response, got $actualType from $endpointKind endpoint";
  }
}
