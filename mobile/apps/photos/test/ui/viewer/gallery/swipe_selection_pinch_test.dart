import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/ui/viewer/gallery/component/swipe_selectable_file_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/swipe_selection_wrapper.dart";
import "package:photos/ui/viewer/gallery/swipe_to_select_helper.dart";

void main() {
  testWidgets("pinch stops selection and autoscroll until every finger lifts", (
    tester,
  ) async {
    final files = List.generate(
      5,
      (index) => EnteFile()..generatedID = index + 1,
    );
    final selectedFiles = SelectedFiles()..selectAll({files.first});
    final helper = SwipeToSelectHelper(
      allFiles: files,
      selectedFiles: selectedFiles,
    );
    final swipeActive = ValueNotifier(false);
    final controller = ScrollController();
    final boundaries = GlobalKey<GalleryBoundariesProviderState>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      helper.dispose();
      selectedFiles.dispose();
      swipeActive.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: GalleryBoundariesProvider(
          key: boundaries,
          child: SwipeSelectionWrapper(
            swipeHelper: helper,
            selectedFiles: selectedFiles,
            isEnabled: true,
            swipeActiveNotifier: swipeActive,
            scrollController: controller,
            child: SingleChildScrollView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 520),
                  Row(
                    children: [
                      for (final file in files)
                        SwipeSelectableFileWidget(
                          file: file,
                          selectedFiles: selectedFiles,
                          child: const SizedBox(
                            width: 100,
                            height: 80,
                            child: ColoredBox(color: Colors.blue),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    boundaries.currentState!
      ..setScrollController(controller, swipeActiveNotifier: swipeActive)
      ..setTopBoundary(0)
      ..setBottomBoundary(500);

    final first = await tester.startGesture(const Offset(150, 550), pointer: 1);
    await first.moveBy(const Offset(20, 0));
    expect(swipeActive.value, isTrue);
    expect(helper.isActive, isTrue);
    expect(selectedFiles.files, unorderedEquals([files.first, files[1]]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.offset, greaterThan(0));

    final beforePinch = selectedFiles.files.toSet();
    final second = await tester.startGesture(
      const Offset(350, 550),
      pointer: 2,
    );
    expect(swipeActive.value, isFalse);
    expect(helper.isActive, isFalse);
    expect(selectedFiles.files, unorderedEquals(beforePinch));
    final stoppedOffset = controller.offset;
    await first.moveTo(const Offset(250, 550));
    await second.moveTo(const Offset(450, 550));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, stoppedOffset);
    expect(swipeActive.value, isFalse);
    expect(helper.isActive, isFalse);
    expect(selectedFiles.files, unorderedEquals(beforePinch));

    await first.up();
    await second.moveTo(const Offset(150, 550));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, stoppedOffset);
    expect(swipeActive.value, isFalse);
    expect(helper.isActive, isFalse);
    expect(selectedFiles.files, unorderedEquals(beforePinch));
    await second.up();

    final next = await tester.startGesture(const Offset(250, 550), pointer: 3);
    await next.moveBy(const Offset(20, 0));
    expect(swipeActive.value, isTrue);
    expect(helper.isActive, isTrue);
    await next.moveTo(const Offset(350, 550));
    expect(selectedFiles.files, unorderedEquals(files.take(4)));
    await next.up();
    expect(swipeActive.value, isFalse);
    expect(helper.isActive, isFalse);

    final pending = await tester.startGesture(
      const Offset(250, 550),
      pointer: 4,
    );
    final beforeDeferredSelection = selectedFiles.files.toSet();
    swipeActive.value = true;
    tester.binding.addPostFrameCallback((_) {
      tester.binding.handlePointerEvent(
        const PointerDownEvent(pointer: 5, position: Offset(450, 550)),
      );
    });
    await tester.pump();
    expect(swipeActive.value, isFalse);
    expect(helper.isActive, isFalse);
    expect(selectedFiles.files, unorderedEquals(beforeDeferredSelection));
    tester.binding.handlePointerEvent(
      const PointerUpEvent(pointer: 5, position: Offset(450, 550)),
    );
    await pending.up();
  });
}
