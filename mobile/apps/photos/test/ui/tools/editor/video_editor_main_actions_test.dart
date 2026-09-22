import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_main_actions.dart';

void main() {
  testWidgets('spaces actions across the available editor width', (
    tester,
  ) async {
    const firstKey = Key('first');
    const secondKey = Key('second');
    const thirdKey = Key('third');
    const fourthKey = Key('fourth');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: VideoEditorMainActions(
              children: [
                SizedBox(key: firstKey, width: 90, height: 60),
                SizedBox(key: secondKey, width: 90, height: 60),
                SizedBox(key: thirdKey, width: 90, height: 60),
                SizedBox(key: fourthKey, width: 90, height: 60),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(firstKey)).dx, 0);
    expect(tester.getTopLeft(find.byKey(secondKey)).dx, 170);
    expect(tester.getTopLeft(find.byKey(thirdKey)).dx, 340);
    expect(tester.getTopLeft(find.byKey(fourthKey)).dx, 510);
  });
}
