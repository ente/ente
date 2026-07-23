import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/dialog_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/components/text_input_widget.dart";
import "package:photos/utils/dialog_util.dart";

void main() {
  group("showDialogWidget", () {
    testWidgets("renders the compatibility sheet with ente components", (
      tester,
    ) async {
      await _pumpLauncher(
        tester,
        (context) => showDialogWidget(
          context: context,
          title: "Invite",
          body: "Share this invite with a friend.",
          icon: Icons.info_outline,
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Send invite",
              icon: Icons.share_outlined,
              isInAlert: true,
              buttonAction: ButtonAction.first,
            ),
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "Cancel",
              isInAlert: true,
              buttonAction: ButtonAction.cancel,
            ),
          ],
        ),
      );

      await _openLauncher(tester);

      expect(find.byType(BottomSheetComponent), findsOneWidget);
      _expectComponentScrim(tester);
      expect(find.byType(ButtonComponent), findsOneWidget);
      expect(find.byType(ButtonWidget), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text("Invite"), findsOneWidget);
      expect(find.text("Share this invite with a friend."), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byTooltip("Close"), findsOneWidget);
      expect(find.text("Cancel"), findsNothing);
      final button = tester.widget<ButtonComponent>(
        find.widgetWithText(ButtonComponent, "Send invite"),
      );
      expect(button.variant, ButtonComponentVariant.neutral);
      expect(button.leading, isNotNull);
    });

    testWidgets("returns the tapped button action", (tester) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showDialogWidget(
          context: context,
          title: "Confirm",
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Continue",
              isInAlert: true,
              buttonAction: ButtonAction.first,
            ),
          ],
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.text("Continue"));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.first);
      expect(result?.exception, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns the cancel action from the close button", (
      tester,
    ) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showDialogWidget(
          context: context,
          title: "Confirm",
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Continue",
              isInAlert: true,
              buttonAction: ButtonAction.first,
            ),
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "Cancel",
              isInAlert: true,
              buttonAction: ButtonAction.second,
            ),
          ],
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.byTooltip("Close"));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.second);
      expect(result?.exception, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns null when dismissed", (tester) async {
      ButtonResult? result;
      var completed = false;

      await _pumpLauncher(tester, (context) async {
        result = await showDialogWidget(
          context: context,
          title: "Dismissible",
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "Cancel",
              isInAlert: true,
              buttonAction: ButtonAction.cancel,
            ),
          ],
        );
        completed = true;
      });

      await _openLauncher(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(result, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

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

    testWidgets("returns an error result when the close callback throws", (
      tester,
    ) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showDialogWidget(
          context: context,
          title: "Failure",
          buttons: [
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "Cancel",
              isInAlert: true,
              buttonAction: ButtonAction.cancel,
              onTap: () async {
                throw StateError("boom");
              },
            ),
          ],
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.byTooltip("Close"));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.error);
      expect(result?.exception, isA<Exception>());
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns an error result when a button callback throws", (
      tester,
    ) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showDialogWidget(
          context: context,
          title: "Failure",
          buttons: [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Fail",
              isInAlert: true,
              buttonAction: ButtonAction.first,
              onTap: () async {
                throw StateError("boom");
              },
            ),
          ],
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.text("Fail"));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.error);
      expect(result?.exception, isA<Exception>());
      expect(find.byType(BottomSheetComponent), findsNothing);
    });
  });

  testWidgets("showChoiceDialog uses the migrated dialog sheet", (
    tester,
  ) async {
    ButtonResult? result;

    await _pumpLauncher(tester, (context) async {
      result = await showChoiceDialog(
        context,
        title: "Remove item?",
        body: "This can be restored later.",
        firstButtonLabel: "Remove",
        secondButtonLabel: "Keep",
        isCritical: true,
      );
    });

    await _openLauncher(tester);

    expect(find.byType(BottomSheetComponent), findsOneWidget);
    expect(find.byTooltip("Close"), findsNothing);
    final removeButton = tester.widget<ButtonComponent>(
      find.widgetWithText(ButtonComponent, "Remove"),
    );
    expect(removeButton.variant, ButtonComponentVariant.critical);

    await tester.tap(find.text("Keep"));
    await tester.pumpAndSettle();

    expect(result?.action, ButtonAction.cancel);
    expect(find.byType(BottomSheetComponent), findsNothing);
  });

  group("showTextInputDialog", () {
    testWidgets("renders the migrated text input sheet", (tester) async {
      await _pumpLauncher(
        tester,
        (context) => showTextInputDialog(
          context,
          title: "Rename file",
          body: "Choose a short name.",
          submitButtonLabel: "Rename",
          icon: Icons.edit_outlined,
          label: "Name",
          hintText: "Enter file name",
          prefixIcon: Icons.drive_file_rename_outline,
          initialValue: "IMG_001",
          message: ".JPG",
          alignMessage: Alignment.centerRight,
          onSubmit: (_) async {},
        ),
      );

      await _openLauncher(tester);

      expect(find.byType(BottomSheetComponent), findsOneWidget);
      _expectComponentScrim(tester);
      expect(find.byType(TextInputComponent), findsOneWidget);
      expect(find.byType(ButtonComponent), findsOneWidget);
      expect(find.byType(TextInputWidget), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text("Rename file"), findsOneWidget);
      expect(find.text("Choose a short name."), findsOneWidget);
      expect(find.text("Name"), findsOneWidget);
      expect(find.text(".JPG"), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.drive_file_rename_outline), findsOneWidget);
      expect(find.byTooltip("Close"), findsOneWidget);
      expect(find.text("Cancel"), findsNothing);

      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller?.text, "IMG_001");
    });

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

    testWidgets("submits from the keyboard action", (tester) async {
      dynamic result;
      var submitted = "";

      await _pumpLauncher(tester, (context) async {
        result = await showTextInputDialog(
          context,
          title: "New album",
          submitButtonLabel: "Create",
          onSubmit: (value) async {
            submitted = value;
          },
        );
      });

      await _openLauncher(tester);
      await tester.enterText(find.byType(TextField), "Keyboard album");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submitted, "Keyboard album");
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

    testWidgets("preserves password mode and input formatters", (tester) async {
      await _pumpLauncher(
        tester,
        (context) => showTextInputDialog(
          context,
          title: "Pair with TV",
          submitButtonLabel: "Pair",
          initialValue: "a1b2",
          isPasswordInput: true,
          textInputFormatter: [FilteringTextInputFormatter.digitsOnly],
          onSubmit: (_) async {},
        ),
      );

      await _openLauncher(tester);

      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.obscureText, isTrue);
      expect(input.controller?.text, "12");
      expect(
        find.byKey(const ValueKey("text-field-password-toggle")),
        findsOneWidget,
      );
    });

    testWidgets("showOnlyLoadingState suppresses button success state", (
      tester,
    ) async {
      await _pumpLauncher(
        tester,
        (context) => showTextInputDialog(
          context,
          title: "New album",
          submitButtonLabel: "Create",
          initialValue: "Album",
          showOnlyLoadingState: true,
          onSubmit: (_) async {},
        ),
      );

      await _openLauncher(tester);

      final button = tester.widget<ButtonComponent>(
        find.widgetWithText(ButtonComponent, "Create"),
      );
      expect(button.shouldShowSuccessState, isFalse);
    });
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<dynamic> Function(BuildContext context) onOpen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

void _expectComponentScrim(WidgetTester tester) {
  final barrierColors = tester
      .widgetList<ModalBarrier>(find.byType(ModalBarrier))
      .map((barrier) => barrier.color);
  expect(barrierColors, contains(const Color.fromRGBO(0, 0, 0, 0.55)));
}
