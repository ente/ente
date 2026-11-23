import "dart:io";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/error-reporting/super_logging.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/settings/security/security_settings_page.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const email = "person@example.com";
  final requests = <(RequestOptions, RequestInterceptorHandler)>[];

  setUpAll(() async {
    const paths = MethodChannel("plugins.flutter.io/path_provider");
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final directory = await Directory.systemTemp.createTemp(
      "security-settings",
    );
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      await directory.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({
      Configuration.emailKey: email,
      Configuration.userIDKey: 1,
      Configuration.hasSecureTokenKey: true,
    });
    FlutterSecureStorage.setMockInitialValues({
      Configuration.tokenKey: "token",
      Configuration.keyKey: "a2V5",
    });
    final preferences = await SharedPreferences.getInstance();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => requests.add((options, handler)),
        ),
      );
    ServiceLocator.instance.init(
      preferences,
      dio,
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
    SuperLogging.appVersion = "test";
    await SuperLogging.main();
    await Configuration.instance.init(preferences);
    await UserService.instance.init();
  });

  setUp(() async {
    requests.clear();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserService.keyHasEnabledTwoFactor, true);
  });

  void respondWithProfile(Map<String, Object> profile) {
    final (options, handler) = requests.last;
    handler.resolve(
      Response(
        requestOptions: options,
        data: {
          "email": email,
          "usage": 0,
          "subscription": {
            "productID": "free",
            "storage": 0,
            "originalTransactionID": "",
            "paymentProvider": "",
            "expiryTime": 0,
            "price": "",
            "period": "",
          },
          "profileData": profile,
        },
      ),
    );
  }

  testWidgets("2FA shows the cached status until a refresh confirms it", (
    tester,
  ) async {
    final userService = UserService.instance;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: const SecuritySettingsPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    final context = tester.element(find.byType(SecuritySettingsPage));
    final row = find.widgetWithText(SettingsItem, context.strings.twofactor);
    final toggle = find.descendant(
      of: row,
      matching: find.byType(ToggleSwitchComponent),
    );
    final loading = find.descendant(
      of: row,
      matching: find.byType(LoadingComponent),
    );
    final retry = find.byTooltip(context.strings.retry);
    expect(loading, findsNothing);
    expect(tester.widget<ToggleSwitchComponent>(toggle).selected, isTrue);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNull);

    final (options, handler) = requests.single;
    handler.reject(DioException(requestOptions: options));
    await tester.pumpAndSettle();
    expect(retry, findsOneWidget);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNull);

    await tester.tap(retry);
    await tester.pump(const Duration(milliseconds: 1));
    expect(retry, findsNothing);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNull);
    respondWithProfile({});
    await tester.pumpAndSettle();
    expect(retry, findsOneWidget);
    expect(tester.widget<ToggleSwitchComponent>(toggle).selected, isTrue);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNull);
    expect(userService.hasEnabledTwoFactor(), isTrue);

    await tester.tap(retry);
    await tester.pump(const Duration(milliseconds: 1));
    respondWithProfile({"isTwoFactorEnabled": false});
    await tester.pumpAndSettle();
    expect(retry, findsNothing);
    expect(tester.widget<ToggleSwitchComponent>(toggle).selected, isFalse);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNotNull);
    expect(userService.hasEnabledTwoFactor(), isFalse);
    expect(requests.map((request) => request.$1.path), [
      "/users/details/v2",
      "/users/details/v2",
      "/users/details/v2",
    ]);
  });

  testWidgets("2FA without a cached status refetches after an outside change", (
    tester,
  ) async {
    final userService = UserService.instance;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(UserService.keyHasEnabledTwoFactor);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: const SecuritySettingsPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    final context = tester.element(find.byType(SecuritySettingsPage));
    final row = find.widgetWithText(SettingsItem, context.strings.twofactor);
    final toggle = find.descendant(
      of: row,
      matching: find.byType(ToggleSwitchComponent),
    );
    final loading = find.descendant(
      of: row,
      matching: find.byType(LoadingComponent),
    );
    final retry = find.byTooltip(context.strings.retry);
    expect(loading, findsOneWidget);
    expect(toggle, findsNothing);

    final (options, handler) = requests.single;
    handler.reject(DioException(requestOptions: options));
    await tester.pumpAndSettle();
    expect(retry, findsOneWidget);
    expect(loading, findsNothing);
    expect(toggle, findsNothing);

    userService.getUserDetailsV2().ignore();
    await tester.pump(const Duration(milliseconds: 1));
    respondWithProfile({"isTwoFactorEnabled": false});
    await tester.pump(const Duration(milliseconds: 1));
    expect(retry, findsNothing);
    expect(tester.widget<ToggleSwitchComponent>(toggle).selected, isFalse);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNull);

    respondWithProfile({"isTwoFactorEnabled": false});
    await tester.pumpAndSettle();
    expect(tester.widget<ToggleSwitchComponent>(toggle).selected, isFalse);
    expect(tester.widget<ToggleSwitchComponent>(toggle).onChanged, isNotNull);
    expect(requests.map((request) => request.$1.path), [
      "/users/details/v2",
      "/users/details/v2",
      "/users/details/v2",
    ]);
  });
}
