import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:logging/logging.dart";
import "package:photos/main.dart" as app;

void main() {
  group("App init test", () {
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    testWidgets("App init test", semanticsEnabled: false, (tester) async {
      // https://github.com/flutter/flutter/issues/89749#issuecomment-1029965407
      tester.testTextInput.register();

      await runZonedGuarded(
        () async {
          bool skipLogin = false;

          ///Ignore exceptions thrown by the app for the test to pass
          WidgetsFlutterBinding.ensureInitialized();
          FlutterError.onError = (FlutterErrorDetails errorDetails) {
            FlutterError.dumpErrorToConsole(errorDetails);
          };

          await binding.traceAction(() async {
            app.main();

            await tester.pumpAndSettle(const Duration(seconds: 1));

            await dismissUpdateAppDialog(tester);

            final signInButton = find.byKey(const ValueKey("signInButton"));
            skipLogin = !tester.any(signInButton);

            if (!skipLogin) {
              await tester.tap(signInButton);
              await tester.pumpAndSettle();
              final emailInputField = find.byType(TextFormField);
              final logInButton = find.byKey(const ValueKey("logInButton"));
              //Fill email id here
              await tester.enterText(emailInputField, "*enter email here*");
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
              await tester.enterText(
                passwordInputField,
                "*enter password here*",
              );
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
            }
          }, reportKey: "app_init_summary");
        },
        (error, stack) {
          Logger("app_init_test").info(error, stack);
        },
      );
    });
  });
}

Future<void> dismissUpdateAppDialog(WidgetTester tester) async {
  await tester.tapAt(const Offset(0, 0));
  await tester.pumpAndSettle();
}

///Use this widget as floating action buttom in HomeWidget so that frames
///are built and rendered continuously so that timeline trace has continuous
///data. Change the duraiton in `_startTimer()` to control the duraiton of
///test on app init.

// class TempWidget extends StatefulWidget {
//   const TempWidget({super.key});

//   @override
//   TempWidgetState createState() => TempWidgetState();
// }

// class TempWidgetState extends State<TempWidget> {
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _startTimer();
//   }

//   void _startTimer() {
//     Future.delayed(const Duration(seconds: 20), () {
//       setState(() {
//         _isLoading = false;
//       });
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return _isLoading
//         ? const CircularProgressIndicator()
//         : const SizedBox.shrink();
//   }
// }
