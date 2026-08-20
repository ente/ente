import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:ente_strings/ente_strings.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";

void main() {
  group("showActionSheet", () {
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
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onOpen,
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
