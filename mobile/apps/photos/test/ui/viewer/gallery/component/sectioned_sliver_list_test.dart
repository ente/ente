import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/gallery/justified_layout.dart";
import "package:photos/ui/viewer/gallery/component/sectioned_sliver_list.dart";

void main() {
  testWidgets(
    "a deep justified jump builds only the nearby viewport and cache rows",
    (tester) async {
      const rowCount = 100000;
      const rowHeight = 50.0;
      const headerHeight = 20.0;
      const spacing = 2.0;
      const rowStride = rowHeight + spacing;
      const deepRowIndex = 80000;
      const deepChildIndex = deepRowIndex + 1;
      final builtIndices = <int>[];
      final rows = List<JustifiedRowLayout>.generate(
        rowCount,
        (index) => JustifiedRowLayout(
          firstIndex: index,
          lastIndex: index,
          minOffset: index * rowStride,
          height: rowHeight,
          itemWidths: const [400],
        ),
        growable: false,
      );
      final section = JustifiedSectionLayout(
        firstIndex: 0,
        lastIndex: rowCount,
        minOffset: 0,
        maxOffset: headerHeight + rows.last.maxOffset,
        headerExtent: headerHeight,
        spacing: spacing,
        rows: rows,
        builder: (context, index) {
          builtIndices.add(index);
          return SizedBox(
            key: ValueKey(index),
            height: index == 0 ? headerHeight : rowHeight,
          );
        },
      );
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: CustomScrollView(
                controller: controller,
                cacheExtent: 100,
                slivers: [
                  SectionedListSliver<void>(sectionLayouts: [section]),
                ],
              ),
            ),
          ),
        ),
      );

      expect(builtIndices, contains(0));
      expect(builtIndices.length, lessThan(50));
      builtIndices.clear();

      final deepOffset = headerHeight + rows[deepRowIndex].minOffset;
      controller.jumpTo(deepOffset);
      await tester.pump();

      expect(controller.offset, deepOffset);
      expect(builtIndices, contains(deepChildIndex));
      expect(builtIndices.length, lessThan(50));
      expect(
        builtIndices,
        everyElement(
          inInclusiveRange(deepChildIndex - 20, deepChildIndex + 20),
        ),
      );

      final scrollViewOrigin = tester.getTopLeft(find.byType(CustomScrollView));
      final deepRowOrigin = tester.getTopLeft(
        find.byKey(const ValueKey(80001)),
      );
      expect(deepRowOrigin, scrollViewOrigin);
    },
  );
}
