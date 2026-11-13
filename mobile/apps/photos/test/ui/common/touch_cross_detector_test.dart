import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/common/touch_cross_detector.dart";

void main() {
  testWidgets(
    "inactive crossing only checks the starting tile and enables immediately",
    (tester) async {
      var trackMoves = false;
      var firstEntries = 0;
      var firstExits = 0;
      var secondEntries = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Row(
              children: [
                _CountingDetector(
                  shouldTrackPointerMoves: () => trackMoves,
                  onEnter: (_) => firstEntries++,
                  onExit: (_) => firstExits++,
                ),
                _CountingDetector(
                  shouldTrackPointerMoves: () => trackMoves,
                  onEnter: (_) => secondEntries++,
                ),
              ],
            ),
          ),
        ),
      );
      final detectors = tester
          .renderObjectList<_CountingRenderDetector>(
            find.byType(_CountingDetector),
          )
          .toList();
      final gesture = await tester.startGesture(const Offset(99, 50));
      for (final detector in detectors) {
        detector.boundsChecks = 0;
      }

      // A small move across the initial tile's edge must still update the
      // long-press bookkeeping, without checking any other gallery tile.
      await gesture.moveTo(const Offset(101, 50));
      await gesture.moveTo(const Offset(99, 50));
      expect(firstEntries, 2);
      expect(firstExits, 1);
      expect(secondEntries, 0);
      expect(detectors.first.boundsChecks, 2);
      expect(detectors.last.boundsChecks, 0);

      // The activation event must work before the next widget rebuild.
      trackMoves = true;
      await gesture.moveTo(const Offset(150, 50));
      expect(secondEntries, 1);
      expect(detectors.last.boundsChecks, 1);
      await gesture.up();
    },
  );

  for (final cancel in [false, true]) {
    testWidgets(
      "${cancel ? 'cancel' : 'up'} clears pointer tracking when crossing is disabled",
      (tester) async {
        var exits = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: _CountingDetector(
                shouldTrackPointerMoves: () => false,
                onExit: (_) => exits++,
              ),
            ),
          ),
        );
        final detector = tester.renderObject<_CountingRenderDetector>(
          find.byType(_CountingDetector),
        );
        const pointer = 7;
        final gesture = await tester.startGesture(
          const Offset(50, 50),
          pointer: pointer,
        );
        expect(TouchCrossDetector.isPointerActive(pointer), isTrue);
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        expect(exits, 1);
        expect(TouchCrossDetector.isPointerActive(pointer), isFalse);

        // Reusing the ID outside the tile must not inherit its original
        // pointer's exemption from the crossing gate.
        final nextGesture = await tester.startGesture(
          const Offset(150, 50),
          pointer: pointer,
        );
        detector.boundsChecks = 0;
        await nextGesture.moveTo(const Offset(50, 50));
        expect(detector.boundsChecks, 0);
        await nextGesture.up();
      },
    );
  }
}

class _CountingDetector extends TouchCrossDetector {
  const _CountingDetector({
    required super.shouldTrackPointerMoves,
    super.onEnter,
    super.onExit,
  }) : super(child: const SizedBox(width: 100, height: 100));

  @override
  _CountingRenderDetector createRenderObject(BuildContext context) {
    return _CountingRenderDetector(
      shouldTrackPointerMoves: shouldTrackPointerMoves,
      onEnter: onEnter,
      onExit: onExit,
    );
  }
}

class _CountingRenderDetector extends RenderTouchCrossDetector {
  _CountingRenderDetector({
    required super.shouldTrackPointerMoves,
    super.onEnter,
    super.onExit,
  });

  int boundsChecks = 0;

  @override
  Offset globalToLocal(Offset point, {RenderObject? ancestor}) {
    boundsChecks++;
    return super.globalToLocal(point, ancestor: ancestor);
  }
}
