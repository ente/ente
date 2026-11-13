import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/dialog_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/utils/dialog_util.dart";

void main() {
  group("showDialogWidget", () {
    testWidgets("honors non-dismissible sheets", (tester) async {
      await _pumpLauncher(
        tester,
        (context) => showDialogWidget(
          context: context,
          title: "Required",
          isDismissible: false,
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "OK",
              isInAlert: true,
              buttonAction: ButtonAction.first,
            ),
          ],
        ),
      );

      await _openLauncher(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsOneWidget);

      await tester.tap(find.text("OK"));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("shows the download decryption failure support action", (
      tester,
    ) async {
      await _pumpLauncher(
        tester,
        (context) => showDownloadDecryptionFailedDialog(context: context),
      );

      await _openLauncher(tester);

      expect(find.text("Download failed"), findsOneWidget);
      expect(
        find.text(
          "This item could not be downloaded. Please reach out to us so we can help.",
        ),
        findsOneWidget,
      );
      expect(find.text("Contact us"), findsOneWidget);
      expect(find.byType(BottomSheetComponent), findsOneWidget);

      await tester.tap(find.text("Contact us"));
      await tester.pumpAndSettle();

      expect(find.text("Report a bug"), findsWidgets);
      expect(find.text("View logs"), findsOneWidget);
      expect(find.text("Export logs"), findsOneWidget);
    });
  });

  group("showTextInputDialog", () {
    testWidgets("submits entered text and closes with a null result", (
      tester,
    ) async {
      dynamic result;
      var submitted = "";

      await _pumpLauncher(tester, (context) async {
        result = await showTextInputDialog(
          context,
          title: "New album",
          submitButtonLabel: "Create",
          hintText: "Enter album name",
          onSubmit: (value) async {
            submitted = value;
          },
        );
      });

      await _openLauncher(tester);

      var submitButton = tester.widget<ButtonComponent>(
        find.widgetWithText(ButtonComponent, "Create"),
      );
      expect(submitButton.isDisabled, isTrue);

      await tester.enterText(find.byType(TextField), "Road trip");
      await tester.pump();

      submitButton = tester.widget<ButtonComponent>(
        find.widgetWithText(ButtonComponent, "Create"),
      );
      expect(submitButton.isDisabled, isFalse);

      await tester.tap(find.text("Create"));
      await tester.pumpAndSettle();

      expect(submitted, "Road trip");
      expect(result, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns a ButtonResult when cancelled", (tester) async {
      dynamic result;

      await _pumpLauncher(tester, (context) async {
        result = await showTextInputDialog(
          context,
          title: "Rename album",
          submitButtonLabel: "Rename",
          initialValue: "Archive",
          onSubmit: (_) async {},
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.byTooltip("Close"));
      await tester.pumpAndSettle();

      expect(result, isA<ButtonResult>());
      expect((result as ButtonResult).action, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns an exception when submit fails", (tester) async {
      dynamic result;

      await _pumpLauncher(tester, (context) async {
        result = await showTextInputDialog(
          context,
          title: "Rename album",
          submitButtonLabel: "Rename",
          initialValue: "Archive",
          onSubmit: (_) async {
            throw StateError("boom");
          },
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.text("Rename"));
      await tester.pumpAndSettle();

      expect(result, isA<Exception>());
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("keeps incorrect password errors in the sheet", (tester) async {
      await _pumpLauncher(
        tester,
        (context) => showTextInputDialog(
          context,
          title: "Enter password",
          submitButtonLabel: "Unlock",
          initialValue: "bad-password",
          isPasswordInput: true,
          popnavAfterSubmission: false,
          onSubmit: (_) async {
            throw Exception("Incorrect password");
          },
        ),
      );

      await _openLauncher(tester);
      await tester.tap(find.text("Unlock"));
      await tester.pump();

      expect(find.byType(BottomSheetComponent), findsOneWidget);
      final input = tester.widget<TextInputComponent>(
        find.byType(TextInputComponent),
      );
      expect(input.messageType, TextInputComponentMessageType.error);
    });

    testWidgets(
      "allows manual navigation when popnavAfterSubmission is false",
      (tester) async {
        dynamic result;

        await _pumpLauncher(tester, (context) async {
          result = await showTextInputDialog(
            context,
            title: "Collect photos",
            submitButtonLabel: "Create",
            initialValue: "May 25",
            popnavAfterSubmission: false,
            onSubmit: (value) async {
              Navigator.of(context).pop("created:$value");
            },
          );
        });

        await _openLauncher(tester);
        await tester.tap(find.text("Create"));
        await tester.pumpAndSettle();

        expect(result, "created:May 25");
        expect(find.byType(BottomSheetComponent), findsNothing);
      },
    );
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<dynamic> Function(BuildContext context) onOpen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async => onOpen(context),
              child: const Text("Open dialog"),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.text("Open dialog"));
  await tester.pumpAndSettle();
}
