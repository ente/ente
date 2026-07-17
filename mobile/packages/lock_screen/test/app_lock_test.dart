import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets('can hide the debug banner', (tester) async {
    await tester.pumpWidget(
      _buildAppLock(ThemeMode.system, debugShowCheckedModeBanner: false),
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
  });
}

Widget _buildAppLock(
  ThemeMode savedThemeMode, {
  Widget? child,
  bool debugShowCheckedModeBanner = true,
}) {
  return AppLock(
    builder: (_) =>
        child ??
        Builder(builder: (context) => Text(Theme.of(context).brightness.name)),
    lockScreen: const SizedBox.shrink(),
    enabled: false,
    savedThemeMode: savedThemeMode,
    lightTheme: ThemeData(brightness: Brightness.light),
    darkTheme: ThemeData(brightness: Brightness.dark),
    debugShowCheckedModeBanner: debugShowCheckedModeBanner,
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[],
    localeListResolutionCallback: (_, supportedLocales) =>
        supportedLocales.first,
  );
}
