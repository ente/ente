import "dart:async";
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:logging/logging.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/core/network/endpoint_config.dart";
import 'package:photos/core/network/ente_interceptor.dart';
import "package:shared_preferences/shared_preferences.dart";
import "package:ua_client_hints/ua_client_hints.dart";

class NetworkClient {
  final _logger = Logger("NetworkClient");
  final _http2FallbackPolicy = _Http2FallbackPolicy();
  late Dio _dio;
  late Dio _downloadDio;
  late Dio _enteDio;
  StreamSubscription<EndpointUpdatedEvent>? _endpointUpdatedSubscription;
  static const kConnectTimeout = 15;
  static const _connectTimeout = Duration(seconds: kConnectTimeout);

  Future<void> init(
    PackageInfo packageInfo,
    SharedPreferences preferences,
  ) async {
    final endpointConfig = EndpointConfig(preferences);
    final String ua = await userAgent();
    final endpoint = endpointConfig.endpoint;
    _dio = Dio(_newBaseOptions(ua, packageInfo));
    _downloadDio = Dio(_newBaseOptions(ua, packageInfo));
    _enteDio = Dio(_newBaseOptions(ua, packageInfo, baseUrl: endpoint));

    _dio.httpClientAdapter = _newAdaptiveHttpClientAdapter(_connectTimeout);
    _downloadDio.httpClientAdapter = _newDownloadHttpClientAdapter(
      _connectTimeout,
    );
    _enteDio.httpClientAdapter = _newAdaptiveHttpClientAdapter(_connectTimeout);

    _setupInterceptors(endpoint);

    if (_endpointUpdatedSubscription != null) {
      await _endpointUpdatedSubscription!.cancel();
    }
    _endpointUpdatedSubscription = Bus.instance
        .on<EndpointUpdatedEvent>()
        .listen((event) {
          _enteDio.options.baseUrl = event.endpoint;
          _setupInterceptors(event.endpoint);
        });
  }

  void _setupInterceptors(String endpoint) {
    _enteDio.interceptors.clear();
    _enteDio.interceptors.add(EnteRequestInterceptor(endpoint));
  }

  BaseOptions _newBaseOptions(
    String ua,
    PackageInfo packageInfo, {
    String? baseUrl,
  }) {
    return BaseOptions(
      baseUrl: baseUrl ?? "",
      connectTimeout: _connectTimeout,
      headers: {
        HttpHeaders.userAgentHeader: ua,
        'X-Client-Version': packageInfo.version,
        'X-Client-Package': packageInfo.packageName,
      },
    );
  }

  HttpClientAdapter _newAdaptiveHttpClientAdapter(Duration connectTimeout) {
    final fallbackAdapter = IOHttpClientAdapter();
    final fallbackPolicy = _http2FallbackPolicy;
    final http2Adapter = Http2Adapter(
      ConnectionManager(handshakeTimout: connectTimeout),
      fallbackAdapter: fallbackAdapter,
      onNotSupported: (options, requestStream, cancelFuture, exception) {
        _logHttp2UnsupportedOriginOnce(
          logger: _logger,
          fallbackPolicy: fallbackPolicy,
          uri: exception.uri,
          reason: "HTTP/2 not supported for ${options.method}",
        );
        return fallbackAdapter.fetch(options, requestStream, cancelFuture);
      },
    );
    return _AdaptiveHttpClientAdapter(
      http2Adapter: http2Adapter,
      fallbackAdapter: fallbackAdapter,
      logger: _logger,
      fallbackPolicy: fallbackPolicy,
    );
  }

  HttpClientAdapter _newDownloadHttpClientAdapter(Duration connectTimeout) {
    return _HttpSchemeFallbackAdapter(
      primaryAdapter: NativeAdapter(),
      fallbackAdapter: _newAdaptiveHttpClientAdapter(connectTimeout),
    );
  }

  NetworkClient._privateConstructor();

  static NetworkClient instance = NetworkClient._privateConstructor();

  Dio getDio() => _dio;

  Dio get downloadDio => _downloadDio;

  Dio get enteDio => _enteDio;
}

class _HttpSchemeFallbackAdapter implements HttpClientAdapter {
  _HttpSchemeFallbackAdapter({
    required HttpClientAdapter primaryAdapter,
    required HttpClientAdapter fallbackAdapter,
  }) : _primaryAdapter = primaryAdapter,
       _fallbackAdapter = fallbackAdapter;

  final HttpClientAdapter _primaryAdapter;
  final HttpClientAdapter _fallbackAdapter;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final adapter = options.uri.scheme.toLowerCase() == "http"
        ? _fallbackAdapter
        : _primaryAdapter;
    return adapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _primaryAdapter.close(force: force);
    _fallbackAdapter.close(force: force);
  }
}

