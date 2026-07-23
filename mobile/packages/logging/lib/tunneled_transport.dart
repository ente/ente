import 'dart:convert';

import 'package:http/http.dart';
import 'package:sentry/sentry.dart';

/// A transport is in charge of sending the event to the Sentry server.
class TunneledTransport implements Transport {
  final Uri _tunnel;
  final SentryOptions _options;

  final Dsn? _dsn;

  _CredentialBuilder? _credentialBuilder;

  final Map<String, String> _headers;

  factory TunneledTransport(Uri tunnel, SentryOptions options) {
    return TunneledTransport._(tunnel, options);
  }

  TunneledTransport._(this._tunnel, this._options)
    : _dsn = _options.dsn != null ? Dsn.parse(_options.dsn!) : null,
      _headers = _buildHeaders(
        _options.platformChecker.isWeb,
        _options.sentryClientName,
      ) {
    _credentialBuilder = _CredentialBuilder(
      _dsn,
      _options.sentryClientName,
      // ignore: invalid_use_of_internal_member
      _options.clock,
    );
  }

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final streamedRequest = await _createStreamedRequest(envelope);
    final response = await _options.httpClient
        .send(streamedRequest)
        .then(Response.fromStream);

    if (response.statusCode != 200) {
      // body guard to not log the error as it has performance impact to allocate
      // the body String.
      if (_options.debug) {
        _options.logger(
          SentryLevel.error,
          'API returned an error, statusCode = ${response.statusCode}, '
          'body = ${response.body}',
        );
      }
      return const SentryId.empty();
    } else {
      _options.logger(
        SentryLevel.debug,
        'Envelope ${envelope.header.eventId ?? "--"} was sent successfully.',
      );
    }

    final eventId = json.decode(response.body)['id'];
    if (eventId == null) {
      return null;
    }
    return SentryId.fromId(eventId);
  }

  Future<StreamedRequest> _createStreamedRequest(
    SentryEnvelope envelope,
  ) async {
    final streamedRequest = StreamedRequest('POST', _tunnel);
    envelope
        .envelopeStream(_options)
        .listen(streamedRequest.sink.add)
        .onDone(streamedRequest.sink.close);

    streamedRequest.headers.addAll(_credentialBuilder!.configure(_headers));

    return streamedRequest;
  }
}

class _CredentialBuilder {
  final String _authHeader;

  final ClockProvider _clock;

  int get timestamp => _clock().millisecondsSinceEpoch;

  _CredentialBuilder._(String authHeader, ClockProvider clock)
    : _authHeader = authHeader,
      _clock = clock;

  factory _CredentialBuilder(
    Dsn? dsn,
    String sdkIdentifier,
    ClockProvider clock,
  ) {
    final authHeader = _buildAuthHeader(
      publicKey: dsn?.publicKey,
      secretKey: dsn?.secretKey,
      sdkIdentifier: sdkIdentifier,
    );

    return _CredentialBuilder._(authHeader, clock);
  }

  static String _buildAuthHeader({
    String? publicKey,
    String? secretKey,
    String? sdkIdentifier,
  }) {
    var header =
        'Sentry sentry_version=7, sentry_client=$sdkIdentifier, '
        'sentry_key=$publicKey';

    if (secretKey != null) {
      header += ', sentry_secret=$secretKey';
    }

    return header;
  }

  Map<String, String> configure(Map<String, String> headers) {
    return headers..addAll(<String, String>{
      'X-Sentry-Auth': '$_authHeader, sentry_timestamp=$timestamp',
    });
  }
}

Map<String, String> _buildHeaders(bool isWeb, String sdkIdentifier) {
  final headers = {'Content-Type': 'application/x-sentry-envelope'};
  // NOTE(lejard_h) overriding user agent on VM and Flutter not sure why
  // for web it use browser user agent
  if (!isWeb) {
    headers['User-Agent'] = sdkIdentifier;
  }
  return headers;
}
