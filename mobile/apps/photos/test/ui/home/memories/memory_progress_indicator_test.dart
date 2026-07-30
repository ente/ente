import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";

void main() {
  testWidgets("fills the available width with equal chunks", (tester) async {
    const totalSteps = 6;
    const availableWidth = 343.0;
    const currentIndex = 3;

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: availableWidth,
            child: MemoryProgressIndicator(
              totalSteps: totalSteps,
              currentIndex: currentIndex,
            ),
          ),
        ),
      ),
    );

    final widths = [
      for (var index = 0; index < totalSteps; index++)
        tester
            .getSize(find.byKey(ValueKey("memory-progress-segment-$index")))
            .width,
    ];

    for (final width in widths.skip(1)) {
      expect(width, widths.first);
    }
    expect(
      widths.reduce((left, right) => left + right) +
          ((totalSteps - 1) * kMemoryProgressGap),
      availableWidth,
    );
  });

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