class _AdaptiveHttpClientAdapter implements HttpClientAdapter {
  _AdaptiveHttpClientAdapter({
    required HttpClientAdapter http2Adapter,
    required HttpClientAdapter fallbackAdapter,
    required Logger logger,
    required _Http2FallbackPolicy fallbackPolicy,
  }) : _http2Adapter = http2Adapter,
       _fallbackAdapter = fallbackAdapter,
       _logger = logger,
       _fallbackPolicy = fallbackPolicy;

  final HttpClientAdapter _http2Adapter;
  final HttpClientAdapter _fallbackAdapter;
  final Logger _logger;
  final _Http2FallbackPolicy _fallbackPolicy;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.scheme != "https") {
      return _fallbackAdapter.fetch(options, requestStream, cancelFuture);
    }
    if (_fallbackPolicy.isUnsupported(options.uri)) {
      return _fallbackAdapter.fetch(options, requestStream, cancelFuture);
    }
    if (_shouldUseFallbackForRequestBody(
      options,
      requestStream,
      cancelFuture,
    )) {
      return _fallbackAdapter.fetch(options, requestStream, cancelFuture);
    }

    try {
      return await _http2Adapter.fetch(options, requestStream, cancelFuture);
    } catch (e, s) {
      if (e is TimeoutException) {
        throw DioException.connectionTimeout(
          requestOptions: options,
          timeout: options.connectTimeout ?? Duration.zero,
          error: e,
        );
      }
      if (_isFallbackHandshakeError(e)) {
        _logHttp2UnsupportedOriginOnce(
          logger: _logger,
          fallbackPolicy: _fallbackPolicy,
          uri: options.uri,
          reason: "HTTP/2 TLS negotiation failed for ${options.method}",
        );
        return _fallbackAdapter.fetch(options, requestStream, cancelFuture);
      }
      Error.throwWithStackTrace(e, s);
    }
  }

  @override
  void close({bool force = false}) {
    _http2Adapter.close(force: force);
    _fallbackAdapter.close(force: force);
  }

  bool _isFallbackHandshakeError(Object e) {
    if (e is HandshakeException) {
      return _isNoApplicationProtocolError(e);
    }
    if (e is DioException && e.error is HandshakeException) {
      return _isNoApplicationProtocolError(e.error! as HandshakeException);
    }
    return false;
  }

  bool _isNoApplicationProtocolError(HandshakeException e) {
    final message = "${e.message} $e".toLowerCase();
    return message.contains("no_application_protocol") ||
        message.contains("no application protocol");
  }

  // Keep body sources on Dio's IO adapter when dio_http2_adapter can close the
  // HTTP/2 outgoing stream before the body stops emitting.
  bool _shouldUseFallbackForRequestBody(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _hasRequestBodySendTimeout(options, requestStream) ||
        _hasCancellableRequestBody(requestStream, cancelFuture) ||
        _hasSourceStreamingBody(options);
  }

  bool _hasRequestBodySendTimeout(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
  ) {
    final sendTimeout = options.sendTimeout ?? Duration.zero;
    return requestStream != null && sendTimeout > Duration.zero;
  }

  bool _hasCancellableRequestBody(
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return requestStream != null && cancelFuture != null;
  }

  bool _hasSourceStreamingBody(RequestOptions options) {
    return options.data is Stream<List<int>> || options.data is FormData;
  }
}

class _Http2FallbackPolicy {
  final _unsupportedOriginKeys = <String>{};

  bool isUnsupported(Uri uri) {
    return _unsupportedOriginKeys.contains(_originKey(uri));
  }

  bool markUnsupported(Uri uri) {
    return _unsupportedOriginKeys.add(_originKey(uri));
  }

  String originForLog(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final port = uri.hasPort && !_isDefaultPort(scheme, uri.port)
        ? ":${uri.port}"
        : "";
    return "$scheme://${_formatHost(uri.host)}$port";
  }

  String _originKey(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return "$scheme://${uri.host.toLowerCase()}:${_effectivePort(uri, scheme)}";
  }

  int _effectivePort(Uri uri, String scheme) {
    if (uri.hasPort) {
      return uri.port;
    }
    if (scheme == "https") {
      return 443;
    }
    if (scheme == "http") {
      return 80;
    }
    return uri.port;
  }

  bool _isDefaultPort(String scheme, int port) {
    return (scheme == "https" && port == 443) ||
        (scheme == "http" && port == 80);
  }

  String _formatHost(String host) {
    return host.contains(":") ? "[$host]" : host;
  }
}

void _logHttp2UnsupportedOriginOnce({
  required Logger logger,
  required _Http2FallbackPolicy fallbackPolicy,
  required Uri uri,
  required String reason,
}) {
  if (fallbackPolicy.markUnsupported(uri)) {
    logger.info(
      "$reason ${fallbackPolicy.originForLog(uri)}; "
      "using IO adapter for this app session",
    );
  }
}
