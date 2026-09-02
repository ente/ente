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
        aspectRatios: const [1, 1, 1, 1],
        availableWidth: availableWidth,
        targetRowHeight: 100,
        spacing: spacing,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      final occupiedWidth =
          row.itemWidths.fold<double>(0, (sum, width) => sum + width) +
          spacing * (row.itemWidths.length - 1);
      expect(occupiedWidth, closeTo(availableWidth, 1e-9));
      expect(row.itemWidths, everyElement(closeTo(98.5, 1e-9)));
    });

    test("an already-tappable final row stays at the target height", () {
      const availableWidth = 400.0;
      const targetRowHeight = 100.0;
      const spacing = 2.0;
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [1, 1],
        availableWidth: availableWidth,
        targetRowHeight: targetRowHeight,
        spacing: spacing,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.height, targetRowHeight);
      expect(row.itemWidths, everyElement(row.height));
      final occupiedWidth =
          row.itemWidths.fold<double>(0, (sum, width) => sum + width) + spacing;
      expect(occupiedWidth, lessThanOrEqualTo(availableWidth));
    });

    test("a sparse portrait final row remains ragged and tappable", () {
      const availableWidth = 400.0;
      const targetRowHeight = 100.0;
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: const [0.25],
        availableWidth: availableWidth,
        targetRowHeight: targetRowHeight,
        spacing: 2,
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.height, 144);
      expect(row.itemWidths.single / row.height, closeTo(1 / 3, 1e-9));
      expect(row.itemWidths.single, closeTo(48, 1e-9));
      expect(row.itemWidths.single, lessThan(availableWidth));
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
      final occupiedWidth =
          row.itemWidths.fold<double>(0, (sum, width) => sum + width) + spacing;
      expect(occupiedWidth, closeTo(availableWidth, 1e-9));
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
