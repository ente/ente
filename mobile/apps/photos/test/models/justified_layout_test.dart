import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/gallery/justified_layout.dart";

void main() {
  group("JustifiedLayoutCalculator", () {
    test("uses a square fallback for missing or invalid dimensions", () {
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(0, 0), 1);
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(0, 100), 1);
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(100, 0), 1);
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(-100, 50), 1);
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(100, -50), 1);
    });

    test("preserves normal ratios and clamps extreme dimensions", () {
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(4, 3), 4 / 3);
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(1, 100), 1 / 3);
      expect(JustifiedLayoutCalculator.aspectRatioForDimensions(100, 1), 4);
    });

    test("justified rows conserve the full available width", () {
      const availableWidth = 400.0;
      const spacing = 2.0;
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [1, 1, 1],
        availableWidth: availableWidth,
        targetRowHeight: 100,
        spacing: spacing,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.itemWidths, hasLength(3));
      expect(_occupiedWidth(row, spacing), closeTo(availableWidth, 1e-9));
    });

    test("a two-item final row expands to the full available width", () {
      const availableWidth = 400.0;
      const spacing = 2.0;
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [1, 1],
        availableWidth: availableWidth,
        targetRowHeight: 100,
        spacing: spacing,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.itemWidths, hasLength(2));
      expect(row.itemWidths, everyElement(row.height));
      expect(_occupiedWidth(row, spacing), closeTo(availableWidth, 1e-9));
    });

    test("caps wide final-row growth and leaves trailing space", () {
      for (final testCase in const [
        (width: 744.0, ratios: [0.75, 0.75]),
        (width: 1024.0, ratios: [0.75, 0.75, 0.75]),
      ]) {
        final row = JustifiedLayoutCalculator.computeRows(
          aspectRatios: testCase.ratios,
          availableWidth: testCase.width,
          targetRowHeight: 320,
          spacing: 2,
        ).single;

        expect(row.height, 400, reason: "available width ${testCase.width}");
        expect(
          _occupiedWidth(row, 2),
          lessThan(testCase.width),
          reason: "available width ${testCase.width}",
        );
      }
    });

    test("sizes final singletons by orientation and caps extremes", () {
      JustifiedRowLayout rowFor(
        double ratio, {
        double width = 402,
        double targetHeight = 200,
      }) {
        return JustifiedLayoutCalculator.computeRows(
          aspectRatios: [ratio],
          availableWidth: width,
          targetRowHeight: targetHeight,
          spacing: 2,
        ).single;
      }

      final portrait = rowFor(9 / 16);
      final extremePortrait = rowFor(0.25);
      final landscape = rowFor(3 / 2);
      final mediumPortrait = rowFor(0.5, width: 744, targetHeight: 320);
      final minimumTappablePortrait = rowFor(
        0.25,
        width: 600,
        targetHeight: (600 - 10) / 6,
      );

      expect(portrait.itemWidths.single, 200);
      expect(extremePortrait.height, 200 * 2.4);
      expect(
        extremePortrait.itemWidths.single / extremePortrait.height,
        closeTo(1 / 3, 1e-9),
      );
      expect(landscape.height, 200);
      expect(mediumPortrait.height, 400);
      expect(mediumPortrait.itemWidths.single, 200);
      expect(minimumTappablePortrait.height, 144);
      expect(minimumTappablePortrait.itemWidths.single, 48);
    });

    test("rebalances a compact portrait orphan", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: List.filled(7, 9 / 16),
        availableWidth: 393,
        targetRowHeight: (393 - 2) / 2,
        spacing: 2,
      );

      expect(rows.map((row) => row.itemWidths.length), [3, 2, 2]);
    });

    test("does not create oversized tablet rows to avoid an orphan", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: List.filled(5, 0.5),
        availableWidth: 744,
        targetRowHeight: 320,
        spacing: 2,
      );

      expect(rows.map((row) => row.itemWidths.length), [4, 1]);
    });

    test("keeps a tappable portrait with the following panorama", () {
      const availableWidth = 393.0;
      const spacing = 2.0;
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [0.85, 4.0],
        availableWidth: availableWidth,
        targetRowHeight: 130,
        spacing: spacing,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.firstIndex, 0);
      expect(row.lastIndex, 1);
      expect(row.height, closeTo(391 / 4.85, 1e-9));
      expect(row.height, greaterThanOrEqualTo(48));
      expect(row.itemWidths, everyElement(greaterThanOrEqualTo(48)));
      expect(_occupiedWidth(row, spacing), closeTo(availableWidth, 1e-9));
    });

    test("does not squeeze an extreme item into a mixed row", () {
      for (final ratios in const [
        [0.25, 4.0],
        [4.0, 0.25],
      ]) {
        final rows = JustifiedLayoutCalculator.computeRows(
          aspectRatios: ratios,
          availableWidth: 430,
          targetRowHeight: 106,
          spacing: 2,
        );

        expect(rows, hasLength(2));
        expect(rows.first.lastIndex, 0);
        expect(rows.last.firstIndex, 1);
        for (final row in rows) {
          expect(row.height, greaterThanOrEqualTo(48));
          expect(row.itemWidths, everyElement(greaterThanOrEqualTo(48)));
        }
      }
    });

    test("does not make a justified row shorter than the tap target", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [4.0, 4.0],
        availableWidth: 360,
        targetRowHeight: 80,
        spacing: 2,
      );

      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.height, greaterThanOrEqualTo(48));
        expect(row.itemWidths, everyElement(greaterThanOrEqualTo(48)));
      }
    });

    test("accepts a justified row exactly at the tap target", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [1.0, 4.0],
        availableWidth: 242,
        targetRowHeight: 100,
        spacing: 2,
      );

      expect(rows, hasLength(1));
      expect(rows.single.height, 48);
      expect(rows.single.itemWidths, [48, 192]);
    });

    test("raises a sparse row to the minimum tappable height", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [4.0],
        availableWidth: 400,
        targetRowHeight: 30,
        spacing: 2,
      );

      expect(rows, hasLength(1));
      expect(rows.single.height, 48);
      expect(rows.single.itemWidths, [192]);
    });

    test("caps row density based on available width", () {
      for (final testCase in const [
        (width: 393.0, maximumItems: 3),
        (width: 599.9, maximumItems: 3),
        (width: 600.0, maximumItems: 4),
        (width: 1007.9, maximumItems: 4),
        (width: 1008.0, maximumItems: 5),
      ]) {
        final targetHeight =
            (testCase.width - 2 * (testCase.maximumItems - 1)) /
            testCase.maximumItems;
        final rows = JustifiedLayoutCalculator.computeRows(
          aspectRatios: List.filled(testCase.maximumItems * 2, 1 / 3),
          availableWidth: testCase.width,
          targetRowHeight: targetHeight,
          spacing: 2,
        );

        expect(
          rows.map((row) => row.itemWidths.length),
          [testCase.maximumItems, testCase.maximumItems],
          reason: "available width ${testCase.width}",
        );
        expect(
          rows.first.height,
          closeTo(3 * targetHeight, 1e-9),
          reason: "non-final row at width ${testCase.width}",
        );
        final expectedFinalHeight = testCase.width < 600
            ? 3 * targetHeight
            : 1.25 * targetHeight;
        expect(
          rows.last.height,
          closeTo(expectedFinalHeight, 1e-9),
          reason: "final row at width ${testCase.width}",
        );
      }
    });

    test("keeps cramped landscape rows independent of responsive cap", () {
      for (final testCase in const [
        (
          ratios: [4 / 3, 4 / 3, 4 / 3],
          width: 393.0,
          targetHeight: (393 - 4) / 3,
          rowCounts: [2, 1],
        ),
        (
          ratios: [1.0, 1.0, 1.0, 1.0],
          width: 1024.0,
          targetHeight: 320.0,
          rowCounts: [3, 1],
        ),
      ]) {
        final rows = JustifiedLayoutCalculator.computeRows(
          aspectRatios: testCase.ratios,
          availableWidth: testCase.width,
          targetRowHeight: testCase.targetHeight,
          spacing: 2,
        );

        expect(
          rows.map((row) => row.itemWidths.length),
          testCase.rowCounts,
          reason: "available width ${testCase.width}",
        );
        expect(rows.last.height, testCase.targetHeight);
      }
    });

    test("merges a final portrait with a tappable two-item row", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [1.0, 1.0, 0.5],
        availableWidth: 393,
        targetRowHeight: (393 - 2) / 2,
        spacing: 2,
      );

      expect(rows, hasLength(1));
      expect(rows.single.itemWidths, hasLength(3));
    });

    test("rebalances a wide orphan when replacement rows stay bounded", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [0.8, 0.8, 0.8, 0.4, 2.0],
        availableWidth: 600,
        targetRowHeight: 200,
        spacing: 2,
      );

      expect(rows.map((row) => row.itemWidths.length), [3, 2]);
      for (final row in rows) {
        expect(row.height, lessThanOrEqualTo(250));
        expect(_occupiedWidth(row, 2), closeTo(600, 1e-9));
      }
    });

    test("forced non-final singleton uses the target row height", () {
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [0.5, 4],
        availableWidth: 393,
        targetRowHeight: 130,
        spacing: 2,
      );

      expect(rows, hasLength(2));
      expect(rows.first.height, 130);
    });
  });

  group("JustifiedSectionLayout", () {
    const rows = [
      JustifiedRowLayout(
        firstIndex: 0,
        lastIndex: 1,
        minOffset: 0,
        height: 10,
        itemWidths: [40, 40],
      ),
      JustifiedRowLayout(
        firstIndex: 2,
        lastIndex: 2,
        minOffset: 12,
        height: 20,
        itemWidths: [80],
      ),
      JustifiedRowLayout(
        firstIndex: 3,
        lastIndex: 4,
        minOffset: 34,
        height: 30,
        itemWidths: [30, 50],
      ),
    ];
    final section = JustifiedSectionLayout(
      firstIndex: 10,
      lastIndex: 13,
      minOffset: 100,
      maxOffset: 169,
      headerExtent: 5,
      spacing: 2,
      rows: rows,
      builder: (context, index) => const SizedBox.shrink(),
    );

    test("maps header and row indices to exact layout offsets", () {
      expect(section.indexToLayoutOffset(10), 100);
      expect(section.indexToLayoutOffset(11), 105);
      expect(section.indexToLayoutOffset(12), 117);
      expect(section.indexToLayoutOffset(13), 139);
      expect(section.indexToLayoutOffset(14), 171);
    });

    test("finds the first child at row and spacing boundaries", () {
      expect(section.getMinChildIndexForScrollOffset(100), 10);
      expect(section.getMinChildIndexForScrollOffset(104.999), 10);
      expect(section.getMinChildIndexForScrollOffset(105), 11);
      expect(section.getMinChildIndexForScrollOffset(115), 11);
      expect(section.getMinChildIndexForScrollOffset(116.999), 11);
      expect(section.getMinChildIndexForScrollOffset(117), 12);
      expect(section.getMinChildIndexForScrollOffset(139), 13);
      expect(section.getMinChildIndexForScrollOffset(169), 13);
    });
  });
}

double _occupiedWidth(JustifiedRowLayout row, double spacing) {
  return row.itemWidths.fold<double>(0, (sum, width) => sum + width) +
      spacing * (row.itemWidths.length - 1);
}
