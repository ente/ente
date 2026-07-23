import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/utils/dialog_util.dart";

void main() {
  group("ButtonWidget", () {
    testWidgets("alert button does not pop regular page routes", (
      tester,
    ) async {
      ButtonResult? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: darkThemeData,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<ButtonResult>(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const _AlertRoutePage(),
                      ),
                    );
                  },
                  child: const Text("Open route"),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text("Open route"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.text("Cancel"), findsOneWidget);
    });

    testWidgets("action sheet buttons return their selected action", (
      tester,
    ) async {
      ButtonResult? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: darkThemeData,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showChoiceActionSheet(
                      context,
                      title: "Clean Uncategorized",
                      body: "Remove duplicate album entries",
                      firstButtonLabel: "Confirm",
                    );
                  },
                  child: const Text("Open sheet"),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text("Open sheet"));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Confirm"));
      await tester.pumpAndSettle();

      expect(result?.action, ButtonAction.first);
      expect(find.text("Open sheet"), findsOneWidget);
    });
  });
}

class _AlertRoutePage extends StatelessWidget {
  const _AlertRoutePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          child: ButtonWidget(
            buttonType: ButtonType.secondary,
            labelText: "Cancel",
            isInAlert: true,
            buttonAction: ButtonAction.cancel,
          ),
        ),
      ),
    );
  }
}
