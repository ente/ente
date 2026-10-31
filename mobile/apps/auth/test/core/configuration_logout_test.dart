import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/ios_autofill_service.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'logout clears account credentials despite AutoFill cleanup failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'auth_autofill_logout_',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var failCleanup = false;
      final autoFill = IOSAutoFillService.forTesting();
      messenger.setMockMethodCallHandler(paths, (_) async => root.path);
      messenger.setMockMethodCallHandler(IOSAutoFillService.channel, (
        call,
      ) async {
        if (call.method == 'isSupported') return true;
        if (call.method == 'clear' && failCleanup) {
          throw PlatformException(code: 'cleanup_failed');
        }
        return null;
      });
      addTearDown(() async {
        autoFill.dispose();
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(IOSAutoFillService.channel, null);
        await root.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final config = Configuration.forTesting(autoFill: autoFill);
      await config.init([]);
      await autoFill.init(
        readCodes: () async => <Code>[],
        scope: () => 'online:1',
        timeOffset: () => 0,
      );
      await config.setKey('account-key');
      await config.setToken('account-token');
      await config.setAuthSecretKey('auth-key');
      failCleanup = true;
      await config.logout();
      expect(config.hasConfiguredAccount(), false);
      expect(config.getToken(), isNull);
      expect(config.getAuthSecretKey(), isNull);
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: BaseConfiguration.keyKey), isNull);
      expect(await storage.read(key: Configuration.authSecretKeyKey), isNull);
      expect(autoFill.hasPendingCleanup, true);
    },
  );

  test('offline PIN lock survives sign-in and reinitialization', () async {
    final root = await Directory.systemTemp.createTemp('auth_offline_lock_');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      await root.delete(recursive: true);
    });

    SharedPreferences.setMockInitialValues({
      Configuration.hasOptedForOfflineModeKey: true,
      LockScreenSettings.keyAppLockSet: true,
      LockScreenSettings.keyHasMigratedLockScreenChanges: true,
    });
    FlutterSecureStorage.setMockInitialValues({
      Configuration.offlineAuthSecretKey: 'offline-key',
      LockScreenSettings.pin: 'pin-hash',
      LockScreenSettings.saltKey: 'salt',
    });
    final config = Configuration.instance;
    final lock = LockScreenSettings.instance;
    const storage = FlutterSecureStorage();

    Future<void> expectPinLockPreserved() async {
      expect(await storage.read(key: LockScreenSettings.pin), 'pin-hash');
      expect(await storage.read(key: LockScreenSettings.saltKey), 'salt');
      expect(lock.getIsAppLockSet(), true);
      expect(await lock.shouldShowLockScreen(), true);
    }

    await config.init([]);
    await lock.init(config, hasOptedForOfflineMode: true);
    expect(config.isLoggedIn(), false);
    await expectPinLockPreserved();

    await config.setKey('account-key');
    await config.setToken('token');
    expect(config.hasConfiguredAccount(), true);
    await expectPinLockPreserved();

    await config.init([]);
    await lock.init(
      config,
      hasOptedForOfflineMode: config.hasOptedForOfflineMode(),
    );
    expect(config.hasConfiguredAccount(), true);
    await expectPinLockPreserved();
  });
}
