import 'dart:io';

import 'package:photos/core/configuration.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/src/rust/third_party/ente_frb_lib/session.dart';

Session? _session;
String? _sessionKey;

Session authenticatedSession() {
  final config = Configuration.instance;
  final authToken = config.getToken();
  final userId = config.getUserID();
  if (authToken == null || userId == null || !config.hasConfiguredAccount()) {
    throw StateError('Authenticated session is not available');
  }
  final baseUrl = endpointConfig.endpoint;
  final key = '$baseUrl|$userId';
  final current = _session;
  if (current != null && _sessionKey == key) {
    current.updateAuthToken(authToken: authToken);
    return current;
  }

  final services = ServiceLocator.instance;
  final opened = openSession(
    baseUrl: baseUrl,
    authToken: authToken,
    masterKey: config.getKey()!,
    userAgent:
        services.enteDio.options.headers[HttpHeaders.userAgentHeader] as String,
    clientPackage: services.packageInfo.packageName,
    clientVersion: services.packageInfo.version,
  );
  clearAuthenticatedSession();
  _session = opened;
  _sessionKey = key;
  return opened;
}

void clearAuthenticatedSession() {
  _session?.dispose();
  _session = null;
  _sessionKey = null;
}
