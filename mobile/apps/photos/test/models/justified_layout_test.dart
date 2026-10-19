import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/gallery/justified_layout.dart";

void main() {
  group("JustifiedSectionLayout", () {
    const rows = [
      JustifiedRowLayout(
        firstIndex: 0,
        lastIndex: 1,
        minOffset: 0,
        height: 10,
        itemWidths: [40, 40],
      ),
      JustifiedRowLayout(
        firstIndex: 2,
        lastIndex: 2,
        minOffset: 12,
        height: 20,
        itemWidths: [80],
      ),
      JustifiedRowLayout(
        firstIndex: 3,
        lastIndex: 4,
        minOffset: 34,
        height: 30,
        itemWidths: [30, 50],
      ),
    ];
    final section = JustifiedSectionLayout(
      firstIndex: 10,
      lastIndex: 13,
      minOffset: 100,
      maxOffset: 169,
      headerExtent: 5,
      spacing: 2,
      rows: rows,
      builder: (context, index) => const SizedBox.shrink(),
    );

    test("maps header and row indices to exact layout offsets", () {
      expect(section.indexToLayoutOffset(10), 100);
      expect(section.indexToLayoutOffset(11), 105);
      expect(section.indexToLayoutOffset(12), 117);
      expect(section.indexToLayoutOffset(13), 139);
      expect(section.indexToLayoutOffset(14), 171);
    });

    test("finds the first child at row and spacing boundaries", () {
      expect(section.getMinChildIndexForScrollOffset(100), 10);
      expect(section.getMinChildIndexForScrollOffset(104.999), 10);
      expect(section.getMinChildIndexForScrollOffset(105), 11);
      expect(section.getMinChildIndexForScrollOffset(115), 11);
      expect(section.getMinChildIndexForScrollOffset(116.999), 11);
      expect(section.getMinChildIndexForScrollOffset(117), 12);
      expect(section.getMinChildIndexForScrollOffset(139), 13);
      expect(section.getMinChildIndexForScrollOffset(169), 13);
    });
  });
}
