import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/notification_key_service.dart';
import 'package:photos/services/notification_service.dart';
import 'package:photos/services/push_service.dart';
import 'package:photos/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  final notifications = FlutterLocalNotificationsPlugin();
  late SharedPreferences preferences;

  setUpAll(() async {
    await EntePhotosRust.init();
    expect(
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!
          .areNotificationsEnabled(),
      isTrue,
      reason: 'Grant Android notification permission before running this test',
    );
  });

  setUp(() async {
    preferences = await SharedPreferences.getInstance();
    await preferences.clear();
    await storage.deleteAll();
    await notifications.cancelAll();
    NotificationService.instance.init(preferences);
  });

  tearDown(() async {
    await preferences.clear();
    await storage.deleteAll();
    await notifications.cancelAll();
  });

  testWidgets('overlapping enrollment reuses one persisted private key', (
    tester,
  ) async {
    final keys = await Future.wait(
      List.generate(8, (_) => NotificationKeyService.generateNotificationKey()),
    );
    expect(keys.toSet().length, 1);
    expect(await NotificationKeyService.generateNotificationKey(), keys.first);
    final stored = await storage.readAll();
    expect(stored.length, 1);
    expect(base64Decode(stored.values.single), hasLength(32));

    await storage.deleteAll();
    expect(
      await NotificationKeyService.generateNotificationKey(),
      isNot(keys.first),
    );
  });

  testWidgets('fallback is shown when signed in and suppressed after logout', (
    tester,
  ) async {
    await preferences.setString(Configuration.tokenKey, 'test-session');
    Future<void> receive() =>
        NotificationService.instance.handlePushNotification(
          {'notificationCiphertext': 'invalid'},
          onSync: () async =>
              fail('An undecryptable push must not request sync'),
        );

    await receive();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await notifications.getActiveNotifications(), hasLength(1));
    await notifications.cancelAll();

    final rootToken = RootIsolateToken.instance!;
    await compute(_clearAccount, rootToken);
    expect(preferences.getString(Configuration.tokenKey), isNotNull);
    await receive();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await notifications.getActiveNotifications(), isEmpty);
  });

  testWidgets('failed key preparation can be retried after clearing storage', (
    tester,
  ) async {
    await NotificationKeyService.setNotificationPrivateKey(Uint8List(1));
    await expectLater(
      NotificationKeyService.generateNotificationKey(),
      throwsA(anything),
    );
    await storage.deleteAll();
    final publicKey = await NotificationKeyService.generateNotificationKey();
    expect(publicKey, isNotNull);
  });

  testWidgets('ordinary Android registration enrolls a key on normal refresh', (
    tester,
  ) async {
    final registrations = <Map<String, dynamic>>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/push/token') {
              registrations.add(Map<String, dynamic>.from(options.data as Map));
            }
            handler.resolve(Response(requestOptions: options, data: {}));
          },
        ),
      );
    ServiceLocator.instance.prefs = preferences;
    ServiceLocator.instance.enteDio = dio;
    await Configuration.instance.init(preferences);
    await preferences.setString(Configuration.tokenKey, 'test-session');
    await preferences.setBool('ls.internal_user_disabled', true);
    await preferences.setString('remote_flags', '{"internalUser":false}');
    expect(flagService.internalUser, isFalse);

    await PushService.instance.init();
    expect(registrations, hasLength(1));
    final publicKey = registrations.single['notificationKey'] as String;
    expect(base64Decode(publicKey), hasLength(1216));
    expect(registrations.single['platform'], 'android');
    expect(publicKey, await NotificationKeyService.generateNotificationKey());

    await PushService.instance.init();
    expect(registrations, hasLength(1), reason: 'Keep the existing cadence');
    await preferences.setInt(PushService.kLastFCMTokenUpdationTime, 0);
    await PushService.instance.init();
    expect(registrations, hasLength(2));
    expect(registrations.last['notificationKey'], publicKey);

    await NotificationKeyService.setNotificationPrivateKey(Uint8List(1));
    await preferences.setInt(PushService.kLastFCMTokenUpdationTime, 0);
    await PushService.instance.init();
    expect(registrations, hasLength(3));
    expect(registrations.last['notificationKey'], isNull);
    expect(registrations.last['fcmToken'], registrations.first['fcmToken']);
  });
}

Future<void> _clearAccount(RootIsolateToken rootToken) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  await (await SharedPreferences.getInstance()).clear();
  await const FlutterSecureStorage().deleteAll();
}
