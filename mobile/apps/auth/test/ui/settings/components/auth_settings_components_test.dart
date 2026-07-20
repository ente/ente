import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

void main() {
  testWidgets('settings item exposes its identifier and handles taps', (
    tester,
  ) async {
    var tapped = false;

    await _pump(
      tester,
      AuthSettingsItem(
        title: 'Security',
        icon: HugeIcons.strokeRoundedSquareLock02,
        semanticsIdentifier: 'auth_settings_security',
        onTap: () => tapped = true,
      ),
    );

    expect(find.text('Security'), findsOneWidget);
    expect(find.byType(HugeIcon), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_outlined), findsOneWidget);

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == 'auth_settings_security',
      ),
    );
    expect(semantics.properties.identifier, 'auth_settings_security');

    await tester.tap(find.text('Security'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('settings item supports destructive and non-navigation rows', (
    tester,
  ) async {
    await _pump(
      tester,
      const AuthSettingsItem(
        title: 'Delete account',
        isDestructive: true,
        showChevron: false,
        trailing: Switch(value: true, onChanged: null),
      ),
    );

    final title = tester.widget<Text>(find.text('Delete account'));
    expect(title.style?.color, ColorTokens.light.warning);
    expect(find.byIcon(Icons.chevron_right_outlined), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('settings scaffold uses the component surface and renders body', (
    tester,
  ) async {
    await _pump(
      tester,
      const AuthSettingsPageScaffold(
        title: 'Data',
        children: [Text('Import codes')],
      ),
    );

    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Import codes'), findsOneWidget);
    expect(find.byType(AppBarComponent), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ColorTokens.light.backgroundBase);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
      home: child,
    ),
  );
}
