import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ui/extents_page_view.dart';

void main() {
  testWidgets('a short drag opens settings without moving the gallery', (
    tester,
  ) async {
    final controller = PageController();
    final scaffold = await _pumpGallery(tester, controller);

    final gesture = await tester.startGesture(const Offset(150, 250));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(14, 0));
    expect(scaffold.isDrawerOpen, isFalse);

    await gesture.moveBy(const Offset(1, 0));
    expect(scaffold.isDrawerOpen, isTrue);
    expect(controller.offset, 0);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('flinging from Albums to Home keeps settings closed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PageController(initialPage: 1);
    final scaffold = await _pumpGallery(tester, controller);

    await tester.flingFrom(const Offset(4, 250), const Offset(390, 0), 7000);
    expect(controller.offset, greaterThan(0));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(controller.page, 0);
    expect(scaffold.isDrawerOpen, isFalse);
  });
}

Future<ScaffoldState> _pumpGallery(
  WidgetTester tester,
  PageController controller,
) async {
  addTearDown(controller.dispose);
  final scaffoldKey = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawer: const Drawer(),
        drawerEnableOpenDragGesture: false,
        body: ExtentsPageView(
          controller: controller,
          physics: const NoLeftBounceScrollPhysics(),
          openDrawer: () => scaffoldKey.currentState!.openDrawer(),
          children: [
            ListView(children: const [SizedBox(height: 1000)]),
            const SizedBox.expand(),
          ],
        ),
      ),
    ),
  );
  return scaffoldKey.currentState!;
}
