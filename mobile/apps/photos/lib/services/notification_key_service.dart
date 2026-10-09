import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class NotificationKeyService {
  static const channel = MethodChannel('io.ente.frame.notifications');
  static final _logger = Logger('NotificationKeyService');

  static Future<Map<String, Object>?> prepare({
    required String sessionToken,
  }) async {
    try {
      return await channel.invokeMapMethod<String, Object>('prepare', {
        'sessionToken': sessionToken,
      });
    } catch (e, s) {
      _logger.warning('Could not prepare notification key', e, s);
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clear');
    } catch (e, s) {
      _logger.warning('Could not clear notification key', e, s);
    }
  }

  static Future<void> syncPreference() async {
    try {
      await channel.invokeMethod<void>('syncPreference');
    } catch (e, s) {
      _logger.warning('Could not share notification preference', e, s);
    }
  }
}
