import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_linux/local_auth_linux.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.local_auth_linux');
  late LocalAuthLinux localAuth;
  late List<MethodCall> calls;

  setUp(() {
    localAuth = LocalAuthLinux(channel: channel);
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          calls.add(methodCall);
          return switch (methodCall.method) {
            'authenticate' => true,
            'isDeviceSupported' => true,
            'getSetupStatus' => <String, Object?>{
              'actionId': linuxLocalAuthPolkitActionId,
              'policyAssetPath': '/usr/share/enteauth/policy',
              'polkitAvailable': true,
              'policyInstalled': true,
              'isFlatpak': false,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registers as the local_auth platform implementation', () {
    final previous = LocalAuthPlatform.instance;

    LocalAuthLinux.registerWith();

    expect(LocalAuthPlatform.instance, isA<LocalAuthLinux>());
    LocalAuthPlatform.instance = previous;
  });

  test('authenticate sends the localized reason to native code', () async {
    final result = await localAuth.authenticate(
      localizedReason: 'Unlock Ente Auth',
      authMessages: const <AuthMessages>[],
    );

    expect(result, isTrue);
    expect(calls.single.method, 'authenticate');
    expect(calls.single.arguments, <String, Object?>{
      'localizedReason': 'Unlock Ente Auth',
    });
  });

  test(
    'authenticate returns false when native auth rejects credentials',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);

      final result = await localAuth.authenticate(
        localizedReason: 'Unlock Ente Auth',
        authMessages: const <AuthMessages>[],
      );

      expect(result, isFalse);
    },
  );

  test('authenticate maps cancellation to LocalAuthException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'authentication_canceled',
            message: 'Authentication was canceled.',
          );
        });

    await expectLater(
      localAuth.authenticate(
        localizedReason: 'Unlock Ente Auth',
        authMessages: const <AuthMessages>[],
      ),
      throwsA(
        isA<LocalAuthException>().having(
          (e) => e.code,
          'code',
          LocalAuthExceptionCode.userCanceled,
        ),
      ),
    );
  });

  test('authenticate rejects biometricOnly', () async {
    await expectLater(
      localAuth.authenticate(
        localizedReason: 'Unlock Ente Auth',
        authMessages: const <AuthMessages>[],
        options: const AuthenticationOptions(biometricOnly: true),
      ),
      throwsUnsupportedError,
    );
  });

  test('authenticate guards concurrent calls', () async {
    final completer = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => completer.future);

    final first = localAuth.authenticate(
      localizedReason: 'Unlock Ente Auth',
      authMessages: const <AuthMessages>[],
    );

    await expectLater(
      localAuth.authenticate(
        localizedReason: 'Unlock Ente Auth',
        authMessages: const <AuthMessages>[],
      ),
      throwsA(
        isA<LocalAuthException>().having(
          (e) => e.code,
          'code',
          LocalAuthExceptionCode.authInProgress,
        ),
      ),
    );

    completer.complete(true);
    await expectLater(first, completion(isTrue));
  });

  test(
    'reports Polkit device support but no direct biometric support',
    () async {
      expect(await localAuth.isDeviceSupported(), isTrue);
      expect(await localAuth.deviceSupportsBiometrics(), isFalse);
      expect(await localAuth.getEnrolledBiometrics(), isEmpty);
      expect(await localAuth.stopAuthentication(), isFalse);
    },
  );

  test('reads setup status from native code', () async {
    final status = await localAuth.getSetupStatus();

    expect(status.actionId, linuxLocalAuthPolkitActionId);
    expect(status.policyAssetPath, '/usr/share/enteauth/policy');
    expect(status.polkitAvailable, isTrue);
    expect(status.policyInstalled, isTrue);
    expect(status.isFlatpak, isFalse);
    expect(status.setupRequired, isFalse);
  });

  test('maps missing Polkit policy to no credentials set', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'setup_required',
            message: 'The Ente Auth Polkit policy is not installed.',
          );
        });

    await expectLater(
      localAuth.authenticate(
        localizedReason: 'Unlock Ente Auth',
        authMessages: const <AuthMessages>[],
      ),
      throwsA(
        isA<LocalAuthException>().having(
          (e) => e.code,
          'code',
          LocalAuthExceptionCode.noCredentialsSet,
        ),
      ),
    );
  });
}
