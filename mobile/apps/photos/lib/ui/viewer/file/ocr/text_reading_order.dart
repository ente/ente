import 'dart:math';

import 'package:flutter/widgets.dart';

class TextReadingOrderBlock {
  const TextReadingOrderBlock({
    required this.index,
    required this.bounds,
    required this.text,
  });

  final int index;
  final Rect bounds;
  final String text;
}

// Read each column top to bottom. Wide headings and footers split columns into
// vertical bands.
List<int> orderTextBlocksForReading(Iterable<TextReadingOrderBlock> source) {
  final blocks = source
      .where((block) => block.bounds.width > 0 && block.bounds.height > 0)
      .toList(growable: false);
  if (blocks.length < 2) {
    return blocks.map((block) => block.index).toList(growable: false);
  }

  final rowOrder = [...blocks]..sort(_compareRows);
  final pageLeft = blocks.map((block) => block.bounds.left).reduce(min);
  final pageRight = blocks.map((block) => block.bounds.right).reduce(max);
  final pageWidth = pageRight - pageLeft;
  if (pageWidth <= 0) {
    return rowOrder.map((block) => block.index).toList(growable: false);
  }

  final widths = blocks.map((block) => block.bounds.width).toList()..sort();
  final medianWidth = widths[widths.length ~/ 2];
  final spanning =
      blocks
          .where(
            (block) =>
                block.bounds.width >= pageWidth * 0.65 &&
                block.bounds.width >= medianWidth * 1.35,
          )
          .toList()
        ..sort(_compareRows);
  final spanningIndices = spanning.map((block) => block.index).toSet();
  final columnBlocks = blocks
      .where((block) => !spanningIndices.contains(block.index))
      .toList(growable: false);

  final columns = _buildColumns(columnBlocks);
  if (!_hasParallelColumns(columns)) {
    return rowOrder.map((block) => block.index).toList(growable: false);
  }

  final isRightToLeft = _isPredominantlyRightToLeft(blocks);
  columns.sort((a, b) {
    final comparison = a.left.compareTo(b.left);
    return isRightToLeft ? -comparison : comparison;
  });
  for (final column in columns) {
    column.blocks.sort(_compareRows);
  }

  final result = <int>[];
  double bandTop = double.negativeInfinity;
  for (final separator in spanning) {
    final boundary = separator.bounds.center.dy;
    _appendColumnBand(result, columns, bandTop: bandTop, bandBottom: boundary);
    result.add(separator.index);
    bandTop = boundary;
  }
  _appendColumnBand(
    result,
    columns,
    bandTop: bandTop,
    bandBottom: double.infinity,
  );
  return result;
}

List<_TextColumn> _buildColumns(List<TextReadingOrderBlock> blocks) {
  final sorted = [...blocks]
    ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
  final columns = <_TextColumn>[];
  for (final block in sorted) {
    _TextColumn? bestColumn;
    double bestOverlap = 0;
    for (final column in columns) {
      final overlap = _horizontalOverlapRatio(block.bounds, column.bounds);
      if (overlap >= 0.2 && overlap > bestOverlap) {
        bestColumn = column;
        bestOverlap = overlap;
      }
    }
    if (bestColumn == null) {
      columns.add(_TextColumn(block));
    } else {
      bestColumn.add(block);
    }
  }
  return columns;
}

bool _hasParallelColumns(List<_TextColumn> columns) {
  if (columns.length < 2) {
    return false;
  }
  for (var first = 0; first < columns.length - 1; first++) {
    for (var second = first + 1; second < columns.length; second++) {
      final a = columns[first].bounds;
      final b = columns[second].bounds;
      final verticalOverlap = max(
        0.0,
        min(a.bottom, b.bottom) - max(a.top, b.top),
      );
      final shorterHeight = min(a.height, b.height);
      if (shorterHeight > 0 && verticalOverlap / shorterHeight >= 0.2) {
        return true;
      }
    }
  }
  return false;
}

void _appendColumnBand(
  List<int> result,
  List<_TextColumn> columns, {
  required double bandTop,
  required double bandBottom,
}) {
  for (final column in columns) {
    for (final block in column.blocks) {
      final center = block.bounds.center.dy;
      if (center >= bandTop && center < bandBottom) {
        result.add(block.index);
      }
    }
  }
}

double _horizontalOverlapRatio(Rect a, Rect b) {
  final overlap = max(0.0, min(a.right, b.right) - max(a.left, b.left));
  final shorterWidth = min(a.width, b.width);
  return shorterWidth <= 0 ? 0 : overlap / shorterWidth;
}

int _compareRows(TextReadingOrderBlock a, TextReadingOrderBlock b) {
  final verticalDiff = a.bounds.top - b.bounds.top;
  final verticalThreshold = max(a.bounds.height, b.bounds.height) * 0.25;
  if (verticalDiff.abs() > verticalThreshold) {
    return verticalDiff < 0 ? -1 : 1;
  }
  final horizontalDiff = a.bounds.left - b.bounds.left;
  if (horizontalDiff.abs() > 2) {
    return horizontalDiff < 0 ? -1 : 1;
  }
  return a.index.compareTo(b.index);
}

bool _isPredominantlyRightToLeft(List<TextReadingOrderBlock> blocks) {
  var rightToLeft = 0;
  var leftToRight = 0;
  for (final block in blocks) {
    for (final rune in block.text.runes) {
      if ((rune >= 0x0590 && rune <= 0x08ff) ||
          (rune >= 0xfb1d && rune <= 0xfdff) ||
          (rune >= 0xfe70 && rune <= 0xfefc)) {
        rightToLeft++;
      } else if ((rune >= 0x0041 && rune <= 0x005a) ||
          (rune >= 0x0061 && rune <= 0x007a)) {
        leftToRight++;
      }
    }
  }
  return rightToLeft > leftToRight;
}

class _TextColumn {
  _TextColumn(TextReadingOrderBlock block)
    : blocks = [block],
      bounds = block.bounds;

  final List<TextReadingOrderBlock> blocks;
  Rect bounds;

  double get left => bounds.left;

  void add(TextReadingOrderBlock block) {
    blocks.add(block);
    bounds = bounds.expandToInclude(block.bounds);
  }
}
