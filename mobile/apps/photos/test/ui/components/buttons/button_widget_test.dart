import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:ente_strings/ente_strings.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";

void main() {
  group("ButtonWidget", () {
    testWidgets("alert button does not pop regular page routes", (
      tester,
    ) async {
      ButtonResult? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: darkThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
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
