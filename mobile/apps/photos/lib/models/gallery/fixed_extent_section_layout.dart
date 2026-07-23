import 'package:flutter/material.dart';

// Used to store layout information for a section (group) in a gallery

class FixedExtentSectionLayout {
  final double tileHeight, mainAxisStride;
  final int firstIndex, lastIndex, bodyFirstIndex;
  final double minOffset, maxOffset, bodyMinOffset;
  final double headerExtent, spacing;
  final IndexedWidgetBuilder builder;

  const FixedExtentSectionLayout({
    required this.firstIndex,
    required this.lastIndex,
    required this.minOffset,
    required this.maxOffset,
    required this.headerExtent,
    required this.tileHeight,
    required this.spacing,
    required this.builder,
  }) : bodyFirstIndex = firstIndex + 1,
       bodyMinOffset = minOffset + headerExtent,
       mainAxisStride = tileHeight + spacing;

  bool hasChild(int index) => firstIndex <= index && index <= lastIndex;

  bool hasChildAtOffset(double scrollOffset) =>
      minOffset <= scrollOffset && scrollOffset <= maxOffset;

  double indexToLayoutOffset(int index) {
    index -= bodyFirstIndex;
    if (index < 0) return minOffset;
    return bodyMinOffset + index * mainAxisStride;
  }

  int getMinChildIndexForScrollOffset(double scrollOffset) {
    scrollOffset -= bodyMinOffset;
    if (mainAxisStride == 0 || !scrollOffset.isFinite || scrollOffset < 0) {
      return firstIndex;
    }

    return bodyFirstIndex + scrollOffset ~/ mainAxisStride;
  }

  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    scrollOffset -= bodyMinOffset;
    if (mainAxisStride == 0 || !scrollOffset.isFinite || scrollOffset < 0) {
      return firstIndex;
    }
    return bodyFirstIndex + (scrollOffset / mainAxisStride).ceil() - 1;
  }
}
