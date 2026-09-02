import "package:flutter/material.dart";

abstract class SectionLayout {
  final int firstIndex;
  final int lastIndex;
  final int bodyFirstIndex;
  final double minOffset;
  final double maxOffset;
  final double bodyMinOffset;
  final double headerExtent;
  final double spacing;
  final IndexedWidgetBuilder builder;

  const SectionLayout({
    required this.firstIndex,
    required this.lastIndex,
    required this.minOffset,
    required this.maxOffset,
    required this.headerExtent,
    required this.spacing,
    required this.builder,
  }) : bodyFirstIndex = firstIndex + 1,
       bodyMinOffset = minOffset + headerExtent;

  bool hasChild(int index) => firstIndex <= index && index <= lastIndex;

  bool hasChildAtOffset(double scrollOffset) =>
      minOffset <= scrollOffset && scrollOffset <= maxOffset;

  double indexToLayoutOffset(int index);

  int getMinChildIndexForScrollOffset(double scrollOffset);

  int getMaxChildIndexForScrollOffset(double scrollOffset);
}

extension SectionLayoutList<T extends SectionLayout> on List<T> {
  T? sectionForIndex(int index) {
    if (isEmpty) return null;
    var low = 0;
    var high = length - 1;
    while (low <= high) {
      final mid = (low + high) >>> 1;
      final section = this[mid];
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

  T? sectionForOffset(double scrollOffset) {
    if (isEmpty) return null;
    if (scrollOffset <= first.minOffset || scrollOffset.isNaN) return first;

    // Sections are contiguous and share their boundary offset. Resolve an
    // exact boundary to the section that starts there so callers do not
    // anchor or lay out the final row of the preceding section.
    var low = 0;
    var high = length - 1;
    var result = first;
    while (low <= high) {
      final mid = (low + high) >>> 1;
      final section = this[mid];
      if (section.minOffset <= scrollOffset) {
        result = section;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
