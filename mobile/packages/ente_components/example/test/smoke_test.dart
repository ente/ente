import 'package:ente_components/ente_components.dart' show ComponentTheme;
import 'package:ente_components_catalog/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog app mounts', (tester) async {
    await tester.pumpWidget(const ComponentsCatalogApp());

    expect(find.text('Components'), findsOneWidget);
  });

  testWidgets('catalog header theme button toggles theme mode', (tester) async {
    await tester.pumpWidget(const ComponentsCatalogApp());

    expect(find.byTooltip('Theme: Light. Tap for Dark'), findsOneWidget);

    await tester.tap(find.byTooltip('Theme: Light. Tap for Dark'));
    await tester.pump();

    expect(find.byTooltip('Theme: Dark. Tap for Light'), findsOneWidget);
  });

  testWidgets('banner catalog shows all Figma states', (tester) async {
    await tester.pumpWidget(const ComponentsCatalogApp());

    await tester.tap(find.byKey(const ValueKey('catalog-section-Banner')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Failure!'), findsOneWidget);
    expect(find.text('Informative!'), findsOneWidget);
    expect(find.text('Success!'), findsOneWidget);
    expect(find.text('Warning!'), findsOneWidget);
    expect(find.text('Neutral!'), findsOneWidget);
    expect(find.text('Syncing backup'), findsOneWidget);
  });

  testWidgets('button transition preview surfaces loading and success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        home: const Scaffold(body: ButtonStateCyclePreview()),
      ),
    );

    final button = find.byKey(const ValueKey('button-cycle'));
    expect(button, findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 299));

    expect(find.byKey(const ValueKey('loading')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byKey(const ValueKey('loading')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(find.byKey(const ValueKey('success')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
  });
}
