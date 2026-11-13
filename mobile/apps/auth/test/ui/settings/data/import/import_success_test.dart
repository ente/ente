import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OK closes import success dialog without popping Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: _OnboardingShell(),
      ),
    );

    await tester.tap(find.text('Open home'));
    await tester.pumpAndSettle();

    expect(find.text('Auth home'), findsOneWidget);
    expect(find.text('Use without backups'), findsNothing);

    await tester.tap(find.text('Show import success'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Auth home'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    final okButton = find.ancestor(
      of: find.text('OK'),
      matching: find.byType(GestureDetector),
    );
    expect(okButton, findsOneWidget);

    await tester.tap(okButton);
    await tester.pumpAndSettle();

    expect(find.text('Auth home'), findsOneWidget);
    expect(find.text('Use without backups'), findsNothing);
    expect(find.text('OK'), findsNothing);
  });
}

class _OnboardingShell extends StatelessWidget {
  const _OnboardingShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Use without backups'),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const _HomeShell()),
                );
              },
              child: const Text('Open home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Auth home'),
            ElevatedButton(
              onPressed: () async {
                await importSuccessDialog(context, 2);
              },
              child: const Text('Show import success'),
            ),
          ],
        ),
      ),
    );
  }
}
