import "dart:collection";
import "dart:math" as math;
import "dart:typed_data";

import "package:photos/models/gallery/justified_layout.dart";

// Selects the minimum-cost sequence from candidate row breaks across the group.
class FlexLayoutCalculator {
  static const double _minimumTappableExtent = 48;
  static const double _defaultMaximumRowHeightFactor = 1.6;
  static const double _minimumLandscapeRowHeight = 96;
  static const int _minimumLandscapeDensityItemCount = 3;
  static const double _preferredTileWidthFactor = 0.6;
  static const double _cropPenaltyWeight = 4;

  const FlexLayoutCalculator._();

  static List<JustifiedRowLayout> computeRows({
    required Iterable<double> aspectRatios,
    required double availableWidth,
    required double targetRowHeight,
    required double spacing,
    required double minimumNonFinalSingletonAspectRatio,
    double maximumRowHeightFactor = _defaultMaximumRowHeightFactor,
  }) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      throw ArgumentError.value(availableWidth, "availableWidth");
    }
    if (!targetRowHeight.isFinite || targetRowHeight <= 0) {
      throw ArgumentError.value(targetRowHeight, "targetRowHeight");
    }
    if (!spacing.isFinite || spacing < 0) {
      throw ArgumentError.value(spacing, "spacing");
    }
    if (!maximumRowHeightFactor.isFinite || maximumRowHeightFactor < 1) {
      throw ArgumentError.value(
        maximumRowHeightFactor,
        "maximumRowHeightFactor",
      );
    }
    if (!minimumNonFinalSingletonAspectRatio.isFinite ||
        minimumNonFinalSingletonAspectRatio <= 0) {
      throw ArgumentError.value(
        minimumNonFinalSingletonAspectRatio,
        "minimumNonFinalSingletonAspectRatio",
      );
    }

    final ratios = Float64List.fromList(aspectRatios.toList(growable: false));
    if (ratios.isEmpty) return const [];
    for (var i = 0; i < ratios.length; i++) {
      final ratio = ratios[i];
      ratios[i] = ratio.isFinite && ratio > 0
          ? ratio.clamp(1 / 3, 4).toDouble()
          : 1;
    }

    final count = ratios.length;
    final costs = Float64List(count + 1)..fillRange(0, count, double.infinity);
    final nextBreak = Uint32List(count);
    final maximumHeight = math.max(
      _minimumTappableExtent,
      targetRowHeight * maximumRowHeightFactor,
    );
    final preferredTileWidth = targetRowHeight * _preferredTileWidthFactor;

    for (var start = count - 1; start >= 0; start--) {
      var ratioSum = 0.0;
      var minimumRatio = double.infinity;
      for (var end = start; end < count; end++) {
        ratioSum += ratios[end];
        minimumRatio = math.min(minimumRatio, ratios[end]);
        final itemCount = end - start + 1;
        final contentWidth = availableWidth - spacing * (itemCount - 1);
        if (contentWidth < itemCount * _minimumTappableExtent) break;

        final isTail = end == count - 1;
        if (!isTail &&
            itemCount == 1 &&
            ratios[start] < minimumNonFinalSingletonAspectRatio) {
          continue;
        }
        final geometry = _rowGeometry(
          ratios: ratios,
          start: start,
          end: end + 1,
          ratioSum: ratioSum,
          minimumRatio: minimumRatio,
          contentWidth: contentWidth,
          maximumHeight: maximumHeight,
          isTail: isTail,
        );
        if (itemCount >= _minimumLandscapeDensityItemCount &&
            minimumRatio >= 1 &&
            geometry.height < _minimumLandscapeRowHeight) {
          continue;
        }
        final heightDeviation = math.log(geometry.height / targetRowHeight);
        final narrowness = math.max(
          0.0,
          preferredTileWidth / geometry.minimumWidth - 1,
        );
        final unusedWidthFraction = math.max(
          0.0,
          1 - geometry.occupiedWidth / contentWidth,
        );
        final singletonPenalty = itemCount == 1 && count > 1 ? 0.15 : 0.0;
        final rowCost =
            itemCount *
                (heightDeviation * heightDeviation +
                    2 * narrowness * narrowness) +
            unusedWidthFraction * unusedWidthFraction +
            _cropPenaltyWeight * geometry.cropCost +
            0.08 +
            singletonPenalty;
        final cost = rowCost + costs[end + 1];
        if (cost < costs[start] - 1e-9) {
          costs[start] = cost;
          nextBreak[start] = end + 1;
        }
      }

      if (nextBreak[start] == 0) {
        nextBreak[start] = start + 1;
        costs[start] = costs[start + 1];
      }
    }

    final rows = <JustifiedRowLayout>[];
    var offset = 0.0;
    for (var start = 0; start < count;) {
      final end = nextBreak[start];
      var ratioSum = 0.0;
      var minimumRatio = double.infinity;
      for (var i = start; i < end; i++) {
        ratioSum += ratios[i];
        minimumRatio = math.min(minimumRatio, ratios[i]);
      }
      final contentWidth = availableWidth - spacing * (end - start - 1);
      final geometry = _rowGeometry(
        ratios: ratios,
        start: start,
        end: end,
        ratioSum: ratioSum,
        minimumRatio: minimumRatio,
        contentWidth: contentWidth,
        maximumHeight: maximumHeight,
        isTail: end == count,
      );
      rows.add(
        JustifiedRowLayout(
          firstIndex: start,
          lastIndex: end - 1,
          minOffset: offset,
          height: geometry.height,
          itemWidths: UnmodifiableListView(
            _itemWidths(
              ratios: ratios,
              start: start,
              end: end,
              contentWidth: contentWidth,
              geometry: geometry,
            ),
          ),
        ),
      );
      offset += geometry.height + spacing;
      start = end;
    }
    return UnmodifiableListView(rows);
  }

  static _FlexRowGeometry _rowGeometry({
    required Float64List ratios,
    required int start,
    required int end,
    required double ratioSum,
    required double minimumRatio,
    required double contentWidth,
    required double maximumHeight,
    required bool isTail,
  }) {
    final naturalHeight = contentWidth / ratioSum;
    final height = naturalHeight.clamp(_minimumTappableExtent, maximumHeight);
    if (isTail && naturalHeight > maximumHeight) {
      final minimumWidth = minimumRatio * height;
      if (minimumWidth >= _minimumTappableExtent) {
        return _FlexRowGeometry(
          height: height,
          scale: 1,
          pinnedRatioCeiling: 0,
          fillsWidth: false,
          occupiedWidth: ratioSum * height,
          minimumWidth: minimumWidth,
          cropCost: 0,
        );
      }
      var occupiedWidth = 0.0;
      var croppedMinimumWidth = double.infinity;
      var cropCost = 0.0;
      for (var i = start; i < end; i++) {
        final naturalWidth = ratios[i] * height;
        final width = math.max(_minimumTappableExtent, naturalWidth);
        occupiedWidth += width;
        croppedMinimumWidth = math.min(croppedMinimumWidth, width);
        final ratioDeviation = math.log(width / height / ratios[i]);
        cropCost += ratioDeviation * ratioDeviation;
      }
      if (occupiedWidth <= contentWidth) {
        return _FlexRowGeometry(
          height: height,
          scale: 1,
          pinnedRatioCeiling: _minimumTappableExtent / height,
          fillsWidth: false,
          occupiedWidth: occupiedWidth,
          minimumWidth: croppedMinimumWidth,
          cropCost: cropCost,
        );
      }
    }

    return _filledRowGeometry(
      ratios: ratios,
      start: start,
      end: end,
      ratioSum: ratioSum,
      minimumRatio: minimumRatio,
      contentWidth: contentWidth,
      height: height,
    );
  }

  static _FlexRowGeometry _filledRowGeometry({
    required Float64List ratios,
    required int start,
    required int end,
    required double ratioSum,
    required double minimumRatio,
    required double contentWidth,
    required double height,
  }) {
    final uncroppedScale = contentWidth / (height * ratioSum);
    final uncroppedMinimumWidth = minimumRatio * height * uncroppedScale;
    if (uncroppedMinimumWidth >= _minimumTappableExtent) {
      final ratioDeviation = math.log(uncroppedScale);
      return _FlexRowGeometry(
        height: height,
        scale: uncroppedScale,
        pinnedRatioCeiling: 0,
        fillsWidth: true,
        occupiedWidth: contentWidth,
        minimumWidth: uncroppedMinimumWidth,
        cropCost: (end - start) * ratioDeviation * ratioDeviation,
      );
    }

    var pinnedRatioCeiling = 0.0;
    var pinnedCount = 0;
    var activeRatioSum = ratioSum;
    var remainingWidth = contentWidth;
    var scale = remainingWidth / (height * activeRatioSum);

    // Pin undersized slots, then redistribute the remaining row width.
    while (pinnedCount < end - start) {
      final nextPinnedRatioCeiling = _minimumTappableExtent / (height * scale);
      var newlyPinnedCount = 0;
      var newlyPinnedRatioSum = 0.0;
      for (var i = start; i < end; i++) {
        final ratio = ratios[i];
        if (ratio >= pinnedRatioCeiling && ratio < nextPinnedRatioCeiling) {
          newlyPinnedCount++;
          newlyPinnedRatioSum += ratio;
        }
      }
      if (newlyPinnedCount == 0) break;
      pinnedRatioCeiling = nextPinnedRatioCeiling;
      pinnedCount += newlyPinnedCount;
      activeRatioSum -= newlyPinnedRatioSum;
      remainingWidth -= newlyPinnedCount * _minimumTappableExtent;
      if (activeRatioSum <= 0) {
        scale = 0;
        break;
      }
      scale = remainingWidth / (height * activeRatioSum);
    }

    var minimumWidth = double.infinity;
    var cropCost = 0.0;
    for (var i = start; i < end; i++) {
      final width = ratios[i] < pinnedRatioCeiling
          ? _minimumTappableExtent
          : ratios[i] * height * scale;
      minimumWidth = math.min(minimumWidth, width);
      final ratioDeviation = math.log(width / height / ratios[i]);
      cropCost += ratioDeviation * ratioDeviation;
    }
    return _FlexRowGeometry(
      height: height,
      scale: scale,
      pinnedRatioCeiling: pinnedRatioCeiling,
      fillsWidth: true,
      occupiedWidth: contentWidth,
      minimumWidth: minimumWidth,
      cropCost: cropCost,
    );
  }

  static List<double> _itemWidths({
    required Float64List ratios,
    required int start,
    required int end,
    required double contentWidth,
    required _FlexRowGeometry geometry,
  }) {
    final widths = List<double>.generate(end - start, (index) {
      final ratio = ratios[start + index];
      return ratio < geometry.pinnedRatioCeiling
          ? _minimumTappableExtent
          : ratio * geometry.height * geometry.scale;
    }, growable: false);
    if (geometry.fillsWidth && widths.isNotEmpty) {
      final precedingWidth = widths
          .take(widths.length - 1)
          .fold<double>(0, (sum, width) => sum + width);
      widths[widths.length - 1] = math.max(
        _minimumTappableExtent,
        contentWidth - precedingWidth,
      );
    }
    return widths;
  }
}

class _FlexRowGeometry {
  final double height;
  final double scale;
  final double pinnedRatioCeiling;
  final bool fillsWidth;
  final double occupiedWidth;
  final double minimumWidth;
  final double cropCost;

  const _FlexRowGeometry({
    required this.height,
    required this.scale,
    required this.pinnedRatioCeiling,
    required this.fillsWidth,
    required this.occupiedWidth,
    required this.minimumWidth,
    required this.cropCost,
  });
}
