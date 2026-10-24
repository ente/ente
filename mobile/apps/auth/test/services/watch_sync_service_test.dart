import 'dart:async';
import 'dart:io';

import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/services/watch_sync_service.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:ente_events/event_bus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secret = 'JBSWY3DPEHPK3PXP';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.ente.auth/watch.test');
  final service = WatchSyncService.instance;

  tearDown(() {
    service.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start does not call the channel off iOS', () {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    service.debugConfigure(
      channel: channel,
      codesLoader: () async => [_code(id: 1)],
    );
    service.start();
    expect(Platform.isIOS, isFalse);
    expect(calls, isEmpty);
  });

  test('a push sends syncTokens and remembers ids for the next deletion set', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    service.debugConfigure(
      channel: channel,
      codesLoader: () async => [_code(id: 42)],
    );

    await service.debugPushNow();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'syncTokens');
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(args['version'], 1);
    expect(args['syncType'], 'DELTA');
    final tokens = args['tokens']! as List<Object?>;
    final token = Map<String, Object?>.from(tokens.single! as Map);
    expect(token['id'], '42');
    expect(token['secret'], _secret);
    expect(args['deletedIds'], isEmpty);

    service.debugConfigure(
      channel: channel,
      codesLoader: () async => const <Code>[],
    );
    await service.debugPushNow();

    expect(calls, hasLength(2));
    final second = Map<String, Object?>.from(calls[1].arguments as Map);
    expect(second['tokens'], isEmpty);
    expect(second['deletedIds'], ['42']);
  });

  test('a missing channel does not throw or record ids', () async {
    service.debugConfigure(
      channel: const MethodChannel('io.ente.auth/watch.missing'),
      codesLoader: () async => [_code(id: 7)],
    );

    await service.debugPushNow();
    service.debugConfigure(
      channel: const MethodChannel('io.ente.auth/watch.missing'),
      codesLoader: () async => const <Code>[],
    );
    await service.debugPushNow();

    const recovered = MethodChannel('io.ente.auth/watch.recovered');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recovered, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recovered, null);
    });
    service.debugConfigure(
      channel: recovered,
      codesLoader: () async => const <Code>[],
    );
    await service.debugPushNow();
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(args['deletedIds'], isEmpty);
  });

  test('cold start and a later removal both call syncTokens', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    var codes = <Code>[_code(id: 42)];
    service.debugConfigure(
      channel: channel,
      codesLoader: () async => codes,
    );

    service.debugStart();
    await _waitUntil(() => calls.length >= 1);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'syncTokens');
    final first = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(first['version'], 1);
    expect(first['syncType'], 'DELTA');
    final firstTokens = first['tokens']! as List<Object?>;
    final firstToken = Map<String, Object?>.from(firstTokens.single! as Map);
    expect(firstToken['id'], '42');
    expect(firstToken['secret'], _secret);
    expect(firstToken['isFavorite'], isTrue);
    expect(first['deletedIds'], isEmpty);

    codes = <Code>[];
    Bus.instance.fire(CodesUpdatedEvent());
    await _waitUntil(() => calls.length >= 2);
    expect(calls, hasLength(2));
    expect(calls[1].method, 'syncTokens');
    final second = Map<String, Object?>.from(calls[1].arguments as Map);
    expect(second['tokens'], isEmpty);
    expect(second['deletedIds'], ['42']);
  });

  test('a sort key change resends sortOrder on the next event', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final codes = <Code>[
      _code(
        id: 1,
        issuer: 'Zoom',
        account: 'z@example.com',
        pinned: false,
        tags: const ['#watch'],
        position: 0,
      ),
      _code(
        id: 2,
        issuer: 'alpha',
        account: 'a@example.com',
        pinned: true,
        position: 5,
      ),
    ];
    service.debugConfigure(
      channel: channel,
      codesLoader: () async => codes,
      sortKey: CodeSortKey.issuerName,
    );

    service.debugStart();
    await _waitUntil(() => calls.length >= 1);
    final first = Map<String, Object?>.from(calls.single.arguments as Map);
    final firstTokens = [
      for (final token in first['tokens']! as List<Object?>)
        Map<String, Object?>.from(token! as Map),
    ];
    expect(firstTokens.map((token) => token['id']), ['2', '1']);
    expect(firstTokens.map((token) => token['sortOrder']), [0, 1]);
    expect(firstTokens[0]['isFavorite'], isTrue);
    expect(firstTokens[1]['isFavorite'], isFalse);

    service.debugConfigure(
      channel: channel,
      codesLoader: () async => codes,
      sortKey: CodeSortKey.manual,
    );
    Bus.instance.fire(CodesUpdatedEvent());
    await _waitUntil(() => calls.length >= 2);
    final second = Map<String, Object?>.from(calls[1].arguments as Map);
    final secondTokens = [
      for (final token in second['tokens']! as List<Object?>)
        Map<String, Object?>.from(token! as Map),
    ];
    expect(secondTokens.map((token) => token['id']), ['1', '2']);
    expect(secondTokens.map((token) => token['sortOrder']), [0, 1]);
    expect(second['deletedIds'], isEmpty);
  });

  test('bursts inside 300ms share one push', () {
    fakeAsync((async) {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls += 1;
            return null;
          });
      service.debugReset();
      service.debugConfigure(
        channel: channel,
        codesLoader: () async => [_code(id: 1)],
      );

      service.debugScheduleSync();
      service.debugScheduleSync();
      service.debugScheduleSync();
      async.elapse(const Duration(milliseconds: 299));
      async.flushMicrotasks();
      expect(calls, 0);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(calls, 1);

      service.debugScheduleSync();
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();
      expect(calls, 2);
    });
  });

  test('service source does not log the payload', () {
    final source = File(
      'lib/services/watch_sync_service.dart',
    ).readAsStringSync();
    expect(source.contains('print('), isFalse);
    expect(source.contains(_secret), isFalse);
    expect(source.contains('payload.toJson()'), isTrue);
  });

  test('main starts watch sync after authenticator init on iOS only', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final initAt = mainSource.indexOf('AuthenticatorService.instance.init()');
    final startAt = mainSource.indexOf('WatchSyncService.instance.start()');
    expect(initAt, greaterThanOrEqualTo(0));
    expect(startAt, greaterThan(initAt));

    final serviceSource = File(
      'lib/services/watch_sync_service.dart',
    ).readAsStringSync();
    expect(serviceSource.contains('!Platform.isIOS'), isTrue);
    expect(serviceSource.contains('MissingPluginException'), isTrue);
    expect(serviceSource.contains('CodesUpdatedEvent'), isTrue);

    final delegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    expect(
      delegate.contains('EnteWatchBridgePlugin.register'),
      isTrue,
    );
  });

  test('copy request is action and id, and the lookup returns the phone code', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PreferenceService.instance.init();
    final code = _code(id: 42);
    final otp = otpForWatchCopy(id: '42', codes: [code]);
    expect(otp, getOTP(code));
    expect(otp, isNot(_secret));
    expect(otpForWatchCopy(id: '7', codes: [code]), isNull);
    expect(
      otpForWatchCopy(id: '8', codes: [_code(id: 8, pinned: false)]),
      isNull,
    );
    expect(
      otpForWatchCopy(
        id: '10',
        codes: [_code(id: 10, pinned: false, tags: const ['#watch'])],
      ),
      isNotNull,
    );
    expect(
      otpForWatchCopy(
        id: '12',
        codes: [
          _code(
            id: 12,
            display: CodeDisplay(pinned: true, trashed: true),
          ),
        ],
      ),
      isNull,
    );
    expect(
      otpForWatchCopy(id: '13', codes: [_code(id: 13, type: Type.hotp)]),
      isNull,
    );
    expect(
      otpForWatchCopy(id: '14', codes: [_code(id: 14, type: Type.steam)]),
      isNull,
    );
    expect(
      otpForWatchCopy(
        id: '15',
        codes: [_code(id: 15, issuer: 'Steam')],
      ),
      isNull,
    );
    expect(
      watchCopyID({'id': '42', 'secret': _secret, 'otp': '123456'}),
      '42',
    );
    expect(watchCopyID({'secret': _secret}), isNull);

    final message = watchCopyMessage(id: '42');
    expect(message.keys.toSet(), {'action', 'id'});
    expect(message['action'], 'copyCode');
    expect(message['id'], '42');
    expect(message.containsValue(_secret), isFalse);
    expect(message.containsValue(otp), isFalse);

    service.debugConfigure(
      channel: channel,
      codesLoader: () async => [code],
    );
    expect(await service.debugCurrentCode('42'), otp);
    expect(await service.debugCurrentCode('7'), isNull);

    service.debugBindCopyHandler();
    final response = await _invoke(
      channel,
      const MethodCall('currentCode', {
        'id': '42',
        'secret': _secret,
        'otp': '123456',
      }),
    );
    final payload = Map<String, Object?>.from(response! as Map);
    expect(payload.keys.toSet(), {'code', 'period'});
    expect(payload['code'], otp);
    expect(payload['period'], code.period);
    expect(payload.containsValue(_secret), isFalse);
    expect(payload.containsKey('otp'), isFalse);
    expect(payload.containsKey('secret'), isFalse);

    final longer = _code(id: 45, period: 45);
    service.debugConfigure(
      channel: channel,
      codesLoader: () async => [longer],
    );
    service.debugBindCopyHandler();
    final longerResponse = await _invoke(
      channel,
      const MethodCall('currentCode', {'id': '45'}),
    );
    final longerPayload = Map<String, Object?>.from(longerResponse! as Map);
    expect(longerPayload.keys.toSet(), {'code', 'period'});
    expect(longerPayload['period'], 45);
    expect(longerPayload['code'], isNot(_secret));
    expect(longerPayload.containsKey('secret'), isFalse);
  });
}

Future<Object?> _invoke(MethodChannel channel, MethodCall call) async {
  final completer = Completer<ByteData?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(call),
        completer.complete,
      );
  final envelope = await completer.future;
  return const StandardMethodCodec().decodeEnvelope(envelope!);
}

Future<void> _waitUntil(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

Code _code({
  required int id,
  String issuer = 'GitHub',
  String account = 'octocat@github.com',
  bool pinned = true,
  List<String> tags = const [],
  int position = 0,
  int period = Code.defaultPeriod,
  Type type = Type.totp,
  CodeDisplay? display,
}) {
  return Code(
    account,
    issuer,
    type == Type.steam ? Code.steamDigits : Code.defaultDigits,
    period,
    _secret,
    Algorithm.sha1,
    type,
    0,
    'otpauth://${type.name}/$issuer:$account?secret=$_secret',
    generatedID: id,
    display: display ??
        CodeDisplay(pinned: pinned, tags: tags, position: position),
  );
}
