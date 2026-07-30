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

    await firstDialog.hide();
    await tester.pumpAndSettle();
  });
}
