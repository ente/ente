import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/profile_service.dart';
import 'package:ente_auth/ui/settings/account_settings_page.dart';
import 'package:ente_auth/ui/settings/profiles_settings_page.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      "profilesV1": [
        '{"scope":"","kind":"online","userID":1,"email":"first@example.org"}',
      ],
      "profilesActiveScope": "",
      // Reconciliation drops profiles whose account data is missing, so each
      // seeded profile needs its (scoped) token to survive init.
      "token": "a-token",
    });
    await ProfileService.instance.init();
  });

  testWidgets('the account page opens the switcher', (tester) async {
    await _pumpAccountPage(tester);

    await tester.tap(find.text('Switch account'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilesSettingsPage), findsOneWidget);
  });

  testWidgets('the switcher row keeps working after going back', (
    tester,
  ) async {
    await _pumpAccountPage(tester);

    // The original symptom was intermittency, so a single successful tap
    // proves nothing.
    for (var attempt = 0; attempt < 5; attempt++) {
      await tester.tap(find.text('Switch account'));
      await tester.pumpAndSettle();
      expect(
        find.byType(ProfilesSettingsPage),
        findsOneWidget,
        reason: 'row did not open the switcher on attempt ${attempt + 1}',
      );

      // Popped directly: the settings scaffold uses a custom back button, so
      // tester.pageBack() cannot find one.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ProfilesSettingsPage), findsNothing);
    }
  });

  testWidgets('an offline vault can still reach the switcher', (tester) async {
    // Regression: with the account actions hidden for a vault that is not
    // signed in, the switcher must still be there — it is the only way back
    // off an offline vault.
    await _pumpAccountPage(tester, hasAccount: false);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.switchAccount), findsOneWidget);
    expect(find.text(l10n.changePassword), findsNothing);
    expect(find.text(l10n.recoveryKey), findsNothing);
    expect(find.text(l10n.deleteAccount), findsNothing);

    await tester.tap(find.text(l10n.switchAccount));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilesSettingsPage), findsOneWidget);
  });

  testWidgets('an offline vault can be removed from the account page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      "profilesV1": ['{"scope":"","kind":"offline"}'],
      "profilesActiveScope": "",
      "has_opted_for_offline_mode": true,
    });
    await ProfileService.instance.init();

    await _pumpAccountPage(tester, hasAccount: false);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.removeVault), findsOneWidget);
  });

  testWidgets('an online account has no remove vault row', (tester) async {
    // Logging out is what removes an online account; two ways to drop the
    // same profile would be two ways to get the teardown wrong.
    await _pumpAccountPage(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.removeVault), findsNothing);
    expect(find.text(l10n.deleteAccount), findsOneWidget);
  });

  testWidgets('the add row is disabled once the profile cap is reached', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      "profilesV1": List.generate(
        ProfileService.maxProfiles,
        (i) =>
            '{"scope":"acct_$i.","kind":"online","userID":$i,'
            '"email":"user$i@example.org"}',
      ),
      "profilesActiveScope": "acct_0.",
      for (var i = 0; i < ProfileService.maxProfiles; i++)
        "acct_$i.token": "token-$i",
    });
    await ProfileService.instance.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProfilesSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.addAccount), findsOneWidget);
    expect(
      find.text(l10n.maxAccountsReached(ProfileService.maxProfiles)),
      findsOneWidget,
    );

    // Disabled rather than merely unstyled: tapping must not start an add.
    final row = tester.widget<MenuComponent>(
      find.widgetWithText(MenuComponent, l10n.addAccount),
    );
    expect(row.onTap, isNull);
  });

  testWidgets('the switcher row sits above the account actions', (
    tester,
  ) async {
    await _pumpAccountPage(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final switcher = tester.getTopLeft(find.text(l10n.switchAccount));
    final changeEmail = tester.getTopLeft(find.text(l10n.changeEmail));

    expect(switcher.dy, lessThan(changeEmail.dy));
  });
}

Future<void> _pumpAccountPage(WidgetTester tester, {bool hasAccount = true}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AccountSettingsPage(hasAccount: hasAccount),
    ),
  );
}
