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
  late bool failClear;
  late bool failInvalidate;
  late int generation;
  late List<dynamic> nativeEntries;
  late bool nativeRevoked;
  Completer<bool>? authenticationResult;
  void Function()? didPublish;

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
    failClear = false;
    failInvalidate = false;
    generation = 0;
    nativeEntries = [];
    nativeRevoked = true;
    authenticationResult = null;
    didPublish = null;
    messenger.setMockMethodCallHandler(IOSAutoFillService.channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
          return supported;
        case 'authenticate':
          return authenticationResult?.future ?? authenticated;
        case 'invalidate':
          if (failInvalidate) throw PlatformException(code: 'failed');
          nativeRevoked = true;
          return 'generation-${++generation}';
        case 'publish':
          if (failPublish) throw PlatformException(code: 'failed');
          final snapshot =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          if (snapshot['generation'] != 'generation-$generation') {
            throw PlatformException(code: 'revoked');
          }
          nativeEntries = snapshot['entries'] as List<dynamic>;
          nativeRevoked = false;
          didPublish?.call();
          return 0;
        case 'clear':
          // Like native clear, persist revocation before attempting cleanup.
          nativeRevoked = true;
          generation++;
          if (failClear) throw PlatformException(code: 'cleanup_failed');
          nativeEntries = [];
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
      expect(calls.map((call) => call.method), ['isSupported', 'clear']);
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
      expect(calls.map((call) => call.method), ['invalidate', 'clear']);
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
    expect(calls.map((call) => call.method), [
      'isSupported',
      'invalidate',
      'publish',
    ]);
  });

  test(
    'failed cleanup remains pending and is retried while disabled',
    () async {
      await initialize();
      await service.enable();
      failClear = true;
      await expectLater(service.disable(), throwsA(isA<PlatformException>()));
      expect(service.isEnabled, false);
      expect(service.hasPendingCleanup, true);
      expect(nativeRevoked, true);
      expect(nativeEntries, isNotEmpty);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          IOSAutoFillService.cleanupPendingKey,
        ),
        true,
      );
      failClear = false;
      await service.refresh();
      expect(calls.last.method, 'clear');
      expect(nativeEntries, isEmpty);
      expect(service.hasPendingCleanup, false);
    },
  );

  test(
    'pending cleanup on restart cannot silently re-enable the feature',
    () async {
      SharedPreferences.setMockInitialValues({
        IOSAutoFillService.enabledKey: true,
        IOSAutoFillService.cleanupPendingKey: true,
      });
      await initialize();
      expect(service.isEnabled, false);
      expect(calls.map((call) => call.method), ['isSupported', 'clear']);
    },
  );

  test('revocation works before service initialization', () async {
    await service.disable();
    expect(calls.single.method, 'clear');
    expect(nativeRevoked, true);
    expect(service.hasPendingCleanup, false);
    await initialize();
    expect(service.isSupported, true);
  });

  test(
    'legacy Base32 pad bits are canonicalized without losing usable entries',
    () async {
      const legacy = 'JBSWY3DPEHPK3PXPJBSWY3DPEH';
      readCodes = () async => [code(1).copyWith(secret: legacy), code(2)];
      await initialize();
      await service.enable();
      expect(service.isEnabled, true);
      expect(service.unavailableEntries, 0);
      expect(nativeEntries, hasLength(2));
      expect(nativeEntries.first['secret'], 'JBSWY3DPEHPK3PXPJBSWY3DPEE======');
    },
  );

  test(
    'bad secrets or settings are skipped and reported individually',
    () async {
      readCodes = () async => [
        code(1),
        code(2).copyWith(secret: '!'),
        code(3).copyWith(period: 0),
        code(4).copyWith(digits: 99),
      ];
      await initialize();
      expect(await service.enable(), true);
      expect(nativeEntries, hasLength(1));
      expect(nativeEntries.single['id'], 'offline:1');
      expect(service.unavailableEntries, 3);
    },
  );

  test(
    'new refresh invalidates immediately and fences an older read',
    () async {
      await initialize();
      await service.enable();
      final pending = Completer<List<Code>>();
      final started = Completer<void>();
      readCodes = () {
        started.complete();
        return pending.future;
      };
      final older = service.refresh();
      await started.future;
      readCodes = () async => [];
      final newer = service.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(nativeRevoked, true);
      calls.clear();
      pending.complete([code(1)]);
      await Future.wait([older, newer]);
      final publications = calls.where((call) => call.method == 'publish');
      expect(publications, hasLength(1));
      expect(nativeEntries, isEmpty);
    },
  );

  test(
    'database mutation revokes before executing and fences in-flight reads',
    () async {
      await initialize();
      await service.enable();
      final pending = Completer<List<Code>>();
      final started = Completer<void>();
      readCodes = () {
        started.complete();
        return pending.future;
      };
      final older = service.refresh();
      await started.future;
      calls.clear();
      await service.withInvalidatedSnapshot(() async {
        expect(nativeRevoked, true);
        readCodes = () async => [];
      });
      pending.complete([code(1)]);
      await older;
      await service.refresh();
      expect(nativeEntries, isEmpty);
      for (final call in calls.where((call) => call.method == 'publish')) {
        expect(jsonDecode(call.arguments as String)['entries'], isEmpty);
      }
    },
  );

  test('a mutation is not performed when native invalidation fails', () async {
    await initialize();
    await service.enable();
    failInvalidate = true;
    var mutated = false;
    await expectLater(
      service.withInvalidatedSnapshot(() async {
        mutated = true;
      }),
      throwsA(isA<PlatformException>()),
    );
    await service.refresh();
    expect(mutated, false);
  });

  test(
    'disabled state with unconfirmed cleanup still gates destructive mutations',
    () async {
      await initialize();
      await service.enable();
      failClear = true;
      await expectLater(service.disable(), throwsA(isA<PlatformException>()));
      var mutated = false;
      await expectLater(
        service.withInvalidatedSnapshot(() async {
          mutated = true;
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(mutated, false);
      failClear = false;
      await service.refresh();
      await service.withInvalidatedSnapshot(() async {
        mutated = true;
      });
      expect(mutated, true);
      expect(nativeEntries, isEmpty);
    },
  );

  test(
    'a partially committed mutation refreshes even when a later step fails',
    () async {
      await initialize();
      await service.enable();
      final republished = Completer<void>();
      didPublish = republished.complete;
      await expectLater(
        service.withInvalidatedSnapshot(() async {
          expect(nativeRevoked, true);
          // A fetched page committed a deletion, then another sync step failed.
          readCodes = () async => [];
          throw StateError('later sync step failed');
        }),
        throwsStateError,
      );
      await republished.future;
      expect(service.isEnabled, true);
      expect(nativeEntries, isEmpty);
    },
  );
}
