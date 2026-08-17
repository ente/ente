import 'package:flutter/material.dart';

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

extension FixedExtentSectionLayoutList on List<FixedExtentSectionLayout> {
  FixedExtentSectionLayout? sectionForIndex(int index) {
    if (isEmpty) return null;
    int low = 0;
    int high = length - 1;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final FixedExtentSectionLayout section = this[mid];
      if (index < section.firstIndex) {
        high = mid - 1;
      } else if (index > section.lastIndex) {
        low = mid + 1;
      } else {
        return section;
      }
    }
    return null;
  }

  FixedExtentSectionLayout? sectionForOffset(double scrollOffset) {
    if (isEmpty) return null;
    int low = 0;
    int high = length - 1;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final FixedExtentSectionLayout section = this[mid];
      if (scrollOffset < section.minOffset) {
        high = mid - 1;
      } else if (scrollOffset > section.maxOffset) {
        low = mid + 1;
      } else {
        return section;
      }
    }
    return last;
  }
}
