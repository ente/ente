import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpPopupMenu(
  WidgetTester tester,
  Widget child, {
  double width = 420,
  double height = 360,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'EntePopupMenuButton renders Figma-sized rows and selects values',
    (tester) async {
      String? selected;

      await pumpPopupMenu(
        tester,
        Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: EntePopupMenuButton<String>(
            child: const SizedBox.square(
              key: ValueKey('popup-anchor'),
              dimension: 48,
              child: Icon(Icons.more_vert),
            ),
            optionsBuilder: () => const [
              EntePopupMenuOption(
                value: 'name',
                label: 'Name',
                secondaryLabel: 'A-Z',
                secondaryTrailingWidget: Icon(Icons.north, size: 12),
                activeTrailingWidget: Icon(Icons.arrow_upward),
                isActive: true,
              ),
              EntePopupMenuOption(value: 'created', label: 'Created'),
              EntePopupMenuOption(
                value: 'updated',
                label: 'Updated',
                showDivider: false,
              ),
            ],
            onSelected: (value) => selected = value,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('popup-anchor')));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('A-Z'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.byIcon(Icons.north), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      final firstItem = tester.widget<Container>(
        find.byKey(const ValueKey('ente-popup-menu-item-0')),
      );
      expect(firstItem.constraints, const BoxConstraints.tightFor(height: 52));
      expect(firstItem.padding, const EdgeInsets.symmetric(horizontal: 16));
      final firstDecoration = firstItem.decoration! as BoxDecoration;
      expect(
        firstDecoration.border?.bottom.color,
        ColorTokens.light.strokeFaint,
      );

      final lastItem = tester.widget<Container>(
        find.byKey(const ValueKey('ente-popup-menu-item-2')),
      );
      final lastDecoration = lastItem.decoration! as BoxDecoration;
      expect(lastDecoration.border, isNull);

      final nameStyle = tester.widget<Text>(find.text('Name')).style!;
      expect(nameStyle.fontSize, TextStyles.mini.fontSize);
      expect(nameStyle.height, TextStyles.mini.height);
      expect(nameStyle.fontWeight, TextStyles.mini.fontWeight);
      expect(nameStyle.color, ColorTokens.light.textBase);
      expect(
        tester.widget<Text>(find.text('A-Z')).style?.color,
        ColorTokens.light.textLight,
      );

      await tester.tap(find.text('Created'));
      await tester.pumpAndSettle();

      expect(selected, 'created');
    },
  );

  testWidgets('EntePopupMenuButton does not open for empty options', (
    tester,
  ) async {
    await pumpPopupMenu(
      tester,
      EntePopupMenuButton<String>(
        child: const SizedBox.square(
          key: ValueKey('empty-popup-anchor'),
          dimension: 48,
          child: Icon(Icons.more_vert),
        ),
        optionsBuilder: () => const [],
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('empty-popup-anchor')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ente-popup-menu-item-0')), findsNothing);
  });

  testWidgets(
    'EntePopupMenuButton ignores async options after anchor unmounts',
    (tester) async {
      final optionsCompleter = Completer<List<EntePopupMenuOption<String>>>();
      var selected = false;

      await pumpPopupMenu(
        tester,
        EntePopupMenuButton<String>(
          child: const SizedBox.square(
            key: ValueKey('async-popup-anchor'),
            dimension: 48,
            child: Icon(Icons.more_vert),
          ),
          optionsBuilder: () => optionsCompleter.future,
          onSelected: (_) => selected = true,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('async-popup-anchor')));
      await tester.pump();

      await pumpPopupMenu(tester, const SizedBox.shrink());
      optionsCompleter.complete(const [
        EntePopupMenuOption(value: 'late', label: 'Late option'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Late option'), findsNothing);
      expect(selected, isFalse);
    },
  );
}
