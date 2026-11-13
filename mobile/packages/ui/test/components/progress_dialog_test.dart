import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('show waits for a visible frame before completing', (
    tester,
  ) async {
    final context = await _pumpPage(tester);
    final dialog = _dialog(context, 'Pending');
    var completed = false;
    final shown = dialog.show().whenComplete(() {
      completed = true;
    });

    await tester.idle();
    expect(completed, isFalse);
    await tester.pump();
    expect(completed, isFalse);
    expect(_dialogOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(_dialogOpacity(tester), greaterThan(0));
    expect(await shown, isTrue);

    final hidden = dialog.hide();
    await tester.pumpAndSettle();
    expect(await hidden, isTrue);
  });

  testWidgets('hide before the first frame removes the dialog', (tester) async {
    final context = await _pumpPage(tester);
    final dialog = _dialog(context, 'Pending');
    final shown = dialog.show();
    final hidden = dialog.hide();
    await tester.pumpAndSettle();

    expect(await shown, isTrue);
    expect(await hidden, isTrue);
    expect(dialog.isShowing(), isFalse);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Page'), findsOneWidget);
  });

  testWidgets('overlapping dialogs own their content and routes', (
    tester,
  ) async {
    final context = await _pumpPage(tester);
    final first = _dialog(context, 'First');
    final second = _dialog(context, 'Second');
    await _show(tester, first);
    await _show(tester, second);

    first.update(message: 'First updated');
    await tester.pump();
    expect(find.text('First updated'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    final hidden = first.hide();
    await tester.pumpAndSettle();
    expect(await hidden, isTrue);
    expect(first.isShowing(), isFalse);
    expect(second.isShowing(), isTrue);
    expect(find.text('First updated'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    final secondHidden = second.hide();
    await tester.pumpAndSettle();
    expect(await secondHidden, isTrue);
    expect(find.text('Page'), findsOneWidget);
  });

  testWidgets('barrier dismissal followed by hide does not pop the page', (
    tester,
  ) async {
    final context = await _pumpPage(tester);
    final dialog = _dialog(context, 'Pending');
    await _show(tester, dialog);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    final hidden = dialog.hide();
    await tester.pumpAndSettle();

    expect(await hidden, isFalse);
    expect(dialog.isShowing(), isFalse);
    expect(find.text('Page'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('hide leaves a newer page on the navigator', (tester) async {
    final context = await _pumpPage(tester);
    final dialog = _dialog(context, 'Pending');
    await _show(tester, dialog);
    final navigator = Navigator.of(context);
    final page = navigator.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('New page'))),
    );
    await tester.pumpAndSettle();

    final hidden = dialog.hide();
    await tester.pumpAndSettle();
    expect(await hidden, isTrue);
    expect(find.text('New page'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    await page;
    expect(find.text('Page'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}

double _dialogOpacity(WidgetTester tester) {
  final transition = tester.widget<FadeTransition>(
    find
        .ancestor(
          of: find.text('Pending'),
          matching: find.byType(FadeTransition),
        )
        .last,
  );
  return transition.opacity.value;
}

ProgressDialog _dialog(BuildContext context, String message) {
  return ProgressDialog(context)
    ..style(message: message, progressWidget: const SizedBox.shrink());
}

Future<void> _show(WidgetTester tester, ProgressDialog dialog) async {
  final shown = dialog.show();
  await tester.pumpAndSettle();
  expect(await shown, isTrue);
}

Future<BuildContext> _pumpPage(WidgetTester tester) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Home')),
    ),
  );
  late BuildContext context;
  // Keep a page below the dialog so an accidental pop is observable.
  // ignore: unawaited_futures
  navigator.currentState!.push<void>(
    MaterialPageRoute(
      builder: (value) {
        context = value;
        return const Scaffold(body: Text('Page'));
      },
    ),
  );
  await tester.pumpAndSettle();
  return context;
}
