import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/viewer/file/inline_text_detection.dart";

void main() {
  testWidgets("inactive OCR leaves still-photo taps available", (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      _testViewer(
        photo: GestureDetector(
          key: const Key("photo"),
          behavior: HitTestBehavior.opaque,
          onTap: () => tapped = true,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key("photo")));

    expect(tapped, isTrue);
  });

  testWidgets("inactive OCR leaves still-photo paging available", (
    tester,
  ) async {
    final pageController = PageController();
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      _testViewer(
        photo: PageView(
          controller: pageController,
          children: const [
            ColoredBox(color: Colors.black),
            SizedBox.expand(),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(pageController.page, 1);
  });
}

Widget _testViewer({required Widget photo}) {
  final file = EnteFile()
    ..generatedID = 1
    ..fileType = FileType.image;

  return MaterialApp(
    home: InheritedDetailPageState(
      enableFullScreenNotifier: ValueNotifier(false),
      isInSharedCollectionNotifier: ValueNotifier(false),
      showingThumbnailFallbackNotifier: ValueNotifier(null),
      isZoomedNotifier: ValueNotifier(false),
      zoomTransformNotifier: ValueNotifier(ZoomTransform.identity),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: photo),
            Positioned.fill(
              child: InlineTextDetection(
                file: file,
                controller: InlineTextDetectionController(),
                isGuestView: false,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
