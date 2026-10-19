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
