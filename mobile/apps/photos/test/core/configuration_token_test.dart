import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/core/configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('photos_token_');
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      await root.delete(recursive: true);
    });
  });

  test('keeps the session while secure storage is unavailable', () async {
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final secureValues = {
      Configuration.tokenKey: 'token',
      Configuration.keyKey: 'a2V5',
    };
    var isAvailable = false;
    final changes = <String>[];
    messenger.setMockMethodCallHandler(secureStorage, (call) async {
      if (call.method != 'read') {
        changes.add(call.method);
        return null;
      }
      if (!isAvailable) {
        throw PlatformException(code: 'unavailable');
      }
      return secureValues[(call.arguments as Map)['key']];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(secureStorage, null));
    SharedPreferences.setMockInitialValues({
      Configuration.hasSecureTokenKey: true,
      Configuration.userIDKey: 1,
    });
    final preferences = await SharedPreferences.getInstance();
    final config = Configuration.instance;

    await config.init(preferences);

    expect(preferences.getBool(Configuration.hasSecureTokenKey), true);

    isAvailable = true;
    await config.init(preferences);

    expect(config.getToken(), 'token');
    expect(changes, isEmpty);
  });

  test('moves a plaintext token into secure storage', () async {
    SharedPreferences.setMockInitialValues({Configuration.tokenKey: 'token'});
    final secureValues = {
      Configuration.keyKey: 'a2V5',
      Configuration.secretKeyKey: 'c2VjcmV0',
    };
    FlutterSecureStorage.setMockInitialValues(secureValues);
    final config = Configuration.instance;

    await config.init(await SharedPreferences.getInstance());

    final preferences = await SharedPreferences.getInstance();
    expect(config.getToken(), 'token');
    expect(secureValues[Configuration.tokenKey], 'token');
    expect(preferences.getString(Configuration.tokenKey), 'token');

    await config.init(preferences);
    expect(preferences.containsKey(Configuration.tokenKey), false);
    expect(config.getToken(), 'token');
    expect(secureValues[Configuration.tokenKey], 'token');
  });
}
