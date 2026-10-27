import 'dart:io';

import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/store/offline_authenticator_db.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:ente_lock_screen/ui/lock_screen.dart';
import 'package:ente_network/network.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/theme/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final root = await Directory.systemTemp.createTemp('auth_keyboard_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const links = MethodChannel('com.llfbandit.app_links/messages');
    const linkEvents = MethodChannel('com.llfbandit.app_links/events');
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    messenger.setMockMethodCallHandler(links, (_) async => null);
    messenger.setMockMethodCallHandler(linkEvents, (_) async => null);
    addTearDown(() async {
      await (await OfflineAuthenticatorDB.instance.database).close();
      for (final channel in [paths, links, linkEvents]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      await root.delete(recursive: true);
    });

    SharedPreferences.setMockInitialValues({
      Configuration.hasOptedForOfflineModeKey: true,
      LockScreenSettings.keyAppLockSet: true,
      LockScreenSettings.keyHasMigratedLockScreenChanges: true,
    });
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Ente Auth',
      packageName: 'io.ente.auth',
      version: '4.4.27',
      buildNumber: '1007',
      buildSignature: '',
    );
    AppThemeConfig.initialize(EnteApp.auth);
    ComponentTheme.configure(app: ComponentApp.auth);
    await Configuration.instance.init([]);
    databaseFactory = databaseFactoryFfi;
    await Network.instance.init(Configuration.instance);
    await UserService.instance.init(Configuration.instance, const HomePage());
    await PreferenceService.instance.init();
    await AuthenticatorService.instance.init();
    await CodeStore.instance.init();
    await CodeDisplayStore.instance.init();
    await LockScreenSettings.instance.init(
      Configuration.instance,
      hasOptedForOfflineMode: true,
    );
    await OfflineAuthenticatorDB.instance.getAll();
  });

  for (final usePin in [true, false]) {
    for (final searchOpen in [false, true]) {
      testWidgets(
        '${usePin ? "PIN" : "password"} keeps keyboard focus after manual lock '
        'with search ${searchOpen ? "open" : "closed"}',
        (tester) async {
          const storage = FlutterSecureStorage();
          await storage.delete(
            key: usePin ? LockScreenSettings.password : LockScreenSettings.pin,
          );
          await storage.write(
            key: usePin ? LockScreenSettings.pin : LockScreenSettings.password,
            value: 'unused-hash',
          );
          await _pumpHome(tester);
          final homeSearch = tester.widget<TextField>(
            find.descendant(
              of: find.byType(HomePage),
              matching: find.byType(TextField, skipOffstage: false),
              skipOffstage: false,
            ),
          );
          if (searchOpen) {
            await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
            await tester.pump();
            expect(homeSearch.focusNode!.hasFocus, isTrue);
          }
          homeSearch.controller!.clear();
          final strings = StringsLocalizations.of(
            tester.element(find.byType(HomePage)),
          );
          await tester.tap(find.byTooltip(strings.appLock));
          await tester.pumpAndSettle();
          await tester.tap(find.text(strings.tapToUnlock));
          await tester.pumpAndSettle();

          final lockInput = tester.widget<EditableText>(
            find.byType(EditableText),
          );
          expect(lockInput.focusNode.hasFocus, isTrue);
          await _typeKey(
            tester,
            usePin ? LogicalKeyboardKey.digit1 : LogicalKeyboardKey.keyA,
            usePin ? '1' : 'a',
            usePin ? '1' : 'a',
          );
          await _typeKey(
            tester,
            LogicalKeyboardKey.numpad2,
            '2',
            usePin ? '12' : 'a2',
          );

          expect(lockInput.focusNode.hasFocus, isTrue);
          expect(lockInput.controller.text, usePin ? '12' : 'a2');
          expect(homeSearch.focusNode!.hasFocus, isFalse);
          expect(homeSearch.controller!.text, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets('Home search resumes after unlocking', (tester) async {
    await _pumpHome(tester);
    final context = tester.element(find.byType(HomePage));
    final homeSearch = tester.widget<TextField>(
      find.byType(TextField, skipOffstage: false),
    );
    final lock = AppLock.of(context)!;
    final lockFuture = lock.showManualLockScreen();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();
    expect(homeSearch.focusNode!.hasFocus, isFalse);
    lock.didUnlock();
    await lockFuture;
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await _typeKey(tester, LogicalKeyboardKey.keyA, 'a', 'a');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Home shortcuts leave another editable field focused', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpHome(
      tester,
      sibling: TextInputComponent(controller: controller, autofocus: true),
    );
    final context = tester.element(find.byType(HomePage));
    expect(FocusScope.of(context).hasFocus, isTrue);
    await _typeKey(tester, LogicalKeyboardKey.keyA, 'a', 'a');
    await _typeKey(tester, LogicalKeyboardKey.slash, '/', 'a/');
    expect(controller.text, 'a/');
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpHome(WidgetTester tester, {Widget? sibling}) async {
  Widget app() => MaterialApp(
    theme: lightThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: sibling == null
        ? const HomePage()
        : Stack(
            children: [
              const HomePage(),
              Align(
                alignment: Alignment.bottomCenter,
                child: Material(child: sibling),
              ),
            ],
          ),
  );
  await tester.runAsync(() async {
    await tester.pumpWidget(
      AppLock(
        builder: (_) => app(),
        lockScreen: LockScreen(Configuration.instance),
        enabled: false,
        savedThemeMode: ThemeMode.light,
        lightTheme: lightThemeData,
        supportedLocales: const [Locale('en')],
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        localeListResolutionCallback: (_, locales) => locales.first,
      ),
    );
    await CodeStore.instance.getAllCodes();
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  await tester.pumpAndSettle();
}

Future<void> _typeKey(
  WidgetTester tester,
  LogicalKeyboardKey key,
  String character,
  String text,
) async {
  await tester.sendKeyEvent(key, character: character);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  await tester.pump();
}
