import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/video_seek_controller.dart";

void main() {
  test(
    "retains the latest user intent while an earlier seek is in flight",
    () async {
      final firstSeek = Completer<void>();
      final seeks = <Duration>[];
      final controller = VideoSeekController(
        seek: (target) {
          seeks.add(target);
          return seeks.length == 1 ? firstSeek.future : Future.value();
        },
        readPosition: () => const Duration(seconds: 40),
        readDuration: () => const Duration(seconds: 60),
      );
      controller.onPlayerPosition(const Duration(seconds: 30));

      controller.seekBy(const Duration(seconds: 5));
      await _flushMicrotasks();
      controller.seekBy(const Duration(seconds: 5));

      expect(controller.position, const Duration(seconds: 40));
      expect(seeks, [const Duration(seconds: 35)]);

      firstSeek.complete();
      await _flushMicrotasks();

      expect(seeks, [const Duration(seconds: 35), const Duration(seconds: 40)]);
      controller.onPlayerPosition(const Duration(seconds: 40));
      expect(controller.state.phase, VideoSeekPhase.idle);
      controller.dispose();
    },
  );

  test(
    "rejects a stale player event until the requested target is observed",
    () async {
      final controller = VideoSeekController(
        seek: (_) async {},
        readPosition: () => const Duration(seconds: 35),
        readDuration: () => const Duration(seconds: 60),
      );
      controller.onPlayerPosition(const Duration(seconds: 30));

      controller.seekBy(const Duration(seconds: 5));
      await _flushMicrotasks();
      controller.onPlayerPosition(const Duration(seconds: 10));

      expect(controller.position, const Duration(seconds: 35));

      controller.onPlayerPosition(const Duration(seconds: 35));
      expect(controller.position, const Duration(seconds: 35));
      expect(controller.state.phase, VideoSeekPhase.idle);
      controller.dispose();
    },
  );

  test("a source reset keeps an in-flight seek serialized", () async {
    final firstSeek = Completer<void>();
    final seeks = <Duration>[];
    final controller = VideoSeekController(
      seek: (target) {
        seeks.add(target);
        return seeks.length == 1 ? firstSeek.future : Future.value();
      },
      readPosition: () => const Duration(seconds: 12),
      readDuration: () => const Duration(seconds: 60),
    );

    controller.seekBy(const Duration(seconds: 5));
    await _flushMicrotasks();
    controller.reset(
      position: const Duration(seconds: 12),
      duration: const Duration(seconds: 60),
    );
    controller.seekBy(const Duration(seconds: 5));
    await _flushMicrotasks();

    expect(seeks, [const Duration(seconds: 5)]);

    firstSeek.complete();
    await _flushMicrotasks();

    expect(seeks, [const Duration(seconds: 5), const Duration(seconds: 17)]);
    controller.onPlayerPosition(const Duration(seconds: 17));
    expect(controller.state.phase, VideoSeekPhase.idle);
    controller.dispose();
  });

  testWidgets("reconciles a seek when no matching event arrives", (
    tester,
  ) async {
    var playerPosition = const Duration(seconds: 30);
    final controller = VideoSeekController(
      seek: (target) async {
        playerPosition = target - const Duration(seconds: 1);
      },
      readPosition: () => playerPosition,
      readDuration: () => const Duration(seconds: 60),
    );
    controller.onPlayerPosition(playerPosition);

    controller.seekBy(const Duration(seconds: 5));
    await tester.pump();
    expect(controller.state.phase, VideoSeekPhase.settling);

    await tester.pump(const Duration(seconds: 2));
    expect(controller.position, const Duration(seconds: 34));
    expect(controller.state.phase, VideoSeekPhase.idle);
    controller.dispose();
  });

  test("does not notify listeners for an unchanged player position", () {
    final controller = VideoSeekController(
      seek: (_) async {},
      readPosition: () => const Duration(seconds: 30),
      readDuration: () => const Duration(seconds: 60),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.onPlayerPosition(const Duration(seconds: 30));
    notifications = 0;
    controller.onPlayerPosition(const Duration(seconds: 30));

    expect(notifications, 0);
    controller.dispose();
  });

  test("does not enter dragging until a duration is available", () {
    final controller = VideoSeekController(
      seek: (_) async {},
      readPosition: () => Duration.zero,
      readDuration: () => null,
    );

    controller.beginSliderInteraction();
    controller.endSliderInteraction(Duration.zero);

    expect(controller.state.phase, VideoSeekPhase.idle);
    controller.dispose();
  });

  testWidgets("a slider release seeks to its final target", (tester) async {
    final seeks = <Duration>[];
    final controller = VideoSeekController(
      seek: (target) async {
        seeks.add(target);
      },
      readPosition: () => const Duration(seconds: 10),
      readDuration: () => const Duration(seconds: 60),
    );

    controller.beginSliderInteraction();
    controller.updateSliderTarget(const Duration(seconds: 20));
    controller.endSliderInteraction(const Duration(seconds: 40));
    await tester.pump();

    expect(seeks, [const Duration(seconds: 40)]);
    controller.dispose();
  });

  test("relative seeks clamp to bounds and skip no-op commands", () async {
    final seeks = <Duration>[];
    final controller = VideoSeekController(
      seek: (target) async {
        seeks.add(target);
      },
      readPosition: () => const Duration(seconds: 3),
      readDuration: () => const Duration(seconds: 60),
    );
    controller.onPlayerPosition(const Duration(seconds: 3));

    controller.seekBy(const Duration(seconds: -5));
    await _flushMicrotasks();
    controller.onPlayerPosition(Duration.zero);
    controller.seekBy(const Duration(seconds: -5));
    controller.seekBy(const Duration(seconds: 70));
    await _flushMicrotasks();

    expect(seeks, [Duration.zero, const Duration(seconds: 60)]);
    controller.dispose();
  });

  testWidgets("does not reconcile while a slider interaction is active", (
    tester,
  ) async {
    final controller = VideoSeekController(
      seek: (_) async {},
      readPosition: () => const Duration(seconds: 10),
      readDuration: () => const Duration(seconds: 60),
    );

    controller.beginSliderInteraction();
    controller.updateSliderTarget(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));

    expect(controller.position, const Duration(seconds: 30));
    expect(controller.state.phase, VideoSeekPhase.dragging);
    controller.dispose();
  });

  test("recovers from a failed seek command", () async {
    final controller = VideoSeekController(
      seek: (_) => Future.error(StateError("seek failed")),
      readPosition: () => const Duration(seconds: 10),
      readDuration: () => const Duration(seconds: 60),
    );
    controller.onPlayerPosition(const Duration(seconds: 10));

    controller.seekBy(const Duration(seconds: 5));
    await _flushMicrotasks();

    expect(controller.position, const Duration(seconds: 10));
    expect(controller.state.phase, VideoSeekPhase.idle);
    controller.dispose();
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);
