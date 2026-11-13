import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/gallery/gallery_zoom_image.dart";

void main() {
  testWidgets(
    "repaints thumbnail cropping only when its aspect ratio changes",
    (tester) async {
      final density = AnimationController.unbounded(vsync: tester, value: 3);
      addTearDown(density.dispose);

      Widget thumbnail(Rect to) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: RepaintBoundary(
              child: GalleryZoomImage(
                animation: density,
                lower: 3,
                from: const Rect.fromLTWH(0, 0, 100, 100),
                to: to,
                image: null,
                child: const ColoredBox(color: Color(0xffabcdef)),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(thumbnail(const Rect.fromLTWH(50, 50, 75, 75)));
      final render = tester.renderObject<RenderGalleryZoomImage>(
        find.byType(GalleryZoomImage),
      );
      expect(render.debugNeedsPaint, isFalse);
      density.value = 3.5;
      expect(render.debugNeedsPaint, isFalse);

      await tester.pumpWidget(thumbnail(const Rect.fromLTWH(50, 50, 75, 150)));
      expect(render.debugNeedsPaint, isFalse);
      density.value = 3.75;
      expect(render.debugNeedsPaint, isTrue);
      await tester.pump();
      expect(render.debugNeedsPaint, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
