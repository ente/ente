import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/data/import_page.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'import page uses a grouped source list with stable identifiers',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ImportCodePage(),
        ),
      );

      expect(find.text('Import codes'), findsOneWidget);
      expect(find.byType(MenuGroupComponent), findsOneWidget);
      expect(find.text('Plain text'), findsOneWidget);
      expect(find.text('Ente Encrypted export'), findsOneWidget);
      expect(find.text('OTP Auth'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'auth_import_plainText',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('plain text source opens an Ente instruction sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ImportCodePage(),
      ),
    );

    await tester.tap(find.text('Plain text'));
    await tester.pumpAndSettle();

    expect(find.text('Select file'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier ==
                'auth_import_instruction_plain_text',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Select file'), findsNothing);
  });
}
