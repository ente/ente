import "package:photos/models/gallery/section_layout.dart";

class FixedExtentSectionLayout extends SectionLayout {
  final double tileHeight;
  final double mainAxisStride;

  const FixedExtentSectionLayout({
    required super.firstIndex,
    required super.lastIndex,
    required super.minOffset,
    required super.maxOffset,
    required super.headerExtent,
    required this.tileHeight,
    required super.spacing,
    required super.builder,
  }) : mainAxisStride = tileHeight + spacing;

  @override
  double indexToLayoutOffset(int index) {
    index -= bodyFirstIndex;
    if (index < 0) return minOffset;
    return bodyMinOffset + index * mainAxisStride;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    scrollOffset -= bodyMinOffset;
    if (mainAxisStride == 0 || !scrollOffset.isFinite || scrollOffset < 0) {
      return firstIndex;
    }

    return bodyFirstIndex + scrollOffset ~/ mainAxisStride;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    scrollOffset -= bodyMinOffset;
    if (mainAxisStride == 0 || !scrollOffset.isFinite || scrollOffset < 0) {
      return firstIndex;
    }
    return bodyFirstIndex + (scrollOffset / mainAxisStride).ceil() - 1;
  }
}
