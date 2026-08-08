import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/common/progress_dialog.dart";

void main() {
  testWidgets("ignores updates from a dialog instance that was not shown", (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final firstDialog = ProgressDialog(context);
    firstDialog.style(
      message: "Downloading (0/2)",
      progressWidget: const SizedBox.shrink(),
    );

    final firstShow = firstDialog.show();
    await tester.pump();

    final secondDialog = ProgressDialog(context);
    final secondShown = await secondDialog.show();

    expect(secondShown, isFalse);
    expect(
      () => secondDialog.update(message: "Downloading (1/2)"),
      returnsNormally,
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(await firstShow, isTrue);

    final hideFuture = firstDialog.hide();
    await tester.pumpAndSettle();
    expect(await hideFuture, isTrue);
  });

  testWidgets("waits for sequential dismissals before the page is popped", (
    tester,
  ) async {
    bool? routeResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                routeResult = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const _DeletionPage()),
                );
              },
              child: const Text("Open"),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text("Open"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Delete"));
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();

    expect(find.text("Delete"), findsNothing);
    expect(routeResult, isTrue);
  });

  testWidgets("does not pop the page when barrier dismissal races with hide", (
    tester,
  ) async {
    final work = Completer<void>();

    await _pumpActionPage(
      tester,
      onPressed: (context) async {
        final dialog = ProgressDialog(context);
        dialog.style(progressWidget: const SizedBox.shrink());
        await dialog.show();
        await work.future;
        await dialog.hide();
      },
    );

    await tester.tap(find.text("Run"));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    work.complete();
    await tester.pumpAndSettle();

    expect(find.text("Run"), findsOneWidget);
    expect(find.text("Open"), findsNothing);
  });

  testWidgets("an old dialog cannot clear an active dialog's state", (
    tester,
  ) async {
    final firstWork = Completer<void>();
    late ProgressDialog secondDialog;

    await _pumpActionPage(
      tester,
      onPressed: (context) async {
        final firstDialog = ProgressDialog(context);
        firstDialog.style(
          message: "First",
          progressWidget: const SizedBox.shrink(),
        );
        await firstDialog.show();
        await firstWork.future;
        await firstDialog.hide();
      },
      secondaryOnPressed: (context) async {
        secondDialog = ProgressDialog(context);
        secondDialog.style(
          message: "Second",
          progressWidget: const SizedBox.shrink(),
        );
        await secondDialog.show();
      },
    );

    await tester.tap(find.text("Run"));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Run second"));
    await tester.pumpAndSettle();
    expect(secondDialog.isShowing(), isTrue);
    expect(find.text("Second"), findsOneWidget);

    firstWork.complete();
    await tester.pumpAndSettle();
    expect(secondDialog.isShowing(), isTrue);

    secondDialog.update(message: "Second updated");
    await tester.pump();
    expect(find.text("Second updated"), findsOneWidget);

    final hideFuture = secondDialog.hide();
    await tester.pumpAndSettle();
    expect(await hideFuture, isTrue);
  });
}

Future<void> _pumpActionPage(
  WidgetTester tester, {
  required Future<void> Function(BuildContext) onPressed,
  Future<void> Function(BuildContext)? secondaryOnPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _ActionPage(
                  onPressed: onPressed,
                  secondaryOnPressed: secondaryOnPressed,
                ),
              ),
            ),
            child: const Text("Open"),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
}

class _ActionPage extends StatelessWidget {
  const _ActionPage({required this.onPressed, this.secondaryOnPressed});

  final Future<void> Function(BuildContext) onPressed;
  final Future<void> Function(BuildContext)? secondaryOnPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => onPressed(context),
            child: const Text("Run"),
          ),
          if (secondaryOnPressed != null)
            TextButton(
              onPressed: () => secondaryOnPressed!(context),
              child: const Text("Run second"),
            ),
        ],
      ),
    );
  }
}

class _DeletionPage extends StatelessWidget {
  const _DeletionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () async {
          for (final message in ["Deleting", "Loading", "Deleting again"]) {
            final dialog = ProgressDialog(context, isDismissible: false);
            dialog.style(
              message: message,
              progressWidget: const SizedBox.shrink(),
            );
            await dialog.show();
            await dialog.hide();
          }
          if (context.mounted) {
            Navigator.of(context).pop(true);
          }
        },
        child: const Text("Delete"),
      ),
    );
  }
}
