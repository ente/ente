import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/ui/components/locker_progress_dialog.dart';

void main() {
  for (final dismissWithBack in [false, true]) {
    testWidgets(
      'allows sharing dialog dismissal by ${dismissWithBack ? 'back' : 'barrier'}',
      (tester) async {
        late LockerProgressDialog dialog;
        await tester.pumpWidget(
          MaterialApp(
            theme: ComponentTheme.lightTheme(app: ComponentApp.locker),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  dialog = await showLockerProgressDialog(
                    context,
                    'Sharing',
                    isDismissible: true,
                  );
                },
                child: const Text('share'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('share'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Sharing'), findsOneWidget);
        expect(find.byType(LoadingComponent), findsOneWidget);

        if (dismissWithBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tapAt(const Offset(5, 5));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Sharing'), findsNothing);
        expect(find.text('share'), findsOneWidget);

        final hidden = dialog.hide();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await hidden;
        expect(find.text('share'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keeps progress updates and dismissal', (tester) async {
    late LockerProgressDialog dialog;
    var shown = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.locker),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              dialog = await showLockerProgressDialog(
                context,
                'Uploaded 0 of 2 files',
              );
              shown = true;
            },
            child: const Text('upload'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('upload'));
    expect(shown, isFalse);
    await tester.pump();
    expect(shown, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    expect(shown, isTrue);
    await tester.pump(const Duration(milliseconds: 300));

    expect(dialog.didShow, isTrue);
    expect(dialog.isShowing(), isTrue);
    expect(find.text('Uploaded 0 of 2 files'), findsOneWidget);
    expect(find.byType(LoadingComponent), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(dialog.isShowing(), isTrue);

    dialog.update(message: 'Uploaded 1 of 2 files');
    await tester.pump();
    expect(find.text('Uploaded 1 of 2 files'), findsOneWidget);
    expect(find.text('Uploaded 0 of 2 files'), findsNothing);

    var hidden = false;
    final dismissed = dialog.hide().then((_) => hidden = true);
    expect(hidden, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await dismissed;
    expect(hidden, isTrue);
    expect(dialog.isShowing(), isFalse);
    expect(find.byType(Dialog), findsNothing);
  });
}
