import "dart:io";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/email_entry_page.dart";
import "package:photos/ui/account/login_page.dart";
import "package:photos/ui/account/ott_verification_page.dart";
import "package:photos/ui/account/recovery_page.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, Object>? failure;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({"email": "person@example.com"});
    final preferences = await SharedPreferences.getInstance();
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (failure != null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: failure,
                ),
              ),
            );
          } else {
            handler.resolve(Response(requestOptions: options, statusCode: 200));
          }
        },
      ),
    );
    ServiceLocator.instance.init(
      preferences,
      dio,
      dio,
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
    const pathProvider = MethodChannel("plugins.flutter.io/path_provider");
    final directory = Directory.systemTemp.createTempSync("onboarding").path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => directory);
    try {
      await Configuration.instance.init(preferences);
    } on MissingPluginException catch (_) {}
    await UserService.instance.init();
  });

  setUp(() {
    failure = null;
  });

  // The illustrations animate continuously, so pump a bounded stretch.
  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget app(Widget home) {
    return MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: home,
    );
  }

  testWidgets("login validates the email after typing pauses", (tester) async {
    await tester.pumpWidget(app(const LoginPage()));
    await settle(tester, 20);
    final context = tester.element(find.byType(LoginPage));
    expect(find.text("person@example.com"), findsOneWidget);
    expect(find.text(context.strings.validEmailAddress), findsNothing);
    expect(find.text(context.strings.invalidEmailAddress), findsNothing);

    await tester.enterText(find.byType(TextField), "bad@");
    await settle(tester, 20);
    expect(find.text(context.strings.invalidEmailAddress), findsOneWidget);
    expect(
      tester
          .widget<ButtonComponent>(find.byKey(const ValueKey("logInButton")))
          .isDisabled,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), "new@example.com");
    await settle(tester, 20);
    expect(find.text(context.strings.validEmailAddress), findsOneWidget);
    expect(
      tester
          .widget<ButtonComponent>(find.byKey(const ValueKey("logInButton")))
          .isDisabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("header collapses while the keyboard is open", (tester) async {
    tester.view.physicalSize = const Size(375, 831);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const LoginPage()));
    await settle(tester);
    final context = tester.element(find.byType(LoginPage));
    final title = find.text(context.strings.loginToEnte);
    expect(tester.getTopLeft(title).dy, greaterThan(200));

    tester.view.viewInsets = const FakeViewPadding(bottom: 291);
    await settle(tester);
    expect(tester.getTopLeft(title).dy, greaterThan(200));

    tester.view.viewInsets = FakeViewPadding.zero;
    await settle(tester);
    expect(tester.getTopLeft(title).dy, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets("incorrect code clears the field and refocuses it", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const OTTVerificationPage("person@example.com")),
    );
    await settle(tester);
    failure = {"code": "INCORRECT_OTT"};
    final pin = tester.widget<PinInputComponent>(
      find.byType(PinInputComponent),
    );
    pin.controller.text = "123456";
    await settle(tester, 20);
    final context = tester.element(find.byType(OTTVerificationPage));
    expect(find.text(context.strings.incorrectCode), findsOneWidget);

    await tester.tap(find.byType(BottomSheetCloseButton));
    await settle(tester, 20);
    expect(find.text(context.strings.incorrectCode), findsNothing);
    expect(find.byType(OTTVerificationPage), findsOneWidget);
    expect(pin.controller.text, isEmpty);
    expect(pin.focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets("forgot recovery key sheet closes from its button", (
    tester,
  ) async {
    await tester.pumpWidget(app(const RecoveryPage(isForgotPassword: true)));
    await settle(tester);
    final context = tester.element(find.byType(RecoveryPage));
    await tester.tap(find.text(context.strings.forgotRecoveryKey));
    await settle(tester);
    expect(
      find.text(context.strings.noRecoveryKeyNoDecryption),
      findsOneWidget,
    );

    await tester.tap(find.text(context.strings.ok));
    await settle(tester);
    expect(find.text(context.strings.noRecoveryKeyNoDecryption), findsNothing);
    expect(find.byType(RecoveryPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("sign-up enables submission only once the form is valid", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 831);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(const EmailEntryPage(showReferralSourceField: false)),
    );
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), "new@example.com");
    await tester.enterText(fields.at(1), "correct horse battery staple");
    await tester.enterText(fields.at(2), "correct horse battery staple");
    await settle(tester, 15);
    final button = find.byKey(const ValueKey("createAccountButton"));
    expect(tester.widget<ButtonComponent>(button).isDisabled, isTrue);

    await tester.ensureVisible(find.byType(CheckboxComponent));
    await tester.tap(find.byType(CheckboxComponent));
    await settle(tester);
    expect(tester.widget<ButtonComponent>(button).isDisabled, isFalse);

    await tester.enterText(fields.at(2), "different");
    await settle(tester, 15);
    final context = tester.element(find.byType(EmailEntryPage));
    expect(find.text(context.strings.passwordsDontMatch), findsOneWidget);
    expect(tester.widget<ButtonComponent>(button).isDisabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
