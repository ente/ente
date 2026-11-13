import "dart:async";

import "package:ente_base/models/accounts.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/utils/dialog_util.dart" as shared_dialogs;
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/ott_verification_page.dart";
import "package:photos/ui/account/recovery_page.dart";
import "package:photos/utils/dialog_util.dart";

import "accounts_test_support.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = FakeAccountsClient();

  setUpAll(() => initializeAccountsTest(client));

  setUp(() {
    client.requests.clear();
    client.pendingRequest = null;
    client.failure = null;
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

  testWidgets("Rust network errors use friendly messages across apps", (
    tester,
  ) async {
    await tester.pumpWidget(app(const Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    for (final parse in [parseErrorForUI, shared_dialogs.parseErrorForUI]) {
      for (final timeout in [false, true]) {
        expect(
          parse(
            context,
            "Something went wrong",
            error: AccountsError.network(timeout: timeout),
            surfaceError: false,
          ),
          context.strings.networkConnectionRefusedErr,
        );
      }
    }
  });

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
        expect(client.requests, hasLength(3));
        for (final request in client.requests) {
          expect(request, {
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
    client.pendingRequest = Completer<void>();
    await tester.tap(find.text("Resend code"));
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.requests, hasLength(1));
    final pin = tester.widget<PinInputComponent>(
      find.byType(PinInputComponent),
    );
    expect(pin.isDisabled, isTrue);
    pin.controller.text = "123456";
    await tester.pump();
    expect(client.requests, hasLength(1));
    final actions = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(actions.every((button) => button.onPressed == null), isTrue);
    client.pendingRequest!.complete();
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
    client.failure = const AccountsError.notRegistered();
    await tester.tap(find.text("Resend code"));
    await settle(tester);
    expect(find.byType(OTTVerificationPage), findsOneWidget);
    expect(find.text("Resend code"), findsOneWidget);
    Navigator.of(tester.element(find.byType(OTTVerificationPage))).pop();
    await settle(tester);
    client.failure = null;
    await tester.tap(find.text("Resend code"));
    await settle(tester);
    expect(client.requests, hasLength(2));
    expect(find.byType(OTTVerificationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("disposed resend does not navigate after the response", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const OTTVerificationPage("person@example.com")),
    );
    client.pendingRequest = Completer<void>();
    await tester.tap(find.text("Resend code"));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    client.pendingRequest!.complete();
    await settle(tester);
    expect(client.requests, hasLength(1));
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
