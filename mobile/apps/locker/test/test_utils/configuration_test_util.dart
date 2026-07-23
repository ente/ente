import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

Future<Directory> setupLockerConfigurationForTest(String name) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = await Directory.systemTemp.createTemp('locker_${name}_');
  final tempDirectory = Directory('${root.path}/temp_root');
  final supportDirectory = Directory('${root.path}/support');
  await tempDirectory.create(recursive: true);
  await supportDirectory.create(recursive: true);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        switch (call.method) {
          case 'getTemporaryDirectory':
            return tempDirectory.path;
          case 'getApplicationSupportDirectory':
            return supportDirectory.path;
          default:
            return root.path;
        }
      });

  final secureStorage = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        final arguments = (call.arguments as Map?) ?? {};
        final key = arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return secureStorage[key];
          case 'write':
            if (key != null) {
              secureStorage[key] = arguments['value'] as String;
            }
            return null;
          case 'delete':
            if (key != null) {
              secureStorage.remove(key);
            }
            return null;
          case 'deleteAll':
            secureStorage.clear();
            return null;
          case 'containsKey':
            return key != null && secureStorage.containsKey(key);
          case 'readAll':
            return secureStorage;
          default:
            return null;
        }
      });

  SharedPreferences.setMockInitialValues({});
  await Configuration.instance.init([]);

  return root;
}

void clearLockerConfigurationTestHandlers() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
}
