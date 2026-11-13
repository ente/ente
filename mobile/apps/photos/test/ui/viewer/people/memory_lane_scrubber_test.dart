import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/people/memory_lane_scrubber.dart";

void main() {
  testWidgets("keeps endpoint taps and drags within the current memory", (
    tester,
  ) async {
    for (final fromLeft in [true, false]) {
      var memoryIndex = 1;
      int? photoIndex;
      var seekEnds = 0;
      await _pumpMemoryPager(
        tester,
        onPageChanged: (index) => memoryIndex = index,
        onTap: (index) => photoIndex = index,
        onSeek: (index) => photoIndex = index,
        onSeekEnd: () => seekEnds++,
      );
      final track = tester.getRect(find.byType(Row));
      final start = Offset(
        fromLeft ? track.left - 12 : track.right + 12,
        track.center.dy,
      );

      await tester.dragFrom(start, Offset(fromLeft ? 340 : -340, 0));
      await tester.pumpAndSettle();
      expect(memoryIndex, 1);
      expect(photoIndex, fromLeft ? 19 : 0);
      expect(seekEnds, 1);

      await tester.tapAt(start);
      await tester.pumpAndSettle();
      expect(photoIndex, fromLeft ? 0 : 19);

      await tester.tapAt(track.center);
      await tester.pumpAndSettle();
      expect(photoIndex, 10);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets("allows memory-card swipes outside the scrubber", (tester) async {
    var memoryIndex = 1;
    await _pumpMemoryPager(
      tester,
      onPageChanged: (index) => memoryIndex = index,
      onTap: (_) => fail("A card swipe must not seek a photo"),
      onSeek: (_) => fail("A card swipe must not seek a photo"),
      onSeekEnd: () => fail("A card swipe must not end a seek"),
    );

    final pager = tester.getRect(find.byType(PageView));
    await tester.dragFrom(pager.center, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(memoryIndex, 2);
  });
}

Future<void> _pumpMemoryPager(
  WidgetTester tester, {
  required ValueChanged<int> onPageChanged,
  required ValueChanged<int> onTap,
  required ValueChanged<int> onSeek,
  required VoidCallback onSeekEnd,
}) async {
  final controller = PageController(initialPage: 1);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: PageView(
            controller: controller,
            physics: const BouncingScrollPhysics(),
            onPageChanged: onPageChanged,
            children: [
              const SizedBox.expand(),
              Align(
                alignment: Alignment.bottomCenter,
                child: MemoryLaneScrubber(
                  totalEntries: 20,
                  currentIndex: 10,
                  onTap: onTap,
                  onSeek: onSeek,
                  onSeekEnd: onSeekEnd,
                ),
              ),
              const SizedBox.expand(),
            ],
          ),
        ),
      ),
    ),
  );
}
