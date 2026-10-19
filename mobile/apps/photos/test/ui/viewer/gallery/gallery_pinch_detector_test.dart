import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/gallery/gallery_pinch_detector.dart";

void main() {
  testWidgets("leaves taps and established one-finger scrolling unchanged", (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var taps = 0;
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GalleryPinchDetector(
          enabled: true,
          onStart: (_) => starts++,
          onUpdate: (_, _) {},
          onEnd: (_) {},
          child: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, _) => GestureDetector(
              onTap: () => taps++,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(height: 80),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    final first = await tester.startGesture(const Offset(100, 300), pointer: 1);
    await first.moveTo(const Offset(100, 200));
    await first.moveTo(const Offset(100, 150));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
    final second = await tester.startGesture(
      const Offset(200, 150),
      pointer: 2,
    );
    await second.moveTo(const Offset(240, 150));
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(taps, 1);
  });

  testWidgets(
    "starts on the second finger, keeps its pair and consumes trailing taps",
    (tester) async {
      final starts = <Offset>[];
      final updates = <(double, Offset)>[];
      final ends = <bool>[];
      var taps = 0;
      const detectorKey = ValueKey("pinch");
      await tester.pumpWidget(
        MaterialApp(
          home: Padding(
            padding: const EdgeInsets.only(left: 20, top: 30),
            child: GalleryPinchDetector(
              key: detectorKey,
              enabled: true,
              onStart: starts.add,
              onUpdate: (scale, focalPoint) => updates.add((scale, focalPoint)),
              onEnd: ends.add,
              child: GestureDetector(
                onTap: () => taps++,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byKey(detectorKey));
      final first = await tester.startGesture(
        origin + const Offset(70, 140),
        pointer: 1,
      );
      expect(starts, isEmpty);
      final second = await tester.startGesture(
        origin + const Offset(170, 140),
        pointer: 2,
      );
      expect(starts, [const Offset(120, 140)]);
      await first.moveTo(origin + const Offset(50, 140));
      await second.moveTo(origin + const Offset(190, 140));
      expect(updates.last.$1, closeTo(1.4, 0.0001));
      expect(updates.last.$2, const Offset(120, 140));

      final updateCount = updates.length;
      final third = await tester.startGesture(
        origin + const Offset(300, 300),
        pointer: 3,
      );
      await third.moveTo(origin + const Offset(350, 350));
      expect(updates.length, updateCount);
      expect(starts, hasLength(1));
      await first.up();
      expect(ends, [false]);
      await second.moveTo(origin + const Offset(220, 140));
      await third.up();
      await second.up();
      expect(updates.length, updateCount);
      expect(ends, [false]);
      expect(taps, 0);

      await tester.tapAt(origin + const Offset(100, 100));
      expect(taps, 1);
    },
  );

  testWidgets("pointer cancellation and disabling cancel exactly once", (
    tester,
  ) async {
    var enabled = true;
    late StateSetter rebuild;
    final ends = <bool>[];
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return GalleryPinchDetector(
              enabled: enabled,
              onStart: (_) => starts++,
              onUpdate: (_, _) {},
              onEnd: ends.add,
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );

    for (final disable in [false, true]) {
      final first = await tester.startGesture(
        const Offset(100, 100),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(200, 100),
        pointer: 2,
      );
      if (disable) {
        rebuild(() => enabled = false);
        await tester.pump();
        await first.up();
      } else {
        await first.cancel();
      }
      await second.up();
      expect(ends, everyElement(isTrue));
      expect(ends.length, starts);
    }
    expect(starts, 2);
    expect(ends, [true, true]);

    final first = await tester.startGesture(const Offset(100, 100), pointer: 1);
    final second = await tester.startGesture(
      const Offset(200, 100),
      pointer: 2,
    );
    await first.moveTo(const Offset(70, 100));
    await second.up();
    await first.up();
    expect(starts, 2);
    expect(ends, [true, true]);
    for (final nextEnabled in [true, false, true]) {
      rebuild(() => enabled = nextEnabled);
      await tester.pump();
    }
    final resumedFirst = await tester.startGesture(
      const Offset(100, 100),
      pointer: 3,
    );
    final resumedSecond = await tester.startGesture(
      const Offset(200, 100),
      pointer: 4,
    );
    await resumedFirst.up();
    await resumedSecond.up();
    expect(starts, 3);
    expect(ends, [true, true, false]);
    expect(tester.takeException(), isNull);
  });
}
