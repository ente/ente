import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/data/local_backup_settings_page.dart';
import 'package:ente_auth/ui/settings/language_picker.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'language picker normalizes a device locale to its supported row',
    (tester) async {
      await _pumpPage(
        tester,
        LanguageSelectorPage(
          const [Locale('en'), Locale('fr')],
          (_) {},
          const Locale('en', 'US'),
        ),
      );

      final englishRow = find.widgetWithText(MenuComponent, 'English (en)');
      final radio = tester.widget<RadioComponent>(
        find.descendant(of: englishRow, matching: find.byType(RadioComponent)),
      );

      expect(radio.selected, isTrue);
      expect(find.byType(MenuGroupComponent), findsOneWidget);
    },
  );

  testWidgets('local backup uses component settings controls', (tester) async {
    SharedPreferences.setMockInitialValues({
      'isAutoBackupEnabled': true,
      'autoBackupPath': '/tmp/EnteAuthBackups',
    });

    await _pumpPage(tester, const LocalBackupSettingsPage());
    await tester.pumpAndSettle();

    expect(find.text('Automatic backups'), findsOneWidget);
    expect(find.byType(ToggleSwitchComponent), findsOneWidget);
    expect(find.byType(MenuGroupComponent), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == 'auth_local_backup_settings',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == 'auth_local_backup_toggle',
      ),
      findsOneWidget,
    );
    for (final identifier in [
      'auth_local_backup_password',
      'auth_local_backup_folder',
      'auth_local_backup_create_now',
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.identifier == identifier,
        ),
        findsOneWidget,
      );
    }
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: page,
    ),
  );
}
