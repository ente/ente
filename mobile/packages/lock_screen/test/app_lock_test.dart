import 'dart:ui' as ui;

import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('lifecycle content visibility', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        LockScreenSettings.keyHasMigratedLockScreenChanges: true,
        LockScreenSettings.autoLockTime: 5000,
      });
      await LockScreenSettings.instance.init(
        _OfflineHost(),
        hasOptedForOfflineMode: true,
      );
    });

    testWidgets('iOS covers interruptions without locking the session', (
      tester,
    ) async {
      await _pumpUnlockedApp(tester);
      expect(await _paintedColor(tester), _sensitiveColor);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(await _paintedColor(tester), Colors.white);
      expect(find.text('Unlock'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(await _paintedColor(tester), _sensitiveColor);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final elapsed in [
      const Duration(seconds: 1),
      const Duration(seconds: 6),
    ]) {
      testWidgets('iOS preserves the background lock delay after $elapsed', (
        tester,
      ) async {
        await _pumpUnlockedApp(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(elapsed);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        if (elapsed.inSeconds < 5) {
          expect(await _paintedColor(tester), _sensitiveColor);
        } else {
          expect(find.text('Unlock'), findsOneWidget);
          expect(await _paintedColor(tester), isNot(_sensitiveColor));
          await tester.tap(find.text('Unlock'));
          await tester.pumpAndSettle();
          expect(await _paintedColor(tester), _sensitiveColor);
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  });

  testWidgets('updates theme mode after startup', (tester) async {
    await tester.pumpWidget(
      _buildAppLock(
        ThemeMode.dark,
        child: Builder(
          builder: (context) => Column(
            children: [
              Text(Theme.of(context).brightness.name),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => AppLock.of(context)!.setThemeMode(ThemeMode.light),
                child: const Text('Use light'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('dark'), findsOneWidget);

    await tester.tap(find.text('Use light'));
    await tester.pumpAndSettle();

    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('syncs theme mode when savedThemeMode changes', (tester) async {
    await tester.pumpWidget(_buildAppLock(ThemeMode.dark));

    expect(find.text('dark'), findsOneWidget);

    await tester.pumpWidget(_buildAppLock(ThemeMode.light));
    await tester.pumpAndSettle();

    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('covers unlocked content until unlock', (tester) async {
    await tester.pumpWidget(
      _buildAppLock(
        ThemeMode.light,
        child: Builder(
          builder: (context) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => AppLock.of(context)!.showLockScreen(),
            child: const Text('secret content'),
          ),
        ),
        lockScreen: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppLock.of(context)!.didUnlock(),
            child: const Text('Unlock'),
          ),
        ),
      ),
    );

    final obscurer = find.byKey(appLockContentObscurerKey, skipOffstage: false);

    expect(obscurer, findsNothing);

    await tester.tap(find.text('secret content'));
    await tester.pumpAndSettle();

    expect(obscurer, findsOneWidget);

    await tester.pump(const Duration(seconds: 1));

    expect(obscurer, findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(obscurer, findsNothing);
  });
}

const _sensitiveColor = Color(0xFFFF0000);
const _paintBoundary = ValueKey('app lock painted output');

Future<void> _pumpUnlockedApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _paintBoundary,
      child: _buildAppLock(
        ThemeMode.light,
        enabled: true,
        child: const ColoredBox(color: _sensitiveColor),
        lockScreen: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppLock.of(context)!.didUnlock(),
            child: const Text('Unlock'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Unlock'));
  await tester.pumpAndSettle();
}

Future<Color?> _paintedColor(WidgetTester tester) => tester.runAsync(() async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_paintBoundary),
  );
  final image = await boundary.toImage();
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  final color = Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
  image.dispose();
  return color;
});

class _OfflineHost implements LockScreenHost {
  @override
  bool isLoggedIn() => false;

  @override
  Future<void> logout() async {}
}

Widget _buildAppLock(
  ThemeMode savedThemeMode, {
  Widget? child,
  Widget lockScreen = const SizedBox.shrink(),
  bool debugShowCheckedModeBanner = true,
  bool enabled = false,
}) {
  return AppLock(
    builder: (_) =>
        child ??
        Builder(builder: (context) => Text(Theme.of(context).brightness.name)),
    lockScreen: lockScreen,
    enabled: enabled,
    savedThemeMode: savedThemeMode,
    lightTheme: ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
    ),
    darkTheme: ThemeData(brightness: Brightness.dark),
    debugShowCheckedModeBanner: debugShowCheckedModeBanner,
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[],
    localeListResolutionCallback: (_, supportedLocales) =>
        supportedLocales.first,
  );
}
