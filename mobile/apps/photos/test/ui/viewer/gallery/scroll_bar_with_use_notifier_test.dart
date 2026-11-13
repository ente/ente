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
        bool thumbVisibility = true,
        bool? showThumb,
        double contentHeight = 12000,
        TextDirection textDirection = TextDirection.ltr,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) =>
                Directionality(textDirection: textDirection, child: child!),
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 600,
                child: ScrollbarWithUseNotifer(
                  controller: controller,
                  inUseNotifier: inUseNotifier,
                  interactive: true,
                  thumbVisibility: thumbVisibility,
                  showThumb: showThumb,
                  minScrollbarLength: 36,
                  thickness: 8,
                  scrollbarPadding: const EdgeInsets.only(right: 3),
                  child: SingleChildScrollView(
                    controller: controller,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onPhotoTap,
                      child: SizedBox(height: contentHeight, width: 400),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      ScrollbarPainter painter(WidgetTester tester) => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.foregroundPainter)
          .whereType<ScrollbarPainter>()
          .single;

      testWidgets(
        "thumb waits two seconds then fades and releases its target",
        (tester) async {
          var photoTaps = 0;
          await pumpScrollbar(
            tester,
            thumbVisibility: false,
            onPhotoTap: () => photoTaps++,
          );
          controller.jumpTo(3000);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1900));
          expect(painter(tester).fadeoutOpacityAnimation.value, 1);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            painter(tester).fadeoutOpacityAnimation.value,
            inExclusiveRange(0, 1),
          );
          await tester.pump(const Duration(milliseconds: 150));
          expect(painter(tester).fadeoutOpacityAnimation.value, 0);

          await tester.tapAt(const Offset(360, 166));
          await tester.pump();
          expect(photoTaps, 1);
          final gesture = await tester.startGesture(const Offset(360, 166));
          await gesture.moveBy(const Offset(0, -20));
          await tester.pump();
          await gesture.moveBy(const Offset(0, -60));
          await tester.pump();
          expect(inUseNotifier.value, isFalse);
          expect(controller.offset, greaterThan(3000));
          await gesture.up();
          await tester.pumpAndSettle();
        },
      );

      testWidgets("hidden thumb leaves short-gallery taps and swipes alone", (
        tester,
      ) async {
        var photoTaps = 0;
        await pumpScrollbar(
          tester,
          thumbVisibility: false,
          showThumb: false,
          contentHeight: 1500,
          onPhotoTap: () => photoTaps++,
        );
        controller.jumpTo(300);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(painter(tester).fadeoutOpacityAnimation.value, 1);
        expect(painter(tester).color.a, 0);

        final gesture = await tester.startGesture(const Offset(392, 240));
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump();
        expect(inUseNotifier.value, isFalse);
        expect(controller.offset, greaterThan(300));
        await gesture.up();
        await tester.pumpAndSettle();

        controller.jumpTo(300);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tapAt(const Offset(392, 240));
        await tester.pump();
        expect(photoTaps, 1);
      });

      testWidgets(
        "inward target follows the thumb and keeps an acquired drag",
        (tester) async {
          var photoTaps = 0;
          await pumpScrollbar(tester, onPhotoTap: () => photoTaps++);
          controller.jumpTo(3000);
          await tester.pumpAndSettle();

          final gesture = await tester.startGesture(const Offset(360, 166));
          await gesture.moveBy(const Offset(0, 10));
          await tester.pump();
          expect(inUseNotifier.value, isTrue);
          await gesture.moveBy(const Offset(-160, 90));
          await tester.pump();
          expect(inUseNotifier.value, isTrue);
          expect(controller.offset, greaterThan(4500));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(inUseNotifier.value, isFalse);

          for (final position in [
            const Offset(360, 18),
            const Offset(350, 166),
            const Offset(360, 196),
          ]) {
            controller.jumpTo(3000);
            await tester.pumpAndSettle();
            await tester.tapAt(position);
            await tester.pump();
            final swipe = await tester.startGesture(position);
            await swipe.moveBy(const Offset(0, -20));
            await tester.pump();
            await swipe.moveBy(const Offset(0, -60));
            await tester.pump();
            expect(
              inUseNotifier.value,
              isFalse,
              reason: "swipe from $position",
            );
            expect(controller.offset, greaterThan(3000));
            await swipe.up();
            await tester.pumpAndSettle();
          }
          expect(photoTaps, 3);
        },
      );

      testWidgets("inward target mirrors with a left-side RTL thumb", (
        tester,
      ) async {
        await pumpScrollbar(tester, textDirection: TextDirection.rtl);
        controller.jumpTo(3000);
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(const Offset(36, 166));
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        expect(inUseNotifier.value, isTrue);
        await gesture.moveBy(const Offset(0, 90));
        await tester.pump();
        expect(controller.offset, greaterThan(4500));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(inUseNotifier.value, isFalse);
      });

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
