import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

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
  testWidgets('open popup icons follow theme changes without changing sizes', (
    tester,
  ) async {
    var optionsBuildCount = 0;

    Widget app(ThemeMode themeMode) {
      return MaterialApp(
        theme: ComponentTheme.lightTheme().copyWith(
          iconTheme: const IconThemeData(size: 30),
        ),
        darkTheme: ComponentTheme.darkTheme().copyWith(
          iconTheme: const IconThemeData(size: 30),
        ),
        themeMode: themeMode,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: EntePopupMenuButton<String>(
              optionsBuilder: () {
                optionsBuildCount++;
                return const [
                  EntePopupMenuOption(
                    value: 'sort',
                    label: 'Sort',
                    secondaryLabel: 'Count',
                    leadingWidget: Icon(Icons.sort),
                    secondaryTrailingWidget: Icon(Icons.info_outline, size: 12),
                    isActive: true,
                    activeTrailingWidget: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowUp02,
                      size: 12,
                      strokeWidth: 3,
                    ),
                  ),
                  EntePopupMenuOption(
                    value: 'delete',
                    label: 'Delete',
                    leadingWidget: Icon(
                      Icons.delete,
                      color: Colors.red,
                      size: 20,
                    ),
                    trailingWidget: Icon(Icons.chevron_right),
                  ),
                ];
              },
              onSelected: (_) {},
            ),
          ),
        ),
      );
    }

    TextStyle iconStyle(IconData icon) {
      return tester
          .widget<RichText>(
            find.descendant(
              of: find.byIcon(icon),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!;
    }

    await tester.pumpWidget(app(ThemeMode.light));
    await tester.tap(find.byType(EntePopupMenuButton<String>));
    await tester.pumpAndSettle();

    for (final mode in [ThemeMode.light, ThemeMode.dark, ThemeMode.light]) {
      await tester.pumpWidget(app(mode));
      await tester.pumpAndSettle();
      final colors = mode == ThemeMode.dark
          ? ColorTokens.dark
          : ColorTokens.light;

      for (final icon in [
        Icons.sort,
        Icons.info_outline,
        Icons.chevron_right,
      ]) {
        expect(iconStyle(icon).color, colors.textLight);
      }
      expect(iconStyle(Icons.sort).fontSize, IconSizes.small);
      expect(iconStyle(Icons.info_outline).fontSize, 12);
      expect(iconStyle(Icons.chevron_right).fontSize, 30);
      expect(iconStyle(Icons.delete).color, Colors.red);
      expect(iconStyle(Icons.delete).fontSize, 20);

      final arrow = find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.byType(HugeIcon),
      );
      expect(IconTheme.of(tester.element(arrow)).color, colors.textLight);
      expect(tester.getSize(arrow), const Size.square(12));
      expect(optionsBuildCount, 1);
      expect(tester.takeException(), isNull);
    }
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

  testWidgets('EntePopupMenuButton does not select disabled options', (
    tester,
  ) async {
    String? selected;

    await pumpPopupMenu(
      tester,
      EntePopupMenuButton<String>(
        child: const SizedBox.square(
          key: ValueKey('disabled-popup-anchor'),
          dimension: 48,
          child: Icon(Icons.more_vert),
        ),
        optionsBuilder: () => const [
          EntePopupMenuOption(
            value: 'processing',
            label: 'Creating stream',
            enabled: false,
          ),
        ],
        onSelected: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('disabled-popup-anchor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Creating stream'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('Creating stream'), findsOneWidget);
  });
}
