import "dart:async";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/ott_verification_page.dart";
import "package:photos/ui/account/recovery_page.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  Completer<void>? pendingRequest;
  Map<String, Object>? failure;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          await pendingRequest?.future;
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
      Dio(),
      dio,
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
  });

  setUp(() {
    requests.clear();
    pendingRequest = null;
    failure = null;
  });

  // The onboarding illustrations animate continuously, so the tree never
  // settles; pump a bounded stretch of frames instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget app(
    Widget home, {
    Locale? locale,
    ThemeData? theme,
    double scale = 1,
  }) {
    return MaterialApp(
      theme: theme ?? lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );
  }

  for (final mode in ["signup", "login", "change", "reset", "recreate"]) {
    testWidgets(
      "$mode resends stay on one route and preserve request purpose",
      (tester) async {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => UserService.instance.sendOtt(
                    context,
                    "person@example.com",
                    isCreateAccountScreen: mode == "signup",
                    isChangeEmail: mode == "change",
                    isResetPasswordScreen:
                        mode == "reset" || mode == "recreate",
                    isForgotPassword: mode == "reset",
                    purpose: mode == "signup" || mode == "login" ? mode : null,
                  ),
                  child: const Text("Enter email"),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text("Enter email"));
        await settle(tester);
        final page = tester.widget<OTTVerificationPage>(
          find.byType(OTTVerificationPage),
        );
        expect(page.isCreateAccountScreen, mode == "signup");
        expect(page.isChangeEmail, mode == "change");
        expect(
          page.isResetPasswordScreen,
          mode == "reset" || mode == "recreate",
        );
        expect(page.isForgotPassword, mode == "reset");
        final pin = tester.widget<PinInputComponent>(
          find.byType(PinInputComponent),
        );
        pin.controller.text = "12";
        await tester.pump();

        for (var resend = 0; resend < 2; resend++) {
          await tester.tap(find.text("Resend code"));
          await settle(tester);
          expect(
            find.byType(OTTVerificationPage, skipOffstage: false),
            findsOneWidget,
          );
          expect(pin.controller.text, "12");
        }
        expect(requests, hasLength(3));
        for (final request in requests) {
          expect(request.path, endsWith("/users/ott"));
          expect(request.data, {
            "email": "person@example.com",
            "purpose": mode == "reset" || mode == "recreate" ? "" : mode,
            "mobile": false,
          });
        }
        if (mode == "reset" || mode == "recreate") {
          expect(find.text("Change email"), findsNothing);
          Navigator.of(tester.element(find.byType(OTTVerificationPage))).pop();
        } else {
          await tester.tap(find.text("Change email"));
        }
        await settle(tester);
        expect(find.text("Enter email"), findsOneWidget);
        expect(
          find.byType(OTTVerificationPage, skipOffstage: false),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets("change email unwinds a password-verification fallback", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => UserService.instance.sendOtt(
                        context,
                        "person@example.com",
                        isCreateAccountScreen: true,
                        onChangeEmail: () => Navigator.of(context).pop(),
                      ),
                      child: const Text("Password fallback"),
                    ),
                  ),
                ),
              ),
              child: const Text("Enter email"),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text("Enter email"));
    await settle(tester);
    await tester.tap(find.text("Password fallback"));
    await settle(tester);
    await tester.tap(find.text("Resend code"));
    await settle(tester);
    await tester.tap(find.text("Change email"));
    await settle(tester);
    expect(find.text("Enter email"), findsOneWidget);
    expect(find.text("Password fallback"), findsNothing);
    expect(find.byType(OTTVerificationPage, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("pending resend blocks duplicate sends and code submission", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const OTTVerificationPage("person@example.com")),
    );
    pendingRequest = Completer<void>();
    await tester.tap(find.text("Resend code"));
    await tester.pump(const Duration(milliseconds: 300));
    expect(requests, hasLength(1));
    final pin = tester.widget<PinInputComponent>(
      find.byType(PinInputComponent),
    );
    expect(pin.isDisabled, isTrue);
    pin.controller.text = "123456";
    await tester.pump();
    expect(requests, hasLength(1));
    final actions = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(actions.every((button) => button.onPressed == null), isTrue);
    pendingRequest!.complete();
    await settle(tester);
    expect(find.byType(OTTVerificationPage), findsOneWidget);
    expect(
      tester
          .widget<PinInputComponent>(find.byType(PinInputComponent))
          .isDisabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("failed resend preserves the page and permits a retry", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const OTTVerificationPage("person@example.com")),
    );
    failure = {"code": "USER_NOT_REGISTERED"};
    await tester.tap(find.text("Resend code"));
    await settle(tester);
    expect(find.byType(OTTVerificationPage), findsOneWidget);
    expect(find.text("Resend code"), findsOneWidget);
    Navigator.of(tester.element(find.byType(OTTVerificationPage))).pop();
    await settle(tester);
    failure = null;
    await tester.tap(find.text("Resend code"));
    await settle(tester);
    expect(requests, hasLength(2));
    expect(find.byType(OTTVerificationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("disposed resend does not navigate after the response", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const OTTVerificationPage("person@example.com")),
    );
    pendingRequest = Completer<void>();
    await tester.tap(find.text("Resend code"));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    pendingRequest!.complete();
    await settle(tester);
    expect(requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final theme in [lightThemeData, darkThemeData]) {
    testWidgets(
      "Russian actions wrap at large text scale in ${theme.brightness}",
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          app(
            const OTTVerificationPage("person@example.com"),
            locale: const Locale("ru"),
            theme: theme,
            scale: 2,
          ),
        );
        await settle(tester);
        final context = tester.element(find.byType(OTTVerificationPage));
        for (final label in [
          context.strings.changeEmail,
          context.strings.resendCode,
        ]) {
          final action = find.text(label);
          await tester.scrollUntilVisible(
            action,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await settle(tester);
          final rect = tester.getRect(action);
          expect(rect.left, greaterThanOrEqualTo(16));
          expect(rect.right, lessThanOrEqualTo(304));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final forgotPassword in [true, false]) {
    testWidgets(
      "recovery title matches forgot-password context $forgotPassword",
      (tester) async {
        await tester.pumpWidget(
          app(RecoveryPage(isForgotPassword: forgotPassword)),
        );
        final context = tester.element(find.byType(RecoveryPage));
        final title = forgotPassword
            ? context.strings.forgotPassword
            : context.strings.recoverAccount;
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
