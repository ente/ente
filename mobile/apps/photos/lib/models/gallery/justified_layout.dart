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
  static const double _maximumWideFinalRowHeightFactor = 1.25;
  static const double _minimumLandscapeRowHeightFactor = 0.88;
  static const double _mediumWidthBreakpoint = 600;
  static const double _expandedWidthBreakpoint = 1008;
  // Product decision: cap visual density based on the available gallery width,
  // independently of tap-target sizing.
  static const int _compactMaximumItemsPerRow = 3;
  static const int _mediumMaximumItemsPerRow = 4;
  static const int _expandedMaximumItemsPerRow = 5;
  static const int _minimumLandscapeDensityItemCount = 3;
  // Logical pixels map to density-independent tap extents on both platforms.
  static const double _minimumTappableExtent = 48.0;

  const JustifiedLayoutCalculator._();

  static double aspectRatioForDimensions(int width, int height) {
    if (width <= 0 || height <= 0) return 1;
    return (width / height)
        .clamp(_minimumAspectRatio, _maximumAspectRatio)
        .toDouble();
  }

  static int _maximumItemsPerRowFor(double availableWidth) {
    if (availableWidth < _mediumWidthBreakpoint) {
      return _compactMaximumItemsPerRow;
    }
    if (availableWidth < _expandedWidthBreakpoint) {
      return _mediumMaximumItemsPerRow;
    }
    return _expandedMaximumItemsPerRow;
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
    final maximumItemsPerRow = _maximumItemsPerRowFor(availableWidth);
    // Product decision: on wider galleries, prefer a partial final row over
    // enlarging its items by more than 25%. Compact layouts retain their
    // existing tail treatment.
    final limitsFinalRowGrowth = availableWidth >= _mediumWidthBreakpoint;
    final maximumFinalRowHeightFactor = limitsFinalRowGrowth
        ? _maximumWideFinalRowHeightFactor
        : _maximumRowHeightFactor;
    final maximumFinalRowHeight = targetRowHeight * maximumFinalRowHeightFactor;
    final lastCommittedRatios = <double>[];
    var pendingRatioSum = 0.0;
    var pendingMinimumRatio = double.infinity;
    var pendingFirstIndex = 0;
    var rowOffset = 0.0;

    double widthWithoutGaps(int itemCount) =>
        math.max(1, availableWidth - spacing * (itemCount - 1));

    void addPendingRow({
      required bool fillWidth,
      double raggedHeightFactor = 1,
    }) {
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
              math.max(
                targetRowHeight * raggedHeightFactor,
                minimumTappableHeight,
              ),
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
      lastCommittedRatios
        ..clear()
        ..addAll(pendingRatios);
      rowOffset += height + spacing;
      pendingFirstIndex += pendingRatios.length;
      pendingRatios.clear();
      pendingRatioSum = 0;
      pendingMinimumRatio = double.infinity;
    }

    bool canJustifyFinalRow(List<double> ratios) {
      final ratioSum = ratios.fold<double>(0, (sum, ratio) => sum + ratio);
      final height = widthWithoutGaps(ratios.length) / ratioSum;
      final minimumWidth =
          height * ratios.reduce((left, right) => math.min(left, right));
      final isTappableAndBounded =
          height >= _minimumTappableExtent &&
          height <= maximumFinalRowHeight &&
          minimumWidth >= _minimumTappableExtent;
      if (!isTappableAndBounded) return false;

      return ratios.length < _minimumLandscapeDensityItemCount ||
          ratios.any((ratio) => ratio < 1) ||
          height >= targetRowHeight * _minimumLandscapeRowHeightFactor;
    }

    void replacePendingRatios(Iterable<double> ratios) {
      pendingRatios
        ..clear()
        ..addAll(ratios);
      pendingRatioSum = pendingRatios.fold<double>(
        0,
        (sum, ratio) => sum + ratio,
      );
      pendingMinimumRatio = pendingRatios.fold<double>(
        double.infinity,
        (minimum, ratio) => math.min(minimum, ratio),
      );
    }

    void rewindLastRow() {
      final removedRow = rows.removeLast();
      rowOffset = removedRow.minOffset;
      pendingFirstIndex = removedRow.firstIndex;
    }

    for (final rawRatio in aspectRatios) {
      // Reaching the item cap only proves that a row is non-final once another
      // item arrives. An exact-cap group tail still uses the final-row policy.
      if (pendingRatios.length == maximumItemsPerRow) {
        addPendingRow(fillWidth: true);
      }

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
        final violatesTapTarget =
            candidateHeight < _minimumTappableExtent ||
            candidateMinimumWidth < _minimumTappableExtent;
        final violatesLandscapeDensity =
            candidateCount >= _minimumLandscapeDensityItemCount &&
            pendingMinimumRatio >= 1 &&
            ratio >= 1 &&
            candidateHeight <
                targetRowHeight * _minimumLandscapeRowHeightFactor;

        if (violatesTapTarget || violatesLandscapeDensity) {
          final leaveSingletonRagged = pendingRatios.length == 1;
          addPendingRow(
            fillWidth:
                !leaveSingletonRagged && currentHeight <= maximumRowHeight,
          );
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

    // Compact galleries retain the established behavior of filling a row that
    // ends exactly at their item cap. Wider galleries defer it to the bounded
    // final-row treatment below.
    if (!limitsFinalRowGrowth && pendingRatios.length == maximumItemsPerRow) {
      addPendingRow(fillWidth: true);
    }

    // Product decision: avoid one-item group tails by rebalancing the preceding
    // row when the replacement rows meet tap-target, height, and density limits.
    if (pendingRatios.length == 1 && rows.isNotEmpty) {
      final tailRatios = <double>[...lastCommittedRatios, pendingRatios.single];
      if (lastCommittedRatios.length < maximumItemsPerRow &&
          canJustifyFinalRow(tailRatios)) {
        rewindLastRow();
        replacePendingRatios(tailRatios);
        addPendingRow(fillWidth: true);
      } else if (tailRatios.length >= 4) {
        final firstRowItemCount = (tailRatios.length + 1) ~/ 2;
        final firstRow = tailRatios.sublist(0, firstRowItemCount);
        final secondRow = tailRatios.sublist(firstRowItemCount);
        if (canJustifyFinalRow(firstRow) && canJustifyFinalRow(secondRow)) {
          rewindLastRow();
          replacePendingRatios(firstRow);
          addPendingRow(fillWidth: true);
          replacePendingRatios(secondRow);
          addPendingRow(fillWidth: true);
        }
      }
    }

    if (pendingRatios.isNotEmpty) {
      final shouldJustifyFinalRow = canJustifyFinalRow(pendingRatios);
      final singletonHeightFactor =
          pendingRatios.length == 1 && pendingRatios.single < 1
          ? math.min(_maximumRowHeightFactor, 1 / pendingRatios.single)
          : 1.0;
      final finalRowHeightFactor = pendingRatios.length == 1
          ? math.min(singletonHeightFactor, maximumFinalRowHeightFactor)
          : limitsFinalRowGrowth
          ? maximumFinalRowHeightFactor
          : 1.0;
      addPendingRow(
        fillWidth: pendingRatios.length > 1 && shouldJustifyFinalRow,
        // Give compact portrait singletons roughly one target-width column;
        // wider tails also obey their 25% growth limit.
        raggedHeightFactor: finalRowHeightFactor,
      );
    }
    return UnmodifiableListView(rows);
  }
}
