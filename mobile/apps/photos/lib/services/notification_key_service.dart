import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/src/rust/api/notification_api.dart';
import 'package:photos/src/rust/frb_generated.dart';

class NotificationKeyService {
  static const _channel = MethodChannel('io.ente.frame.notifications');
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'notification_private_key';
  static Future<String>? _pendingKey;

  static Future<String?> generateNotificationKey() {
    if (!Platform.isAndroid) return Future.value();
    return _pendingKey ??= _getOrCreateNotificationKey().whenComplete(() {
      _pendingKey = null;
    });
  }

  static Future<String> _getOrCreateNotificationKey() async {
    final sessionToken = Platform.isIOS
        ? Configuration.instance.getToken()
        : null;
    var privateKey = await getNotificationPrivateKey(
      sessionToken: sessionToken,
    );
    if (privateKey == null) {
      privateKey = generateNotificationPrivateKey();
      await setNotificationPrivateKey(privateKey, sessionToken: sessionToken);
    }
    return base64Encode(getNotificationPublicKey(privateKey: privateKey));
  }

  static Future<Map<String, dynamic>?> decrypt(
    Map<String, dynamic> data,
  ) async {
    final privateKey = await getNotificationPrivateKey();
    if (privateKey == null) return null;
    if (!EntePhotosRust.instance.initialized) {
      await EntePhotosRust.init();
    }
    final plaintext = decryptNotification(
      ciphertext: base64Decode(data['notificationCiphertext'] as String),
      privateKey: privateKey,
    );
    final event = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    if (event['eventType'] is! String) return null;
    return event;
  }

  static Future<Uint8List?> getNotificationPrivateKey({
    String? sessionToken,
  }) async {
    final encoded = Platform.isIOS
        ? await _channel.invokeMethod<String>('getPrivateKey', {
            'sessionToken': sessionToken ?? Configuration.instance.getToken(),
          })
        : await _storage.read(key: _storageKey);
    return encoded == null ? null : base64Decode(encoded);
  }

  static Future<void> setNotificationPrivateKey(
    Uint8List? privateKey, {
    String? sessionToken,
  }) async {
    if (Platform.isIOS) {
      if (privateKey == null) {
        await _channel.invokeMethod<void>('clear');
      } else {
        await _channel.invokeMethod<void>('setPrivateKey', {
          'sessionToken': sessionToken ?? Configuration.instance.getToken(),
          'privateKey': base64Encode(privateKey),
        });
      }
      return;
    }
    if (privateKey == null) {
      await _storage.delete(key: _storageKey);
    } else {
      await _storage.write(key: _storageKey, value: base64Encode(privateKey));
    }
  }
}
