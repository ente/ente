import 'dart:io';

import 'package:locker/service_locator.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/src/rust/third_party/ente_frb_lib/session.dart';

Session? _session;
String? _sessionKey;

Session authenticatedSession() {
  final config = Configuration.instance;
  final authToken = config.getToken();
  final userId = config.getUserID();
  if (authToken == null || userId == null || !config.hasConfiguredAccount()) {
    throw StateError('Authenticated session is not available');
  }
  final baseUrl = config.getHttpEndpoint();
  final key = '$baseUrl|$userId';
  final current = _session;
  if (current != null && _sessionKey == key) {
    current.updateAuthToken(authToken: authToken);
    return current;
  }

  final keyAttributes = config.getKeyAttributes();
  if (keyAttributes == null) {
    throw StateError('Authenticated session is not available');
  }
  final encryptedRecoveryKey = keyAttributes.recoveryKeyEncryptedWithMasterKey;
  final recoveryKeyNonce = keyAttributes.recoveryKeyDecryptionNonce;
  if (encryptedRecoveryKey.isEmpty || recoveryKeyNonce.isEmpty) {
    throw StateError('Recovery key is not available');
  }
  final services = ServiceLocator.instance;
  final opened = openSession(
    input: OpenSessionInput(
      baseUrl: baseUrl,
      authToken: authToken,
      userId: userId,
      masterKey: config.getKey()!,
      keyAttributes: SessionKeyAttributes(
        publicKey: keyAttributes.publicKey,
        encryptedSecretKey: keyAttributes.encryptedSecretKey,
        secretKeyDecryptionNonce: keyAttributes.secretKeyDecryptionNonce,
        recoveryKeyEncryptedWithMasterKey: encryptedRecoveryKey,
        recoveryKeyDecryptionNonce: recoveryKeyNonce,
      ),
      userAgent:
          services.enteDio.options.headers[HttpHeaders.userAgentHeader]
              as String,
      clientPackage: services.packageInfo.packageName,
      clientVersion: services.packageInfo.version,
    ),
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
