import "dart:convert";

import "package:dio/dio.dart";
import "package:photos/core/exceptions.dart";

class ApiResponseInterceptor extends Interceptor {
  ApiResponseInterceptor(String endpoint) : _endpoint = Uri.parse(endpoint);

  final Uri _endpoint;

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    if (!_isApiRequest(error.requestOptions)) {
      handler.next(error);
      return;
    }

    final response = error.response;
    final isInvalidJSON = response == null && error.error is FormatException;
    final hasNonJSONBody =
        response != null && response.data is! Map && response.data is! List;
    if (!isInvalidJSON && !hasNonJSONBody) {
      handler.next(error);
      return;
    }

    final unexpected = UnexpectedApiResponseException(
      error.requestOptions,
      response,
      error.type,
    );
    handler.reject(unexpected);
  }

  bool _isApiRequest(RequestOptions request) {
    final uri = request.uri;
    if (uri.scheme != _endpoint.scheme ||
        uri.host != _endpoint.host ||
        uri.port != _endpoint.port) {
      return false;
    }
    final basePath = _endpoint.path.replaceFirst(RegExp(r"/$"), "");
    return basePath.isEmpty ||
        uri.path == basePath ||
        uri.path.startsWith("$basePath/");
  }
}

class UnexpectedApiResponseException extends DioException
    implements LocallyHandledError {
  UnexpectedApiResponseException(
    RequestOptions request,
    Response<dynamic>? originalResponse,
    DioExceptionType originalType,
  ) : details = _details(originalResponse),
      super(
        requestOptions: _safeRequest(request),
        response: originalResponse == null
            ? null
            : Response<dynamic>(
                requestOptions: _safeRequest(request),
                statusCode: originalResponse.statusCode,
                data: _details(originalResponse),
              ),
        type: originalType,
        message: "The API returned an unexpected response",
      );

  final Map<String, Object> details;

  @override
  String toString() => "UnexpectedApiResponseException: $details";
}

Map<String, Object> _details(Response<dynamic>? response) {
  final body = response?.data;
  return Map.unmodifiable({
    "unexpected_response": true,
    if (response == null) "reason": "invalid_json",
    "status_code": ?response?.statusCode,
    "content_type": ?response?.headers.value(Headers.contentTypeHeader),
    "server": ?response?.headers.value("server"),
    "cf_ray": ?response?.headers.value("cf-ray"),
    if (body is String) "body_length": utf8.encode(body).length,
  });
}

RequestOptions _safeRequest(RequestOptions request) {
  final segments = request.uri.pathSegments.where(
    (segment) => segment.isNotEmpty,
  );
  return RequestOptions(
    method: request.method,
    path: segments.isEmpty ? "/" : "/${segments.first}",
    headers: {"x-request-id": ?request.headers["x-request-id"]},
  );
}
