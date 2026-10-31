import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/services/ios_autofill_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late IOSAutoFillService service;
  late List<MethodCall> calls;
  late Future<List<Code>> Function() readCodes;
  late String scope;
  late bool authenticated;
  late bool supported;
  late bool failPublish;
  Completer<bool>? authenticationResult;

  Code code(
    int id, {
    Type type = Type.totp,
    String issuer = 'Example',
    bool trashed = false,
  }) {
    return Code.fromAccountAndSecret(
      type,
      'person@example.com',
      issuer,
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      CodeDisplay(trashed: trashed),
      6,
    )..generatedID = id;
  }

  Future<void> initialize() => service.init(
    readCodes: () => readCodes(),
    scope: () => scope,
    timeOffset: () => 1234,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = IOSAutoFillService.forTesting();
    calls = [];
    readCodes = () async => [code(1)];
    scope = 'offline';
    authenticated = true;
    supported = true;
    failPublish = false;
    authenticationResult = null;
    messenger.setMockMethodCallHandler(IOSAutoFillService.channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
          return supported;
        case 'authenticate':
          return authenticationResult?.future ?? authenticated;
        case 'publish':
          if (failPublish) throw PlatformException(code: 'failed');
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(IOSAutoFillService.channel, null);
  });

  test(
    'a fresh install clears shared data without publishing secrets',
    () async {
      await initialize();
      expect(calls.map((call) => call.method), ['isSupported', 'clear']);
      expect(service.isEnabled, false);
    },
  );

  test(
    'unsupported iOS versions never publish or request authentication',
    () async {
      supported = false;
      await initialize();
      expect(await service.enable(), false);
      expect(calls.map((call) => call.method), ['isSupported']);
    },
  );

  test('cancelled authentication leaves AutoFill disabled', () async {
    authenticated = false;
    await initialize();
    expect(await service.enable(), false);
    expect(calls.where((call) => call.method == 'publish'), isEmpty);
    expect(service.isEnabled, false);
  });

  test(
    'revocation while authenticating cannot subsequently enable AutoFill',
    () async {
      await initialize();
      authenticationResult = Completer<bool>();
      final enabling = service.enable();
      await Future<void>.delayed(Duration.zero);
      await service.disable();
      authenticationResult!.complete(true);
      expect(await enabling, false);
      expect(service.isEnabled, false);
      expect(calls.where((call) => call.method == 'publish'), isEmpty);
    },
  );

  test(
    'an initial publish failure revokes data and does not persist opt-in',
    () async {
      await initialize();
      failPublish = true;
      await expectLater(service.enable(), throwsA(isA<PlatformException>()));
      expect(service.isEnabled, false);
      expect(calls.last.method, 'clear');
      expect(
        (await SharedPreferences.getInstance()).getBool(
          IOSAutoFillService.enabledKey,
        ),
        false,
      );
    },
  );

  test('only valid saved non-trashed TOTP entries are published', () async {
    readCodes = () async => [
      code(1),
      code(2, type: Type.hotp),
      code(3, type: Type.steam),
      code(4, issuer: 'Steam'),
      code(5, trashed: true),
      Code.withError(const FormatException(), 'invalid'),
      code(6)..generatedID = null,
    ];
    await initialize();
    expect(await service.enable(), true);
    final snapshot =
        jsonDecode(calls.last.arguments as String) as Map<String, dynamic>;
    expect(snapshot['version'], 1);
    expect(snapshot['timeOffsetMilliseconds'], 1234);
    final entries = snapshot['entries'] as List<dynamic>;
    expect(entries, hasLength(1));
    expect(entries.single['id'], 'offline:1');
    expect(entries.single['algorithm'], 'sha1');
    expect(
      (await SharedPreferences.getInstance()).getBool(
        IOSAutoFillService.enabledKey,
      ),
      true,
    );
  });

  test(
    'disabling during a read prevents republishing after revocation',
    () async {
      await initialize();
      await service.enable();
      calls.clear();
      final started = Completer<void>();
      final pending = Completer<List<Code>>();
      readCodes = () {
        started.complete();
        return pending.future;
      };
      final refresh = service.refresh();
      await started.future;
      await service.disable();
      expect(calls.last.method, 'clear');
      pending.complete([code(1)]);
      await refresh;
      expect(calls.map((call) => call.method), ['clear']);
      expect(service.isEnabled, false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          IOSAutoFillService.enabledKey,
        ),
        false,
      );
    },
  );

  test(
    'a vault change during a read drops the previous vault snapshot',
    () async {
      await initialize();
      await service.enable();
      calls.clear();
      final started = Completer<void>();
      final pending = Completer<List<Code>>();
      readCodes = () {
        started.complete();
        return pending.future;
      };
      final refresh = service.refresh();
      await started.future;
      scope = 'online:42';
      pending.complete([code(1)]);
      await refresh;
      expect(calls.where((call) => call.method == 'publish'), isEmpty);
      readCodes = () async => [code(2)];
      await service.refresh();
      final snapshot =
          jsonDecode(calls.last.arguments as String) as Map<String, dynamic>;
      expect(snapshot['entries'][0]['id'], 'online:42:2');
    },
  );

  test(
    'refresh failure disables AutoFill and clears old credentials',
    () async {
      await initialize();
      await service.enable();
      failPublish = true;
      await service.refresh();
      expect(service.isEnabled, false);
      expect(calls.last.method, 'clear');
    },
  );

  test('enabled AutoFill refreshes its snapshot on startup', () async {
    SharedPreferences.setMockInitialValues({
      IOSAutoFillService.enabledKey: true,
    });
    await initialize();
    expect(service.isEnabled, true);
    expect(calls.map((call) => call.method), ['isSupported', 'publish']);
  });
}
