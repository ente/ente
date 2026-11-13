import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/video_double_tap_seek.dart";

void main() {
  testWidgets("opposite-direction double taps reset the accumulated badge", (
    tester,
  ) async {
    final seeks = <Duration>[];
    var position = const Duration(seconds: 30);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: DoubleTapSeekOverlay(
            enabled: () => true,
            position: () => position,
            duration: () => const Duration(seconds: 60),
            seekBy: (delta) {
              position += delta;
              if (position < Duration.zero) position = Duration.zero;
              if (position > const Duration(seconds: 60)) {
                position = const Duration(seconds: 60);
              }
              seeks.add(position);
              return position;
            },
          ),
        ),
      ),
    );

    await _doubleTap(tester, forward: true);
    await _doubleTap(tester, forward: false);

    expect(seeks, [const Duration(seconds: 35), const Duration(seconds: 30)]);
    expect(find.text("5s"), findsOneWidget);
  });

  testWidgets("rapid same-direction double taps accumulate the badge", (
    tester,
  ) async {
    final seeks = <Duration>[];
    var position = Duration.zero;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: DoubleTapSeekOverlay(
            enabled: () => true,
            position: () => position,
            duration: () => const Duration(seconds: 40),
            seekBy: (delta) {
              position += delta;
              if (position > const Duration(seconds: 40)) {
                position = const Duration(seconds: 40);
              }
              seeks.add(position);
              return position;
            },
          ),
        ),
      ),
    );

    for (var i = 0; i < 8; i++) {
      await _doubleTap(tester, forward: true);
    }

    expect(seeks, [
      for (var seconds = 5; seconds <= 40; seconds += 5)
        Duration(seconds: seconds),
    ]);
    expect(find.text("40s"), findsOneWidget);
  });

  testWidgets(
    "keeps the requested badge when position updates are stale at a boundary",
    (tester) async {
      final seeks = <Duration>[];
      const position = Duration(seconds: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: DoubleTapSeekOverlay(
              enabled: () => true,
              position: () => position,
              duration: () => const Duration(seconds: 60),
              seekBy: (delta) {
                final unclampedTarget = position + delta;
                final target = unclampedTarget < Duration.zero
                    ? Duration.zero
                    : unclampedTarget > const Duration(seconds: 60)
                    ? const Duration(seconds: 60)
                    : unclampedTarget;
                seeks.add(target);
                return target;
              },
            ),
          ),
        ),
      );

      await _doubleTap(tester, forward: false);
      await _doubleTap(tester, forward: false);

      expect(seeks, [Duration.zero, Duration.zero]);
      expect(find.text("5s"), findsOneWidget);
    },
  );

  testWidgets("reports the requested seek at a boundary", (tester) async {
    var position = const Duration(seconds: 57);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: DoubleTapSeekOverlay(
            enabled: () => true,
            position: () => position,
            duration: () => const Duration(seconds: 60),
            seekBy: (delta) {
              position += delta;
              if (position > const Duration(seconds: 60)) {
                position = const Duration(seconds: 60);
              }
              return position;
            },
          ),
        ),
      ),
    );

    await _doubleTap(tester, forward: true);

    expect(find.text("5s"), findsOneWidget);
  });

  testWidgets("does not seek while the overlay is disabled", (tester) async {
    var seekCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: DoubleTapSeekOverlay(
            enabled: () => false,
            position: () => const Duration(seconds: 30),
            duration: () => const Duration(seconds: 60),
            seekBy: (_) {
              seekCount++;
              return const Duration(seconds: 30);
            },
          ),
        ),
      ),
    );

    await _doubleTap(tester, forward: true);

    expect(seekCount, 0);
  });
}

Future<void> _doubleTap(WidgetTester tester, {required bool forward}) async {
  final rect = tester.getRect(find.byType(DoubleTapSeekOverlay));
  final position = Offset(
    rect.left + rect.width * (forward ? 0.75 : 0.25),
    rect.center.dy,
  );
  final firstTap = await tester.startGesture(position);
  await firstTap.up();
  await tester.pump(const Duration(milliseconds: 50));

  final secondTap = await tester.startGesture(position);
  await secondTap.up();
  await tester.pump(const Duration(milliseconds: 400));
}
