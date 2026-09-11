import "package:flutter_test/flutter_test.dart";
import "package:photos/models/gallery/flex_layout.dart";
import "package:photos/models/gallery/justified_layout.dart";

void main() {
  test("never creates a singleton before the final row", () {
    for (final width in [393.0, 744.0, 1024.0, 1366.0]) {
      for (final ratios in <List<double>>[
        [1.5, 0.5, 0.5],
        [4, 1 / 3, 1, 1],
        [1 / 3, 4, 1 / 3, 4, 1],
        List.filled(9, 9 / 16),
      ]) {
        final rows = _rows(ratios, width: width);

        expect(
          rows.take(rows.length - 1).map((row) => row.itemWidths.length),
          everyElement(greaterThanOrEqualTo(2)),
          reason: "width $width, ratios $ratios",
        );
        expect(rows.last.lastIndex, ratios.length - 1);
      }
    }
  });

  test(
    "full-row variant allows landscape singletons without internal gaps",
    () {
      const ratios = [16 / 9, 16 / 9, 16 / 9];
      final rows = _rows(ratios, minimumNonFinalSingletonAspectRatio: 0.75);

      expect(rows.first.itemWidths, hasLength(1));
      for (final row in rows.take(rows.length - 1)) {
        expect(_occupiedWidth(row), closeTo(402, 1e-9));
      }
    },
  );

  test("full-row variant keeps tall portraits out of non-final singletons", () {
    const ratios = [16 / 9, 9 / 16, 16 / 9, 9 / 16, 16 / 9];
    final rows = _rows(ratios, minimumNonFinalSingletonAspectRatio: 0.75);

    for (final row in rows.take(rows.length - 1)) {
      if (row.itemWidths.length == 1) {
        expect(ratios[row.firstIndex], greaterThanOrEqualTo(0.75));
      }
      expect(_occupiedWidth(row), closeTo(402, 1e-9));
    }
  });

  test("full-row variant permits a ragged portrait-only group", () {
    final row = _rows([
      9 / 16,
    ], minimumNonFinalSingletonAspectRatio: 0.75).single;

    expect(_occupiedWidth(row), lessThan(402));
  });

  test("uses adaptive cropping only when a row cannot remain tappable", () {
    final rows = _rows([4, 1 / 3, 1, 1]);
    final extremeRow = rows.first;

    expect(extremeRow.itemWidths, hasLength(2));
    expect(_occupiedWidth(extremeRow), closeTo(402, 1e-9));
    expect(extremeRow.itemWidths, everyElement(greaterThanOrEqualTo(48)));
    expect(
      extremeRow.itemWidths[1] / extremeRow.height,
      isNot(closeTo(1 / 3, 1e-9)),
    );

    final naturalRow = _rows([1, 1]).single;
    expect(
      naturalRow.itemWidths.map((width) => width / naturalRow.height),
      everyElement(closeTo(1, 1e-9)),
    );
  });

  test("conserves width at an adaptive-crop pinning threshold", () {
    final row = _rows([3.12, 0.4, 0.48], width: 404, targetHeight: 80).single;

    expect(row.itemWidths, everyElement(greaterThanOrEqualTo(48)));
    expect(_occupiedWidth(row), closeTo(404, 1e-9));
  });

  test("can exceed Comfort's item cap to avoid a portrait orphan", () {
    final rows = _rows(List.filled(4, 9 / 16));

    expect(rows, hasLength(1));
    expect(rows.single.itemWidths, hasLength(4));
    expect(_occupiedWidth(rows.single), closeTo(402, 1e-9));
  });

  test("avoids cramped landscape rows without imposing a count cap", () {
    const ratios = [0.75, 0.75, 2.0, 2.0, 2.0, 2.0, 2.0, 0.4, 0.4, 0.4];
    final compactRows = _rows(ratios, targetHeight: 224);

    for (final row in compactRows) {
      final rowRatios = ratios.sublist(row.firstIndex, row.lastIndex + 1);
      if (rowRatios.length >= 3 && rowRatios.every((ratio) => ratio >= 1)) {
        expect(row.height, greaterThanOrEqualTo(96));
      }
    }

    final moderateLandscapeRow = _rows(
      [4 / 3, 4 / 3, 4 / 3],
      width: 393,
      targetHeight: 100,
    ).single;
    expect(moderateLandscapeRow.itemWidths, hasLength(3));

    final wideLandscapeRow = _rows(
      List.filled(5, 2.0),
      width: 1024,
      targetHeight: 100,
    ).single;
    expect(wideLandscapeRow.itemWidths, hasLength(5));
  });

  test("fills a final row until its configurable maximum height", () {
    final fitted = _rows([0.75, 0.75], targetHeight: 200).single;
    expect(fitted.height, closeTo(400 / 1.5, 1e-9));
    expect(_occupiedWidth(fitted), closeTo(402, 1e-9));

    final capped = _rows([0.75, 0.75], width: 1024, targetHeight: 320).single;
    expect(capped.height, 512);
    expect(_occupiedWidth(capped), lessThan(1024));

    final relaxed = _rows(
      [0.75, 0.75],
      width: 1024,
      targetHeight: 320,
      maximumHeightFactor: 2,
    ).single;
    expect(relaxed.height, 640);
    expect(relaxed.height, greaterThan(capped.height));
  });

  test(
    "preserves order, offsets and tappable geometry across screen sizes",
    () {
      const ratios = [1 / 3, 4.0, 0.85, 4.0, 1.0, 0.75, 1.5, 0.5, 1.0];
      for (final width in [393.0, 744.0, 1024.0, 1366.0]) {
        final rows = _rows(ratios, width: width);
        var fileIndex = 0;
        var offset = 0.0;
        for (final row in rows) {
          expect(row.firstIndex, fileIndex);
          expect(row.minOffset, closeTo(offset, 1e-9));
          expect(row.height, inInclusiveRange(48, 320 * 1.6));
          expect(row.itemWidths, everyElement(greaterThanOrEqualTo(48 - 1e-9)));
          fileIndex += row.itemWidths.length;
          expect(row.lastIndex, fileIndex - 1);
          expect(_occupiedWidth(row), lessThanOrEqualTo(width + 1e-7));
          offset = row.maxOffset + 2;
        }
        expect(fileIndex, ratios.length);
      }
    },
  );

  test("normalizes invalid ratios and handles empty groups", () {
    final rows = _rows([0, double.nan, double.infinity, 0.01, 100]);

    expect(rows.last.lastIndex, 4);
    expect(
      rows.expand((row) => row.itemWidths),
      everyElement(greaterThanOrEqualTo(48)),
    );
    expect(_rows([]), isEmpty);
  });

  test("rejects invalid tuning", () {
    expect(() => _rows([1], maximumHeightFactor: 0.9), throwsArgumentError);
    expect(
      () => _rows([1], minimumNonFinalSingletonAspectRatio: 0),
      throwsArgumentError,
    );
  });
}

List<JustifiedRowLayout> _rows(
  List<double> ratios, {
  double width = 402,
  double? targetHeight,
  double maximumHeightFactor = 1.6,
  double? minimumNonFinalSingletonAspectRatio,
}) {
  return FlexLayoutCalculator.computeRows(
    aspectRatios: ratios,
    availableWidth: width,
    targetRowHeight: targetHeight ?? (width < 600 ? 200 : 320),
    spacing: 2,
    maximumRowHeightFactor: maximumHeightFactor,
    minimumNonFinalSingletonAspectRatio: minimumNonFinalSingletonAspectRatio,
  );
}

double _occupiedWidth(JustifiedRowLayout row) {
  return row.itemWidths.fold<double>(0, (sum, width) => sum + width) +
      2 * (row.itemWidths.length - 1);
}
