import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const pathsChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final config = Configuration.instance;
  late Map<String, String> secureValues;
  late Set<String> failingCalls;

  setUp(() async {
    secureValues = {};
    failingCalls = {};
    final root = await Directory.systemTemp.createTemp('auth_token_');
    messenger.setMockMethodCallHandler(pathsChannel, (_) async => root.path);
    messenger.setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = call.arguments as Map;
      final key = arguments['key'] as String?;
      if (failingCalls.contains('${call.method}:$key') ||
          failingCalls.remove('once:${call.method}:$key')) {
        throw PlatformException(code: 'unavailable');
      }
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          if (!failingCalls.contains('drop:$key')) {
            secureValues[key!] = arguments['value'] as String;
          }
        case 'delete':
          secureValues.remove(key);
        case 'containsKey':
          return secureValues.containsKey(key);
      }
      return null;
    });
    addTearDown(() async {
      failingCalls.clear();
      await config.logout();
      messenger.setMockMethodCallHandler(secureStorageChannel, null);
      messenger.setMockMethodCallHandler(pathsChannel, null);
      await root.delete(recursive: true);
    });
  });

  test('moves a plaintext token into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      BaseConfiguration.tokenKey: 'token',
    });
    secureValues.addAll({
      BaseConfiguration.keyKey: 'a2V5',
      Configuration.offlineAuthSecretKey: 'b2ZmbGluZQ==',
    });

    await config.init([]);

    final preferences = await SharedPreferences.getInstance();
    expect(config.getToken(), 'token');
    expect(secureValues[BaseConfiguration.tokenKey], 'token');
    expect(preferences.getBool(BaseConfiguration.hasSecureTokenKey), true);

    await config.init([]);
    expect(preferences.containsKey(BaseConfiguration.tokenKey), false);

    await config.logout();
    expect(secureValues.containsKey(BaseConfiguration.tokenKey), false);
    expect(secureValues[Configuration.offlineAuthSecretKey], 'b2ZmbGluZQ==');
  });

  test('keeps the session when a token write is lost', () async {
    SharedPreferences.setMockInitialValues({
      BaseConfiguration.tokenKey: 'token',
      BaseConfiguration.userIDKey: 1,
    });
    secureValues[BaseConfiguration.keyKey] = 'a2V5';
    failingCalls.add('drop:${BaseConfiguration.tokenKey}');

    await config.init([]);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(BaseConfiguration.hasSecureTokenKey), false);

    failingCalls.clear();
    await config.init([]);
    secureValues.remove(BaseConfiguration.tokenKey);
    await config.init([]);

    expect(config.getToken(), 'token');
    expect(secureValues[BaseConfiguration.tokenKey], 'token');
  });

  test('trusts a plaintext token written by an older build', () async {
    SharedPreferences.setMockInitialValues({
      BaseConfiguration.tokenKey: 'new-token',
      BaseConfiguration.hasSecureTokenKey: true,
    });
    secureValues.addAll({
      BaseConfiguration.tokenKey: 'old-token',
      BaseConfiguration.keyKey: 'a2V5',
    });

    await config.init([]);

    expect(config.getToken(), 'new-token');
    expect(secureValues[BaseConfiguration.tokenKey], 'new-token');
  });

  test('clears secure data left by an earlier install', () async {
    SharedPreferences.setMockInitialValues({});
    secureValues.addAll({
      BaseConfiguration.tokenKey: 'old-token',
      BaseConfiguration.keyKey: 'b2xkLWtleQ==',
      Configuration.offlineAuthSecretKey: 'b2ZmbGluZQ==',
    });

    await config.init([]);

    expect(config.isLoggedIn(), false);
    expect(secureValues.containsKey(BaseConfiguration.tokenKey), false);
    expect(secureValues[Configuration.offlineAuthSecretKey], 'b2ZmbGluZQ==');
  });

  test('keeps the session while secure storage is unavailable', () async {
    SharedPreferences.setMockInitialValues({
      BaseConfiguration.hasSecureTokenKey: true,
      BaseConfiguration.userIDKey: 1,
    });
    secureValues.addAll({
      BaseConfiguration.tokenKey: 'token',
      BaseConfiguration.keyKey: 'a2V5',
      LockScreenSettings.pin: 'pin-hash',
    });
    failingCalls.addAll([
      'read:${BaseConfiguration.tokenKey}',
      'read:${BaseConfiguration.keyKey}',
    ]);

    await config.init([]);

    expect(config.isLoggedIn(), true);
    expect(secureValues[LockScreenSettings.pin], 'pin-hash');

    failingCalls.clear();
    await config.init([]);

    expect(config.getToken(), 'token');
  });

  test('keeps the session after a one-off token read failure', () async {
    SharedPreferences.setMockInitialValues({
      BaseConfiguration.hasSecureTokenKey: true,
      BaseConfiguration.userIDKey: 1,
    });
    secureValues.addAll({
      BaseConfiguration.tokenKey: 'token',
      BaseConfiguration.keyKey: 'a2V5',
    });
    failingCalls.add('once:read:${BaseConfiguration.tokenKey}');

    await config.init([]);

    expect(config.getToken(), 'token');
  });

  test('signs out when only the token entry is unreadable', () async {
    SharedPreferences.setMockInitialValues({
      BaseConfiguration.hasSecureTokenKey: true,
      BaseConfiguration.userIDKey: 1,
    });
    secureValues.addAll({
      BaseConfiguration.tokenKey: 'token',
      BaseConfiguration.keyKey: 'a2V5',
      Configuration.offlineAuthSecretKey: 'b2ZmbGluZQ==',
    });
    failingCalls.add('read:${BaseConfiguration.tokenKey}');

    await config.init([]);

    final preferences = await SharedPreferences.getInstance();
    expect(config.isLoggedIn(), false);
    expect(preferences.containsKey(BaseConfiguration.userIDKey), false);
    expect(secureValues[Configuration.offlineAuthSecretKey], 'b2ZmbGluZQ==');
  });
}
