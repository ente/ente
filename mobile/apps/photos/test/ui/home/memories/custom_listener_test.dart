import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/custom_listener.dart";

void main() {
  const targetKey = ValueKey("gesture-target");

  Future<void> pumpListener(
    WidgetTester tester, {
    required VoidCallback onSwipeUp,
    bool Function()? canSwipeUp,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 200,
            child: MemoriesPointerGestureListener(
              onSwipeUp: onSwipeUp,
              canSwipeUp: canSwipeUp,
              child: const ColoredBox(key: targetKey, color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets("opens details after an upward-dominant swipe", (tester) async {
    var swipeCount = 0;
    await pumpListener(tester, onSwipeUp: () => swipeCount++);

    await tester.drag(find.byKey(targetKey), const Offset(10, -60));

    expect(swipeCount, 1);
  });

  testWidgets("opens details when an upward swipe follows a hold", (
    tester,
  ) async {
    var swipeCount = 0;
    await pumpListener(tester, onSwipeUp: () => swipeCount++);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(targetKey)),
    );

    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -60));
    await gesture.up();

    expect(swipeCount, 1);
  });

  testWidgets("does not open details after horizontal page displacement", (
    tester,
  ) async {
    var swipeCount = 0;
    await pumpListener(tester, onSwipeUp: () => swipeCount++);

    await tester.drag(find.byKey(targetKey), const Offset(20, -60));

    expect(swipeCount, 0);
  });

  testWidgets("does not open details while media is zoomed", (tester) async {
    var swipeCount = 0;
    await pumpListener(
      tester,
      onSwipeUp: () => swipeCount++,
      canSwipeUp: () => false,
    );

    await tester.drag(find.byKey(targetKey), const Offset(0, -60));

    expect(swipeCount, 0);
  });

  testWidgets("disqualifies the full gesture after multitouch", (tester) async {
    var swipeCount = 0;
    await pumpListener(tester, onSwipeUp: () => swipeCount++);
    final center = tester.getCenter(find.byKey(targetKey));
    final firstPointer = await tester.startGesture(center, pointer: 1);
    final secondPointer = await tester.startGesture(
      center + const Offset(10, 0),
      pointer: 2,
    );

    await secondPointer.up();
    await firstPointer.moveBy(const Offset(0, -60));
    await firstPointer.up();

    expect(swipeCount, 0);
  });
}
