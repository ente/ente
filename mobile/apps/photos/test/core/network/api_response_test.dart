import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/network/api_response.dart";

void main() {
  group(ApiResponseShapeInterceptor, () {
    test(
      "rejects non-object production API responses on object routes",
      () async {
        final dio = _dio(
          endpoint: kDefaultProductionEndpoint,
          body: '"not an object"',
          contentType: Headers.jsonContentType,
        );

        final error = await _dioExceptionFor(dio.get("/users/details/v2"));

        expect(error.error, isA<ApiResponseFormatException>());
        final formatError = error.error! as ApiResponseFormatException;
        expect(formatError.path, "/users/details/v2");
        expect(formatError.actualType, "String");
        expect(formatError.shouldReport, true);
        expect(formatError.endpointKind, "production");
        expect(
          formatError.sentryContext["content_type"],
          Headers.jsonContentType,
        );
        expect(formatError.sentryContext["body_length"], 13);
      },
    );

    test(
      "classifies non-production endpoint response shapes as local",
      () async {
        final dio = _dio(
          endpoint: "https://self-hosted.example.com",
          body: "<html></html>",
          contentType: "text/html",
        );

        final error = await _dioExceptionFor(dio.get("/memory-share"));
        final formatError = error.error! as ApiResponseFormatException;

        expect(formatError.shouldReport, false);
        expect(formatError.endpointKind, "custom");
      },
    );

    test(
      "allows non-object responses on routes that do not expect objects",
      () async {
        final dio = _dio(
          endpoint: kDefaultProductionEndpoint,
          body: '"https://example.com/upload"',
          contentType: Headers.jsonContentType,
        );

        final response = await dio.post("/files/upload-url");

        expect(response.data, "https://example.com/upload");
      },
    );
  });
}

Dio _dio({
  required String endpoint,
  required String body,
  required String contentType,
}) {
  return Dio(BaseOptions(baseUrl: endpoint))
    ..httpClientAdapter = _StaticAdapter(body: body, contentType: contentType)
    ..interceptors.add(ApiResponseShapeInterceptor(endpoint));
}

Future<DioException> _dioExceptionFor(Future<Object?> request) async {
  try {
    await request;
  } on DioException catch (e) {
    return e;
  }
  fail("Expected DioException");
}

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter({required this.body, required this.contentType});

  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
