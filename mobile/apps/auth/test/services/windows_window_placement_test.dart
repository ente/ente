import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/services/window_placement.dart';
import 'package:ente_auth/services/windows_window_placement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.ente.auth/window_geometry');
  const key = 'windowsWindowPlacement';
  const size = Size(500, 420);
  const normal = Rect.fromLTWH(180, 150, 500, 420);
  const moved = Rect.fromLTWH(300, 180, 460, 380);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SharedPreferences preferences;
  late WindowsWindowPlacement placement;
  late Map<String, dynamic> snapshot;
  Rect? restored;
  var captures = 0;
  var fail = false;
  Completer<void>? blocked;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    placement = WindowsWindowPlacement(preferences);
    restored = null;
    captures = 0;
    fail = false;
    blocked = null;
    snapshot = {
      'normalBounds': rectJson(normal),
      'normalMonitorId': 'primary',
      'maximized': false,
      'minimized': false,
      'monitors': [
        {
          'id': 'primary',
          'workArea': rectJson(const Rect.fromLTWH(0, 0, 1920, 1040)),
          'dpi': 96,
          'primary': true,
        },
      ],
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'snapshot') {
        captures++;
        if (fail) throw PlatformException(code: 'test-failure');
        await blocked?.future;
        return snapshot;
      }
      if (call.method == 'setBounds') {
        restored = readRect(call.arguments as Map);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Placement saved() => Placement.fromJson(
    jsonDecode(preferences.getString(key)!) as Map<String, dynamic>,
  );

  test('persists geometry and ignores startup saves', () async {
    await placement.startSaving();
    snapshot['normalBounds'] = rectJson(moved);
    snapshot['maximized'] = true;
    await placement.save();
    placement = WindowsWindowPlacement(preferences);
    snapshot['normalBounds'] = rectJson(normal);
    snapshot['maximized'] = false;
    await placement.save(maximized: false);
    expect(await placement.restore(size, false), isTrue);
    expect(restored, moved);
    await placement.save(maximized: false);
    expect(saved().maximized, isTrue);
    await placement.startSaving();
    expect(saved().maximized, isFalse);
  });

  for (final stored in [null, '{broken']) {
    test('legacy defaults with stored placement: $stored', () async {
      if (stored != null) await preferences.setString(key, stored);
      expect(await placement.restore(size, true), isTrue);
      expect(restored, const Rect.fromLTWH(70, 70, 500, 420));
    });
  }

  test('queued saves retain placement through minimize', () async {
    await placement.startSaving();
    snapshot['normalBounds'] = rectJson(moved);
    blocked = Completer<void>();
    final maximize = placement.save(maximized: true);
    final flush = placement.save();
    await Future<void>.delayed(Duration.zero);
    expect(captures, 2);
    snapshot['minimized'] = true;
    blocked!.complete();
    await flush;
    expect(captures, 3);
    expect(saved().logicalBounds, moved);
    expect(saved().maximized, isTrue);
    await maximize;
    snapshot['minimized'] = false;
    await placement.save(maximized: false);
    expect(saved().maximized, isFalse);
  });

  test('a failed capture retains state events before minimizing', () async {
    await placement.startSaving();
    fail = true;
    await placement.save(maximized: true);
    fail = false;
    snapshot['minimized'] = true;
    await placement.save();
    expect(saved().logicalBounds, normal);
    expect(saved().maximized, isTrue);
  });
}
