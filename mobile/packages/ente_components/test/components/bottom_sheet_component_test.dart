import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BottomSheetComponent returns closeResult from close button', (
    tester,
  ) async {
    String? result;

    await _pumpLauncher(tester, (context) async {
      result = await showBottomSheetComponent<String>(
        context: context,
        builder: (_) => const BottomSheetComponent(
          title: 'Close result',
          content: Text('Sheet body'),
          closeResult: 'cancelled',
        ),
      );
    });

    await _openLauncher(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(result, 'cancelled');
    expect(find.text('Close result'), findsNothing);
  });

  testWidgets(
    'showBottomSheetComponent blocks system back when not dismissible',
    (tester) async {
      await _pumpLauncher(
        tester,
        (context) => showBottomSheetComponent<void>(
          context: context,
          isDismissible: false,
          builder: (_) => const BottomSheetComponent(
            title: 'Locked sheet',
            content: Text('Sheet body'),
          ),
        ),
      );

      await _openLauncher(tester);

      expect(find.text('Locked sheet'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Locked sheet'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Locked sheet'), findsNothing);
    },
  );

  testWidgets('BottomSheetComponent does not pop a newer route after onClose', (
    tester,
  ) async {
    final closeCompleter = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        routes: {
          '/': (context) {
            return Scaffold(
              body: ButtonComponent(
                label: 'Show sheet',
                onTap: () {
                  return showBottomSheetComponent<void>(
                    context: context,
                    builder: (_) => BottomSheetComponent(
                      title: 'Async close',
                      content: const Text('Sheet body'),
                      onClose: () async {
                        unawaited(
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const Scaffold(body: Text('New route')),
                            ),
                          ),
                        );
                        await closeCompleter.future;
                      },
                    ),
                  );
                },
              ),
            );
          },
        },
      ),
    );

    await tester.tap(find.text('Show sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('New route'), findsOneWidget);

    closeCompleter.complete();
    await tester.pump();

    expect(find.text('New route'), findsOneWidget);
  });

  testWidgets('BottomSheetComponent applies keyboard inset padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(),
        home: const MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 120)),
          child: Material(
            child: BottomSheetComponent(
              title: 'Keyboard aware',
              content: Text('Input content'),
              isKeyboardAware: true,
            ),
          ),
        ),
      ),
    );

    final animatedPadding = tester.widget<AnimatedPadding>(
      find.byType(AnimatedPadding),
    );
    expect(animatedPadding.padding, const EdgeInsets.only(bottom: 120));
  });
}

Future<void> _pumpLauncher<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) onTap, {
  String label = 'Show sheet',
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: ButtonComponent(
              label: label,
              onTap: () async {
                await onTap(context);
              },
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openLauncher(
  WidgetTester tester, {
  String label = 'Show sheet',
}) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
