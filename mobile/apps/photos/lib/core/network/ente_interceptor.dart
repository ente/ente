import "dart:io";

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/models/base/id.dart";

class EnteRequestInterceptor extends Interceptor {
  final EndpointConfig endpointConfig;
  final String? Function() _tokenProvider;
  final String id = Platform.isIOS ? "ios" : "droid";

  EnteRequestInterceptor(
    this.endpointConfig, {
    String? Function()? tokenProvider,
  }) : _tokenProvider = tokenProvider ?? Configuration.instance.getToken;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      assert(
        options.baseUrl == endpointConfig.endpoint,
        "interceptor should only be used for API endpoint",
      );
    }
    // ignore: prefer_const_constructors
    options.headers.putIfAbsent("x-request-id", () => newID(id));
    final String? tokenValue = _tokenProvider();
    if (tokenValue != null) {
      options.headers.putIfAbsent("X-Auth-Token", () => tokenValue);
    }
    if (endpointConfig.isLocked && _hasAuthToken(options.headers)) {
      try {
        endpointConfig.validateAuthenticatedRequest(options.uri);
      } on EndpointPolicyException catch (e) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            error: e,
          ),
        );
        return;
      }
      options.followRedirects = false;
    }
    handler.next(options);
  }

  static bool _hasAuthToken(Map<String, dynamic> headers) {
    return headers.entries.any(
      (entry) =>
          entry.key.toLowerCase() == "x-auth-token" && entry.value != null,
    );
  }
}
