import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";

void main() {
  group("showActionSheet", () {
    testWidgets("renders the compatibility sheet with ente components", (
      tester,
    ) async {
      await _pumpLauncher(
        tester,
        (context) => showActionSheet(
          context: context,
          title: "Delete files?",
          body: "Files will be moved to trash.",
          bodyHighlight: "This applies to all albums.",
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Delete",
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
      final buttonComponents = tester
          .widgetList<ButtonComponent>(find.byType(ButtonComponent))
          .toList();
      expect(buttonComponents[0].variant, ButtonComponentVariant.neutral);
      expect(buttonComponents[0].size, ButtonComponentSize.large);
      expect(find.text("Delete files?"), findsOneWidget);
      expect(find.text("Files will be moved to trash."), findsOneWidget);
      expect(find.text("This applies to all albums."), findsOneWidget);
      expect(find.byTooltip("Close"), findsOneWidget);
      expect(find.text("Cancel"), findsNothing);
    });

    testWidgets("returns the tapped button action", (tester) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showActionSheet(
          context: context,
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Confirm",
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
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.text("Confirm"));
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
        result = await showActionSheet(
          context: context,
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Confirm",
              isInAlert: true,
              buttonAction: ButtonAction.first,
            ),
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "Cancel",
              isInAlert: true,
              buttonAction: ButtonAction.third,
            ),
          ],
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.byTooltip("Close"));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.third);
      expect(result?.exception, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns null when dismissed", (tester) async {
      ButtonResult? result;
      var completed = false;

      await _pumpLauncher(tester, (context) async {
        result = await showActionSheet(
          context: context,
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

    testWidgets("preserves the legacy success confirmation delay", (
      tester,
    ) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showActionSheet(
          context: context,
          buttons: [
            ButtonWidget(
              buttonType: ButtonType.neutral,
              labelText: "Save",
              isInAlert: true,
              buttonAction: ButtonAction.first,
              shouldShowSuccessConfirmation: true,
              onTap: () async {},
            ),
          ],
        );
      });

      await _openLauncher(tester);
      await tester.tap(find.text("Save"));
      await tester.pump();

      expect(result, isNull);
      expect(find.byType(BottomSheetComponent), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 999));

      expect(result, isNull);
      expect(find.byType(BottomSheetComponent), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.first);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("returns an error result when a button callback throws", (
      tester,
    ) async {
      ButtonResult? result;

      await _pumpLauncher(tester, (context) async {
        result = await showActionSheet(
          context: context,
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

    testWidgets("renders custom body widgets and icon-only sheets", (
      tester,
    ) async {
      await _pumpLauncher(
        tester,
        (context) => showActionSheet(
          context: context,
          title: "Done",
          bodyWidget: const Text("Custom body"),
          actionSheetType: ActionSheetType.iconOnly,
          isCheckIconGreen: true,
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.secondary,
              labelText: "Close",
              isInAlert: true,
              buttonAction: ButtonAction.cancel,
            ),
          ],
        ),
      );

      await _openLauncher(tester);

      expect(find.byType(BottomSheetComponent), findsOneWidget);
      expect(find.byIcon(Icons.check_outlined), findsOneWidget);
      expect(find.text("Done"), findsOneWidget);
      expect(find.text("Custom body"), findsNothing);
      expect(find.text("Close"), findsOneWidget);
      expect(find.byTooltip("Close"), findsNothing);
    });

    testWidgets("centers body text for illustrated sheets", (tester) async {
      await _pumpLauncher(
        tester,
        (context) => showActionSheet(
          context: context,
          title: "Warning",
          body: "Are you sure?",
          illustration: const SizedBox(width: 80, height: 80),
          buttons: const [
            ButtonWidget(
              buttonType: ButtonType.critical,
              labelText: "Yes",
              isInAlert: true,
              buttonAction: ButtonAction.first,
            ),
          ],
        ),
      );

      await _openLauncher(tester);

      final body = tester.widget<Text>(find.text("Are you sure?"));
      final bodyBottom = tester.getBottomLeft(find.text("Are you sure?")).dy;
      final buttonTop = tester.getTopLeft(find.byType(ButtonComponent)).dy;

      expect(body.textAlign, TextAlign.center);
      expect(buttonTop - bodyBottom, 24);
    });
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onOpen,
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
              child: const Text("Open sheet"),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.text("Open sheet"));
  await tester.pumpAndSettle();
}

void _expectComponentScrim(WidgetTester tester) {
  final barrierColors = tester
      .widgetList<ModalBarrier>(find.byType(ModalBarrier))
      .map((barrier) => barrier.color);
  expect(barrierColors, contains(const Color.fromRGBO(0, 0, 0, 0.55)));
}
