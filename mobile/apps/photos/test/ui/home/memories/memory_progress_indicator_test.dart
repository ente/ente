import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";

void main() {
  testWidgets("uses the full track when segmented chunks become too narrow", (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 343,
            child: MemoryProgressIndicator(totalSteps: 20, currentIndex: 7),
          ),
        ),
      ),
    );

    expect(find.byType(Row), findsNothing);
    expect(tester.getSize(find.byType(LinearProgressIndicator)).width, 343);
  });
}
