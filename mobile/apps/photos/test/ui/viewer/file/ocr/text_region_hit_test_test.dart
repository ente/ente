import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile_ocr/models/text_region.dart";
import "package:photos/ui/viewer/file/ocr/text_region_hit_test.dart";

void main() {
  const imageSize = Size(400, 200);
  const viewportSize = Size(200, 200);
  const region = TextRegion(
    confidence: 0.9,
    points: [
      Offset(100, 50),
      Offset(300, 50),
      Offset(300, 100),
      Offset(100, 100),
    ],
  );

  test("maps letterboxed viewport points into image coordinates", () {
    expect(
      containedImageRect(viewportSize, imageSize),
      const Rect.fromLTWH(0, 50, 200, 100),
    );
    expect(
      isViewportPointInTextRegions(
        point: const Offset(100, 87.5),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
      ),
      isTrue,
    );
  });

  test("rejects points outside text and outside the displayed image", () {
    expect(
      isViewportPointInTextRegions(
        point: const Offset(20, 90),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
      ),
      isFalse,
    );
    expect(
      isViewportPointInTextRegions(
        point: const Offset(100, 20),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
      ),
      isFalse,
    );
  });

  test("applies hit slop in viewport pixels", () {
    expect(
      isViewportPointInTextRegions(
        point: const Offset(45, 87.5),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
        hitSlop: 8,
      ),
      isTrue,
    );
  });

  test("maps zoomed and panned viewport points back to text regions", () {
    const scale = 2.0;
    const offset = Offset(20, -10);

    expect(
      isZoomedViewportPointInTextRegions(
        point: const Offset(120, 65),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
        scale: scale,
        offset: offset,
      ),
      isTrue,
    );
    expect(
      isViewportPointInTextRegions(
        point: const Offset(120, 65),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
      ),
      isFalse,
    );
  });

  test("keeps region hit slop constant on screen while zoomed", () {
    expect(
      isZoomedViewportPointInTextRegions(
        point: const Offset(10, 75),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [region],
        scale: 2,
        offset: const Offset(20, -10),
        hitSlop: 8,
      ),
      isFalse,
    );
  });

  test("does not claim corners outside a rotated text region", () {
    const rotatedRegion = TextRegion(
      confidence: 0.9,
      points: [
        Offset(200, 20),
        Offset(380, 100),
        Offset(200, 180),
        Offset(20, 100),
      ],
    );

    expect(
      isViewportPointInTextRegions(
        point: const Offset(15, 60),
        viewportSize: viewportSize,
        imageSize: imageSize,
        regions: const [rotatedRegion],
      ),
      isFalse,
    );
  });
}
