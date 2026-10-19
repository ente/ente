import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/gallery/scrollbar/scroll_bar_with_use_notifier.dart";

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group(platform.name, () {
      late ScrollController controller;
      late ValueNotifier<bool> inUseNotifier;

      setUp(() {
        controller = ScrollController();
        inUseNotifier = ValueNotifier(false);
      });

      tearDown(() {
        controller.dispose();
        inUseNotifier.dispose();
      });

      Future<void> pumpScrollbar(
        WidgetTester tester, {
        VoidCallback? onPhotoTap,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 600,
                child: ScrollbarWithUseNotifer(
                  controller: controller,
                  inUseNotifier: inUseNotifier,
                  interactive: true,
                  thumbVisibility: true,
                  minScrollbarLength: 36,
                  thickness: 8,
                  scrollbarPadding: const EdgeInsets.only(right: 3),
                  child: SingleChildScrollView(
                    controller: controller,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onPhotoTap,
                      child: const SizedBox(height: 12000, width: 400),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets("track taps above and below the thumb do not scroll", (
        tester,
      ) async {
        await pumpScrollbar(tester);
        controller.jumpTo(2000);
        await tester.pumpAndSettle();

        for (final position in [
          const Offset(392, 50),
          const Offset(392, 500),
        ]) {
          await tester.tapAt(position);
          await tester.pumpAndSettle();
          expect(controller.offset, 2000);
          expect(inUseNotifier.value, isFalse);
        }
      });

      testWidgets("visible and padded thumb targets still drag the gallery", (
        tester,
      ) async {
        await pumpScrollbar(tester);

        for (final position in [const Offset(392, 18), const Offset(372, 40)]) {
          controller.jumpTo(0);
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(position);
          await tester.pumpAndSettle();
          await gesture.moveBy(const Offset(0, 10));
          await tester.pump();
          expect(inUseNotifier.value, isTrue, reason: "drag from $position");
          await gesture.moveBy(const Offset(0, 100));
          await tester.pump();
          expect(controller.offset, greaterThan(0));

          await gesture.up();
          await tester.pumpAndSettle();
          expect(inUseNotifier.value, isFalse);
        }
      });

      testWidgets("gallery swipes and photo taps beside the track still work", (
        tester,
      ) async {
        var photoTaps = 0;
        await pumpScrollbar(tester, onPhotoTap: () => photoTaps++);

        await tester.tapAt(const Offset(370, 450));
        await tester.pumpAndSettle();
        expect(photoTaps, 1);
        expect(controller.offset, 0);

        await tester.dragFrom(const Offset(370, 450), const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(0));
        expect(inUseNotifier.value, isFalse);
        expect(photoTaps, 1);
      });
    });
  }
}
