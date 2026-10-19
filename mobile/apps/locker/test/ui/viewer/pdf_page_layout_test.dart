import "dart:ui";

import "package:flutter_test/flutter_test.dart";
import "package:locker/ui/viewer/pdf_page_layout.dart";

void main() {
  PdfPageLayout layout(List<Size> pages, {double viewportHeight = 800}) {
    return PdfPageLayout(
      pageSizes: pages,
      viewportWidth: 400,
      viewportHeight: viewportHeight,
      topInset: 100,
      bottomPadding: 20,
    );
  }

  test("stacks pages at content width with gaps and insets", () {
    final pages = layout(const [Size(100, 200), Size(200, 100)]);
    expect(pages.contentWidth, 368);
    expect(pages.offsets, [100, 848, 1044]);
    expect(pages.pageHeight(0), 736);
    expect(pages.pageHeight(1), 184);
    expect(pages.contentHeight, 1052);
  });

  test("content height never drops below the viewport", () {
    final single = layout(const [Size(200, 100)], viewportHeight: 900);
    expect(single.contentHeight, 900);
  });

  test("invalid page sizes fall back to an A4 aspect", () {
    final broken = layout(const [Size(0, 0), Size(100, double.infinity)]);
    expect(broken.pageHeight(0), closeTo(368 * 1.414, 0.01));
    expect(broken.pageHeight(1), closeTo(368 * 1.414, 0.01));
  });

  test("pageAt resolves boundaries and out-of-range positions", () {
    final pages = layout(const [Size(1, 1), Size(1, 1), Size(1, 1)]);
    expect(pages.offsets, [100, 480, 860, 1240]);
    expect(pages.pageAt(-50), 0);
    expect(pages.pageAt(479.9), 0);
    expect(pages.pageAt(480), 1);
    expect(pages.pageAt(859.9), 1);
    expect(pages.pageAt(860), 2);
    expect(pages.pageAt(99999), 2);
  });

  test("visibleRange adds the margin and clamps to the document", () {
    final pages = layout(List.filled(10, const Size(1, 1)));
    expect(pages.visibleRange(0, 10), (0, 1));
    expect(pages.visibleRange(1300, 1500), (2, 4));
    expect(pages.visibleRange(3500, 99999), (7, 9));
    expect(pages.visibleRange(1300, 1500, margin: 0), (3, 3));
  });

  test("currentPage is the page with the largest visible fraction", () {
    final pages = layout(const [Size(1, 2.5), Size(4, 1)]);
    expect(pages.offsets, [100, 1032, 1136]);
    expect(pages.currentPage(0, 800), 0);
    expect(pages.currentPage(344, 1144), 1);

    final equal = layout(List.filled(3, const Size(1, 1)));
    expect(equal.currentPage(0, 800), 0);
    expect(equal.currentPage(300, 1100), 1);
    expect(equal.currentPage(700, 1500), 2);
  });

  test("clampTranslationY keeps the content inside the viewport", () {
    final pages = layout(const [Size(100, 200), Size(200, 100)]);
    expect(pages.clampTranslationY(10, 1), 0);
    expect(pages.clampTranslationY(-500, 1), -252);
    expect(pages.clampTranslationY(-1500, 2), -1304);
  });

  test("renderWidth follows pixel ratio and zoom until the pixel cap", () {
    final pages = layout(const [Size(100, 200), Size(400, 100)]);
    expect(
      pages.renderWidth(0, pixelRatio: 3, scale: 1, maxPixels: 100000000),
      1104,
    );
    expect(
      pages.renderWidth(0, pixelRatio: 3, scale: 4, maxPixels: 100000000),
      4416,
    );
    final capped = pages.renderWidth(
      0,
      pixelRatio: 3,
      scale: 4,
      maxPixels: 8000000,
    );
    expect(capped, 2000);
    expect(pages.renderHeight(0, capped), 4000);
    expect(pages.renderHeight(1, 400), 100);
  });

  test("zoom buckets round up within the scale range", () {
    expect(PdfPageLayout.zoomBucket(0.5, maxScale: 5), 1);
    expect(PdfPageLayout.zoomBucket(1, maxScale: 5), 1);
    expect(PdfPageLayout.zoomBucket(1.2, maxScale: 5), 2);
    expect(PdfPageLayout.zoomBucket(4.01, maxScale: 5), 5);
    expect(PdfPageLayout.zoomBucket(9, maxScale: 5), 5);
  });
}
