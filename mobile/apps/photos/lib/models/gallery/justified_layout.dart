import "dart:collection";
import "dart:math" as math;

import "package:photos/models/gallery/section_layout.dart";

class JustifiedRowLayout {
  final int firstIndex;
  final int lastIndex;
  final double minOffset;
  final double height;
  final List<double> itemWidths;

  const JustifiedRowLayout({
    required this.firstIndex,
    required this.lastIndex,
    required this.minOffset,
    required this.height,
    required this.itemWidths,
  });

  double get maxOffset => minOffset + height;
}

class JustifiedSectionLayout extends SectionLayout {
  final List<JustifiedRowLayout> rows;

  const JustifiedSectionLayout({
    required super.firstIndex,
    required super.lastIndex,
    required super.minOffset,
    required super.maxOffset,
    required super.headerExtent,
    required super.spacing,
    required super.builder,
    required this.rows,
  });

  @override
  double indexToLayoutOffset(int index) {
    index -= bodyFirstIndex;
    if (index < 0) return minOffset;
    if (index >= rows.length) return maxOffset + spacing;
    return bodyMinOffset + rows[index].minOffset;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    final bodyOffset = scrollOffset - bodyMinOffset;
    if (bodyOffset < 0 || rows.isEmpty) return firstIndex;
    return bodyFirstIndex + _lastRowStartingAtOrBefore(bodyOffset);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    final bodyOffset = scrollOffset - bodyMinOffset;
    if (bodyOffset <= 0 || rows.isEmpty) return firstIndex;
    return bodyFirstIndex + _lastRowStartingBefore(bodyOffset);
  }

  int _lastRowStartingAtOrBefore(double offset) {
    if (!offset.isFinite) return rows.length - 1;
    var low = 0;
    var high = rows.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >>> 1;
      if (rows[mid].minOffset <= offset) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  int _lastRowStartingBefore(double offset) {
    if (!offset.isFinite) return rows.length - 1;
    var low = 0;
    var high = rows.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >>> 1;
      if (rows[mid].minOffset < offset) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}

class JustifiedLayoutCalculator {
  static const double _minimumAspectRatio = 1 / 3;
  static const double _maximumAspectRatio = 4.0;
  static const double _maximumRowHeightFactor = 2.4;
  // Logical pixels map to density-independent tap extents on both platforms.
  static const double _minimumTappableExtent = 48.0;

  const JustifiedLayoutCalculator._();

  static double aspectRatioForDimensions(int width, int height) {
    if (width <= 0 || height <= 0) return 1;
    return (width / height)
        .clamp(_minimumAspectRatio, _maximumAspectRatio)
        .toDouble();
  }

  static List<JustifiedRowLayout> computeRows({
    required Iterable<double> aspectRatios,
    required double availableWidth,
    required double targetRowHeight,
    required double spacing,
  }) {
    if (aspectRatios.isEmpty) return const [];
    if (!availableWidth.isFinite || availableWidth <= 0) {
      throw ArgumentError.value(availableWidth, "availableWidth");
    }
    if (!targetRowHeight.isFinite || targetRowHeight <= 0) {
      throw ArgumentError.value(targetRowHeight, "targetRowHeight");
    }
    if (!spacing.isFinite || spacing < 0) {
      throw ArgumentError.value(spacing, "spacing");
    }

    final rows = <JustifiedRowLayout>[];
    final pendingRatios = <double>[];
    final maximumRowHeight = targetRowHeight * _maximumRowHeightFactor;
    var pendingRatioSum = 0.0;
    var pendingMinimumRatio = double.infinity;
    var pendingFirstIndex = 0;
    var rowOffset = 0.0;

    double widthWithoutGaps(int itemCount) =>
        math.max(1, availableWidth - spacing * (itemCount - 1));

    void addPendingRow({required bool fillWidth}) {
      if (pendingRatios.isEmpty) return;
      final contentWidth = widthWithoutGaps(pendingRatios.length);
      final fittedHeight = contentWidth / pendingRatioSum;
      final minimumTappableHeight = math.max(
        _minimumTappableExtent,
        _minimumTappableExtent / pendingMinimumRatio,
      );
      final height = fillWidth
          ? fittedHeight
          : math.min(
              fittedHeight,
              math.max(targetRowHeight, minimumTappableHeight),
            );
      final widths = pendingRatios
          .map((ratio) => ratio * height)
          .toList(growable: false);

      if (fillWidth && widths.isNotEmpty) {
        final precedingWidth = widths
            .take(widths.length - 1)
            .fold<double>(0, (sum, width) => sum + width);
        widths[widths.length - 1] = math.max(0, contentWidth - precedingWidth);
      }

      rows.add(
        JustifiedRowLayout(
          firstIndex: pendingFirstIndex,
          lastIndex: pendingFirstIndex + pendingRatios.length - 1,
          minOffset: rowOffset,
          height: height,
          itemWidths: UnmodifiableListView(widths),
        ),
      );
      rowOffset += height + spacing;
      pendingFirstIndex += pendingRatios.length;
      pendingRatios.clear();
      pendingRatioSum = 0;
      pendingMinimumRatio = double.infinity;
    }

    for (final rawRatio in aspectRatios) {
      final ratio = rawRatio.isFinite && rawRatio > 0
          ? rawRatio.clamp(_minimumAspectRatio, _maximumAspectRatio).toDouble()
          : 1.0;
      if (pendingRatios.isNotEmpty) {
        final candidateCount = pendingRatios.length + 1;
        final candidateRatioSum = pendingRatioSum + ratio;
        final candidateHeight =
            widthWithoutGaps(candidateCount) / candidateRatioSum;
        final candidateMinimumWidth =
            candidateHeight * math.min(pendingMinimumRatio, ratio);
        final currentHeight =
            widthWithoutGaps(pendingRatios.length) / pendingRatioSum;
        final wouldOverCompress =
            candidateHeight < _minimumTappableExtent ||
            candidateMinimumWidth < _minimumTappableExtent;

        if (wouldOverCompress) {
          addPendingRow(fillWidth: currentHeight <= maximumRowHeight);
        }
      }

      pendingRatios.add(ratio);
      pendingRatioSum += ratio;
      pendingMinimumRatio = math.min(pendingMinimumRatio, ratio);

      final naturalWidth =
          pendingRatioSum * targetRowHeight +
          spacing * (pendingRatios.length - 1);
      if (naturalWidth >= availableWidth) {
        addPendingRow(fillWidth: true);
      }
    }

    addPendingRow(fillWidth: false);
    return UnmodifiableListView(rows);
  }
}
