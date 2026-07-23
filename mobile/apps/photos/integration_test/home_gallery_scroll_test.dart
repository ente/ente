import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:logging/logging.dart";
import "package:photos/main.dart" as app;
import "package:scrollable_positioned_list/scrollable_positioned_list.dart";

void main() {
  group("Home gallery scroll test", () {
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    testWidgets("Home gallery scroll test", semanticsEnabled: false, (
      tester,
    ) async {
      // https://github.com/flutter/flutter/issues/89749#issuecomment-1029965407
      tester.testTextInput.register();

      await runZonedGuarded(
        () async {
          ///Ignore exceptions thrown by the app for the test to pass
          WidgetsFlutterBinding.ensureInitialized();
          FlutterError.onError = (FlutterErrorDetails errorDetails) {
            FlutterError.dumpErrorToConsole(errorDetails);
          };

          app.main();

          await tester.pumpAndSettle(const Duration(seconds: 1));

          await dismissUpdateAppDialog(tester);

          final signInButton = find.byKey(const ValueKey("signInButton"));
          await tester.tap(signInButton);
          await tester.pumpAndSettle();

          final emailInputField = find.byType(TextFormField);
          final logInButton = find.byKey(const ValueKey("logInButton"));
          //Fill email id here
          await tester.enterText(emailInputField, "enter email here");
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await tester.tap(logInButton);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          final passwordInputField = find.byKey(
            const ValueKey("passwordInputField"),
          );
          final verifyPasswordButton = find.byKey(
            const ValueKey("verifyPasswordButton"),
          );
          //Fill password here
          await tester.enterText(passwordInputField, "enter password here");
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await tester.tap(verifyPasswordButton);
          await tester.pumpAndSettle();

          await tester.pumpAndSettle(const Duration(seconds: 1));
          await dismissUpdateAppDialog(tester);

          //Grant permission to access photos. Must manually click the system dialog.
          final grantPermissionButton = find.byKey(
            const ValueKey("grantPermissionButton"),
          );
          await tester.tap(grantPermissionButton);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await tester.pumpAndSettle(const Duration(seconds: 3));

          //Automatically skips backup
          final skipBackupButton = find.byKey(
            const ValueKey("skipBackupButton"),
          );
          await tester.tap(skipBackupButton);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          await binding.traceAction(() async {
            //scroll gallery
            final scrollablePositionedList = find.byType(
              ScrollablePositionedList,
            );
            await tester.fling(
              scrollablePositionedList,
              const Offset(0, -5000),
              4500,
            );
            await tester.pumpAndSettle();
            await tester.fling(
              scrollablePositionedList,
              const Offset(0, 5000),
              4500,
            );

            await tester.fling(
              scrollablePositionedList,
              const Offset(0, -7000),
              4500,
            );
            await tester.pumpAndSettle();
            await tester.fling(
              scrollablePositionedList,
              const Offset(0, 7000),
              4500,
            );

            await tester.fling(
              scrollablePositionedList,
              const Offset(0, -9000),
              4500,
            );
            await tester.pumpAndSettle();
            await tester.fling(
              scrollablePositionedList,
              const Offset(0, 9000),
              4500,
            );
            await tester.pumpAndSettle();
          }, reportKey: 'home_gallery_scrolling_summary');
        },
        (error, stack) {
          Logger("gallery_scroll_test").info(error, stack);
        },
      );
    });
  });
}

Future<void> dismissUpdateAppDialog(WidgetTester tester) async {
  await tester.tapAt(const Offset(0, 0));
  await tester.pumpAndSettle();
}
