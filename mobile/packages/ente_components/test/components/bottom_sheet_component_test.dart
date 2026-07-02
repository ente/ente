import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BottomSheetComponent renders title and close action', (
    tester,
  ) async {
    var closeCount = 0;

    await tester.pumpWidget(
      _wrap(
        BottomSheetComponent(
          title: 'Title',
          content: const Text('Body copy'),
          onClose: () => closeCount += 1,
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Body copy'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('BottomSheetComponent renders custom content and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const BottomSheetComponent(
          title: 'Title',
          content: Text('Body copy'),
          actions: [
            ButtonComponent(label: 'Primary'),
            ButtonComponent(
              label: 'Secondary',
              variant: ButtonComponentVariant.secondary,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Body copy'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
  });

  testWidgets('BottomSheetComponent respects explicit action spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const BottomSheetComponent(
          title: 'Title',
          message: 'Centered message',
          actionsTopSpacing: 7,
          actions: [
            ButtonComponent(key: ValueKey('action-button'), label: 'Action'),
          ],
        ),
      ),
    );

    final messageBottom = tester
        .getBottomLeft(find.text('Centered message'))
        .dy;
    final actionTop = tester
        .getTopLeft(find.byKey(const ValueKey('action-button')))
        .dy;

    expect(actionTop - messageBottom, 7);
  });

  testWidgets('BottomSheetComponent dismisses from close button by default', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      (context) => showBottomSheetComponent<void>(
        context: context,
        builder: (_) => const BottomSheetComponent(
          title: 'Default close',
          content: Text('Sheet body'),
        ),
      ),
    );

    await _openLauncher(tester);

    expect(find.text('Default close'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Default close'), findsNothing);
  });

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

  testWidgets('showErrorBottomSheetComponent presents error content', (
    tester,
  ) async {
    var closeCount = 0;

    await _pumpLauncher(
      tester,
      (context) => showErrorBottomSheetComponent<void>(
        context: context,
        message: 'Something went wrong.',
        onClose: () => closeCount += 1,
        actionLabel: 'Contact support',
      ),
      label: 'Show error',
    );

    await _openLauncher(tester, label: 'Show error');

    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(closeCount, 1);
    expect(find.text('Error'), findsNothing);
  });

  testWidgets('showErrorBottomSheetComponent can hide close button', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      (context) => showErrorBottomSheetComponent<void>(
        context: context,
        message: 'Something went wrong.',
        showCloseButton: false,
      ),
      label: 'Show error',
    );

    await _openLauncher(tester, label: 'Show error');

    expect(find.text('Error'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
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

  testWidgets('BottomSheetComponent passes initial scrollable size', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const BottomSheetComponent(
          content: SizedBox(key: ValueKey('scrollable-content')),
          isScrollable: true,
          initialChildSize: 0.7,
        ),
      ),
    );
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.initialChildSize, 0.7);
  });

  testWidgets('BottomSheetComponent keeps default layout non-scrollable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const BottomSheetComponent(
          content: SizedBox(key: ValueKey('plain-content')),
          initialChildSize: 0.7,
        ),
      ),
    );
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byType(Padding), findsWidgets);
    expect(find.byKey(const ValueKey('plain-content')), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ComponentTheme.lightTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 375, child: child),
      ),
    ),
  );
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
