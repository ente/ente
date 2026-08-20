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
