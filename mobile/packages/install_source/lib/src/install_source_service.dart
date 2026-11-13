import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class InstallSourceService {
  InstallSourceService(
    this._enteDio, {
    required String app,
    required String? Function() getToken,
    MethodChannel? methodChannel,
  }) : _app = app,
       _getToken = getToken,
       _methodChannel = methodChannel ?? const MethodChannel(_channelName);

  static const _channelName = 'io.ente.install_source/install_source';
  static const _platformChannelTimeout = Duration(seconds: 3);
  static const _installEvent = 'install';

  final Dio _enteDio;
  final String _app;
  final String? Function() _getToken;
  final MethodChannel _methodChannel;
  final _logger = Logger('InstallSourceService');

  Future<void> autoAttributeSource({required bool isSignUp}) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _methodChannel
          .invokeMethod<void>('autoAttributeSource', {'isSignUp': isSignUp})
          .timeout(_platformChannelTimeout);
      await autoAttributePendingSource();
    } catch (e, s) {
      _logger.warning('Failed to auto-attribute install source', e, s);
    }
  }

  Future<void> autoAttributePendingSource() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final events =
          await _methodChannel
              .invokeListMethod<String>('getPendingEvents')
              .timeout(_platformChannelTimeout) ??
          const <String>[];
      for (final eventJson in events) {
        await _sendEventJson(eventJson);
      }
    } catch (e, s) {
      _logger.warning('Failed to flush install source events', e, s);
    }
  }

  Future<bool> hasInstallSource() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _methodChannel
              .invokeMethod<bool>('hasInstallSource')
              .timeout(_platformChannelTimeout) ??
          false;
    } catch (e, s) {
      _logger.warning('Failed to check install source', e, s);
      return false;
    }
  }

  Future<void> _sendEventJson(String eventJson) async {
    final event = jsonDecode(eventJson) as Map<String, dynamic>;
    final eventName = event['event'] as String?;
    if (eventName == null) {
      return;
    }
    if (eventName != _installEvent && _getToken() == null) {
      return;
    }
    event['app'] = _app;
    event['platform'] = Platform.operatingSystem;
    await _enteDio.post(
      eventName == _installEvent ? '/events' : '/events/user',
      data: event,
    );
    await _methodChannel.invokeMethod<void>('markEventSent', {
      'event': eventName,
    });
  }
}
