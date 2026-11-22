import 'package:ente_components/ente_components.dart';
import 'package:ente_ui/components/language_selector_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('changing language updates the accessible selected row', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Locale? chosenLocale;

    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.locker),
        home: Scaffold(
          body: LanguageSelectorList(
            const [Locale('en'), Locale('id')],
            (locale) => chosenLocale = locale,
            const Locale('id'),
          ),
        ),
      ),
    );

    final indonesian = find.semantics.byLabel(RegExp(r'^Bahasa Indonesia\b'));
    final english = find.semantics.byLabel(RegExp(r'^English\b'));
    expect(
      indonesian.evaluate().single,
      isSemantics(hasSelectedState: true, isSelected: true, hasTapAction: true),
    );
    expect(english.evaluate().single, isSemantics(isSelected: false));

    tester.semantics.tap(english);
    await tester.pumpAndSettle();

    expect(chosenLocale, const Locale('en'));
    expect(
      english.evaluate().single,
      isSemantics(hasSelectedState: true, isSelected: true, hasTapAction: true),
    );
    expect(indonesian.evaluate().single, isSemantics(isSelected: false));
    semantics.dispose();
  });
}
