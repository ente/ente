import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/gallery/justified_grid_row.dart";

void main() {
  testWidgets(
    "JustifiedGridRow gives children their precomputed sizes and offsets",
    (tester) async {
      const rowKey = ValueKey("row");
      const firstKey = ValueKey("first");
      const secondKey = ValueKey("second");
      const thirdKey = ValueKey("third");

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: JustifiedGridRow(
                  key: rowKey,
                  itemWidths: [60, 90, 146],
                  height: 80,
                  spacing: 2,
                  textDirection: TextDirection.ltr,
                  children: [
                    ColoredBox(key: firstKey, color: Colors.red),
                    ColoredBox(key: secondKey, color: Colors.green),
                    ColoredBox(key: thirdKey, color: Colors.blue),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final rowFinder = find.byKey(rowKey);
      final rowOrigin = tester.getTopLeft(rowFinder);
      expect(tester.getSize(rowFinder), const Size(300, 80));
      expect(tester.getSize(find.byKey(firstKey)), const Size(60, 80));
      expect(tester.getSize(find.byKey(secondKey)), const Size(90, 80));
      expect(tester.getSize(find.byKey(thirdKey)), const Size(146, 80));
      expect(tester.getTopLeft(find.byKey(firstKey)), rowOrigin);
      expect(
        tester.getTopLeft(find.byKey(secondKey)),
        rowOrigin + const Offset(62, 0),
      );
      expect(
        tester.getTopLeft(find.byKey(thirdKey)),
        rowOrigin + const Offset(154, 0),
      );
    },
  );
}
