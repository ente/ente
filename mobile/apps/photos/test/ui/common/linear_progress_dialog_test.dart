import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/common/linear_progress_dialog.dart";
import "package:photos/utils/delete_file_util.dart";

void main() {
  testWidgets("waits for batch dialog dismissal before showing success", (
    tester,
  ) async {
    var deletionCompleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await routeToPage<bool>(
                  context,
                  _BatchDeletionPage(
                    onDeletionCompleted: () => deletionCompleted = true,
                  ),
                  forceCustomPageRoute: true,
                );
                if (result == true && context.mounted) {
                  await showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const Text("Success"),
                  );
                }
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
    await tester.pump();

    expect(find.byType(LinearProgressDialog), findsOneWidget);
    expect(deletionCompleted, isFalse);
    expect(find.text("Success"), findsNothing);

    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressDialog), findsNothing);
    expect(deletionCompleted, isTrue);
    expect(find.text("Delete"), findsNothing);
    expect(find.text("Success"), findsOneWidget);
  });
}

class _BatchDeletionPage extends StatelessWidget {
  final VoidCallback onDeletionCompleted;

  const _BatchDeletionPage({required this.onDeletionCompleted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () async {
          final result = await deleteLocalFilesInBatches(context, const []);
          onDeletionCompleted();
          if (result.isCompleted && context.mounted) {
            Navigator.of(context).pop(true);
          }
        },
        child: const Text("Delete"),
      ),
    );
  }
}
