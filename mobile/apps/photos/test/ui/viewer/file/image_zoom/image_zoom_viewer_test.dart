import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";

const _viewportSize = Size(400, 400);
const _landscapeSize = Size(1200, 800);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image landscapeImage;
  late ui.Image largerLandscapeImage;

  setUpAll(() async {
    landscapeImage = await _createTestImage(_landscapeSize);
    largerLandscapeImage = await _createTestImage(const Size(2400, 1600));
  });

  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  tearDown(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  tearDownAll(() {
    landscapeImage.dispose();
    largerLandscapeImage.dispose();
  });

  group("double-tap focal zoom", () {
    testWidgets("centers the tapped horizontal area", (tester) async {
      final harness = await _pumpViewer(tester, image: landscapeImage);

      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);

      await _doubleTap(tester, harness.globalPoint(const Offset(250, 200)));

      _expectTransform(
        harness.controller,
        scale: 1.5,
        offset: const Offset(-75, 0),
      );
      expect(harness.controller.stage, ImageZoomStage.covering);
    });

    testWidgets("cycles through cover, original size, and initial", (
      tester,
    ) async {
      final harness = await _pumpViewer(tester, image: landscapeImage);
      final center = harness.globalPoint(const Offset(200, 200));

      await _doubleTap(tester, center);
      _expectTransform(harness.controller, scale: 1.5, offset: Offset.zero);
      expect(harness.controller.stage, ImageZoomStage.covering);

      await _doubleTap(tester, center);
      _expectTransform(harness.controller, scale: 3, offset: Offset.zero);
      expect(harness.controller.stage, ImageZoomStage.originalSize);

      await _doubleTap(tester, center);
      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);
      expect(harness.controller.isZoomed, isFalse);
    });

    testWidgets("a canceled second tap cannot poison the next valid tap", (
      tester,
    ) async {
      final harness = await _pumpViewer(tester, image: landscapeImage);
      final canceledPoint = harness.globalPoint(const Offset(250, 200));

      await tester.tapAt(canceledPoint);
      await tester.pump(const Duration(milliseconds: 50));
      final secondTap = await tester.startGesture(canceledPoint, pointer: 11);
      await tester.pump(const Duration(milliseconds: 16));
      await secondTap.moveBy(const Offset(60, 0));
      await secondTap.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);

      await _doubleTap(tester, harness.globalPoint(const Offset(150, 200)));

      _expectTransform(
        harness.controller,
        scale: 1.5,
        offset: const Offset(75, 0),
      );
    });

    testWidgets("single taps and long presses still reach the parent", (
      tester,
    ) async {
      var parentTapCount = 0;
      var parentLongPressCount = 0;
      final harness = await _pumpViewer(
        tester,
        image: landscapeImage,
        onParentTap: () => parentTapCount++,
        onParentLongPress: () => parentLongPressCount++,
      );
      final center = harness.globalPoint(const Offset(200, 200));

      await tester.tapAt(center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      expect(parentTapCount, 1);

      await _doubleTap(tester, harness.globalPoint(const Offset(250, 200)));

      expect(parentTapCount, 1);
      _expectTransform(
        harness.controller,
        scale: 1.5,
        offset: const Offset(-75, 0),
      );

      final longPress = await tester.startGesture(center, pointer: 12);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(parentLongPressCount, 1);
      await longPress.up();
    });

    testWidgets("a baseline pinch enables a subsequent one-finger pan", (
      tester,
    ) async {
      final harness = await _pumpViewer(tester, image: landscapeImage);
      final center = harness.globalPoint(const Offset(200, 200));
      final firstFinger = await tester.createGesture(pointer: 23);
      final secondFinger = await tester.createGesture(pointer: 24);

      await firstFinger.down(center - const Offset(40, 0));
      await secondFinger.down(center + const Offset(40, 0));
      await firstFinger.moveTo(center - const Offset(80, 0));
      await secondFinger.moveTo(center + const Offset(80, 0));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();

      _expectTransform(harness.controller, scale: 2, offset: Offset.zero);

      await tester.dragFrom(center, const Offset(80, 0));
      await tester.pumpAndSettle();

      expect(harness.controller.transform.offset.dx, greaterThan(20));
      expect(harness.controller.transform.offset.dx, lessThanOrEqualTo(200));
      expect(harness.controller.transform.scale, closeTo(2, 0.01));

      await _doubleTap(tester, center);
      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);
    });

    testWidgets("a replacement pointer rebases an active baseline pinch", (
      tester,
    ) async {
      final lockChanges = <bool>[];
      final harness = await _pumpViewer(
        tester,
        image: landscapeImage,
        onInteractionLockChanged: lockChanges.add,
      );
      final center = harness.globalPoint(const Offset(200, 200));
      final firstFinger = await tester.createGesture(pointer: 31);
      final secondFinger = await tester.createGesture(pointer: 32);
      final replacementFinger = await tester.createGesture(pointer: 33);

      await firstFinger.down(center - const Offset(40, 0));
      await secondFinger.down(center + const Offset(40, 0));
      await tester.pump();
      expect(lockChanges, <bool>[true]);

      await firstFinger.moveTo(center - const Offset(60, 0));
      await secondFinger.moveTo(center + const Offset(60, 0));
      await tester.pump();
      _expectTransform(harness.controller, scale: 1.5, offset: Offset.zero);

      await secondFinger.up();
      await tester.pump();
      expect(lockChanges.last, isTrue);

      await replacementFinger.down(center + const Offset(60, 0));
      await tester.pump();
      final beforeReplacementMove = harness.controller.transform;
      _expectTransform(harness.controller, scale: 1.5, offset: Offset.zero);

      await replacementFinger.moveTo(center + const Offset(20, 0));
      await tester.pump();
      expect(
        harness.controller.transform.scale,
        lessThan(beforeReplacementMove.scale),
      );
      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(lockChanges.last, isTrue);

      await replacementFinger.up();
      await tester.pump();
      expect(lockChanges.last, isTrue);

      await firstFinger.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(lockChanges, <bool>[true, false]);
      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);
    });
  });

  group("parent gesture handoff", () {
    testWidgets("the second pointer locks interaction before either moves", (
      tester,
    ) async {
      final lockChanges = <bool>[];
      final harness = await _pumpViewer(
        tester,
        image: landscapeImage,
        onInteractionLockChanged: lockChanges.add,
      );
      final center = harness.globalPoint(const Offset(200, 200));
      final firstFinger = await tester.createGesture(pointer: 31);
      final secondFinger = await tester.createGesture(pointer: 32);

      await firstFinger.down(center - const Offset(20, 0));
      expect(lockChanges, isEmpty);
      await secondFinger.down(center + const Offset(20, 0));

      expect(lockChanges, <bool>[true]);
      expect(harness.controller.transform, ImageZoomTransform.identity);

      await firstFinger.up();
      expect(lockChanges.last, isTrue);
      await secondFinger.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
      expect(lockChanges.last, isFalse);
    });

    testWidgets("reset restores PageView and vertical-dismiss handoff", (
      tester,
    ) async {
      var verticalDragDistance = 0.0;
      final harness = await _pumpPageHarness(
        tester,
        image: landscapeImage,
        onVerticalDragUpdate: (details) {
          verticalDragDistance += details.delta.dy;
        },
      );
      final center = harness.globalPoint(const Offset(200, 200));

      await _doubleTap(tester, center);
      expect(harness.isLocked, isTrue);
      expect(harness.pageController.page, closeTo(1, 0.01));

      await tester.dragFrom(center, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(verticalDragDistance, 0);
      expect(harness.pageController.page, closeTo(1, 0.01));

      await tester.dragFrom(center, const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(harness.pageController.page, closeTo(1, 0.01));
      _expectTransform(
        harness.zoomController,
        scale: 1.5,
        offset: const Offset(100, 0),
      );

      await harness.zoomController.reset(animated: false);
      await tester.pump();
      expect(harness.isLocked, isFalse);
      expect(harness.zoomController.transform, ImageZoomTransform.identity);

      await tester.dragFrom(center, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(verticalDragDistance, closeTo(100, 0.5));
      expect(harness.pageController.page, closeTo(1, 0.01));
      expect(harness.zoomController.transform, ImageZoomTransform.identity);

      await tester.dragFrom(center, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(harness.pageController.page, closeTo(2, 0.01));
    });
  });

  testWidgets("fling inertia stays bounded and keeps the image visible", (
    tester,
  ) async {
    final controller = ImageZoomController();
    final boundaryKey = GlobalKey();
    final viewportKey = GlobalKey();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                key: viewportKey,
                width: _viewportSize.width,
                height: _viewportSize.height,
                child: ImageZoomViewer(
                  imageProvider: _DeterministicImageProvider(landscapeImage),
                  controller: controller,
                  loadingBuilder: _emptyLoadingBuilder,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(viewportKey));
    await _doubleTap(tester, center);
    _expectTransform(controller, scale: 1.5, offset: Offset.zero);
    expect(
      await tester.runAsync(() => _centerPixel(find.byKey(boundaryKey))),
      const Color(0xFFFFFFFF),
    );

    var transformNotifications = 0;
    void onTransformChanged() => transformNotifications++;
    controller.addListener(onTransformChanged);
    addTearDown(() => controller.removeListener(onTransformChanged));

    await tester.flingFrom(center, const Offset(0, 220), 3000);
    await tester.pump(const Duration(milliseconds: 500));

    _expectTransform(controller, scale: 1.5, offset: Offset.zero);
    expect(transformNotifications, 0);
    expect(
      await tester.runAsync(() => _centerPixel(find.byKey(boundaryKey))),
      const Color(0xFFFFFFFF),
    );

    transformNotifications = 0;
    await tester.flingFrom(center, const Offset(220, 0), 3000);
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        await tester.runAsync(() => _centerPixel(find.byKey(boundaryKey))),
        const Color(0xFFFFFFFF),
      );
    }

    _expectTransform(controller, scale: 1.5, offset: const Offset(100, 0));
    expect(transformNotifications, greaterThan(0));

    await controller.reset(animated: false);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.transform, ImageZoomTransform.identity);
    expect(
      await tester.runAsync(() => _centerPixel(find.byKey(boundaryKey))),
      const Color(0xFFFFFFFF),
    );
  });

  testWidgets(
    "orientation change cancels an active animation without a stale resume",
    (tester) async {
      final controller = ImageZoomController();
      addTearDown(controller.dispose);
      final viewportKey = GlobalKey();
      final imageProvider = _DeterministicImageProvider(landscapeImage);
      final lockChanges = <bool>[];
      var viewportSize = const Size(400, 600);
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return SizedBox(
                    key: viewportKey,
                    width: viewportSize.width,
                    height: viewportSize.height,
                    child: ImageZoomViewer(
                      imageProvider: imageProvider,
                      controller: controller,
                      loadingBuilder: _emptyLoadingBuilder,
                      onInteractionLockChanged: lockChanges.add,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final initialTopLeft = tester.getTopLeft(find.byKey(viewportKey));
      await _beginDoubleTap(tester, initialTopLeft + const Offset(250, 300));
      await tester.pump(const Duration(milliseconds: 60));

      final beforeRotation = controller.transform;
      expect(beforeRotation.scale, inExclusiveRange(1, 2.25));
      expect(lockChanges, contains(true));
      final oldCenter = viewportSize.center(Offset.zero);
      final oldFittedRect = Alignment.center.inscribe(
        const Size(400, 800 / 3),
        Offset.zero & viewportSize,
      );
      final oldSceneFocus =
          oldCenter - beforeRotation.offset / beforeRotation.scale;
      final normalizedFocus = Offset(
        (oldSceneFocus.dx - oldFittedRect.left) / oldFittedRect.width,
        (oldSceneFocus.dy - oldFittedRect.top) / oldFittedRect.height,
      );

      setHostState(() => viewportSize = const Size(600, 400));
      await tester.pump();
      await tester.pump();

      final afterRotation = controller.transform;
      expect(afterRotation.scale, closeTo(beforeRotation.scale, 0.01));
      expect(afterRotation.scale, lessThan(2.25));
      expect(controller.stage, ImageZoomStage.gesture);
      _expectFiniteAndInBounds(
        afterRotation,
        viewportSize: viewportSize,
        fittedImageSize: viewportSize,
      );
      final newSceneFocus = Offset(
        normalizedFocus.dx * viewportSize.width,
        normalizedFocus.dy * viewportSize.height,
      );
      final transformedFocus = _applyTransform(
        afterRotation,
        point: newSceneFocus,
        viewportSize: viewportSize,
      );
      expect(transformedFocus.dx, closeTo(viewportSize.width / 2, 0.5));
      expect(transformedFocus.dy, closeTo(viewportSize.height / 2, 0.5));
      // The parent remains locked because the preserved transform is zoomed,
      // even though the old programmatic animation has been canceled.
      expect(lockChanges.last, isTrue);
      final lockChangeCountAfterRotation = lockChanges.length;

      await tester.pump(const Duration(milliseconds: 500));

      _expectSameTransform(controller.transform, afterRotation);
      expect(controller.stage, ImageZoomStage.gesture);
      expect(lockChanges, hasLength(lockChangeCountAfterRotation));
    },
  );

  testWidgets(
    "cover baseline is semantic identity when collage owns gestures",
    (tester) async {
      final lockChanges = <bool>[];
      final harness = await _pumpViewer(
        tester,
        image: landscapeImage,
        initialFit: BoxFit.cover,
        gesturesEnabled: false,
        onInteractionLockChanged: lockChanges.add,
      );
      final center = harness.globalPoint(const Offset(200, 200));

      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);
      expect(harness.controller.isZoomed, isFalse);

      await _doubleTap(tester, center);
      final firstFinger = await tester.createGesture(pointer: 61);
      final secondFinger = await tester.createGesture(pointer: 62);
      await firstFinger.down(center - const Offset(20, 0));
      await secondFinger.down(center + const Offset(20, 0));
      await firstFinger.moveTo(center - const Offset(80, 0));
      await secondFinger.moveTo(center + const Offset(80, 0));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();

      expect(harness.controller.transform, ImageZoomTransform.identity);
      expect(harness.controller.stage, ImageZoomStage.initial);
      expect(lockChanges, isEmpty);
    },
  );

  testWidgets(
    "same-aspect provider replacement during animation stays stable",
    (tester) async {
      final controller = ImageZoomController();
      addTearDown(controller.dispose);
      final viewportKey = GlobalKey();
      ImageProvider currentProvider = _DeterministicImageProvider(
        landscapeImage,
      );
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  setHostState = setState;
                  return SizedBox(
                    key: viewportKey,
                    width: _viewportSize.width,
                    height: _viewportSize.height,
                    child: ImageZoomViewer(
                      imageProvider: currentProvider,
                      controller: controller,
                      loadingBuilder: _emptyLoadingBuilder,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final tapPoint =
          tester.getTopLeft(find.byKey(viewportKey)) + const Offset(250, 200);
      await _beginDoubleTap(tester, tapPoint);
      await tester.pump(const Duration(milliseconds: 60));
      final beforeReplacement = controller.transform;
      expect(beforeReplacement.scale, inExclusiveRange(1, 1.5));

      setHostState(() {
        currentProvider = _DeterministicImageProvider(largerLandscapeImage);
      });
      await tester.pump();

      _expectSameTransform(controller.transform, beforeReplacement);
      _expectFiniteAndInBounds(
        controller.transform,
        viewportSize: _viewportSize,
        fittedImageSize: const Size(400, 800 / 3),
      );

      await tester.pumpAndSettle();

      _expectTransform(controller, scale: 1.5, offset: const Offset(-75, 0));
      expect(controller.stage, ImageZoomStage.gesture);

      await _doubleTap(tester, tapPoint);
      expect(controller.transform, ImageZoomTransform.identity);
      expect(controller.stage, ImageZoomStage.initial);
    },
  );
}

Future<_ViewerHarness> _pumpViewer(
  WidgetTester tester, {
  required ui.Image image,
  VoidCallback? onParentTap,
  VoidCallback? onParentLongPress,
  GestureDragUpdateCallback? onVerticalDragUpdate,
  ValueChanged<bool>? onInteractionLockChanged,
  BoxFit initialFit = BoxFit.contain,
  bool gesturesEnabled = true,
}) async {
  final viewportKey = GlobalKey();
  final controller = ImageZoomController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: GestureDetector(
            onTap: onParentTap,
            onLongPress: onParentLongPress,
            onVerticalDragUpdate: onVerticalDragUpdate,
            child: SizedBox(
              key: viewportKey,
              width: _viewportSize.width,
              height: _viewportSize.height,
              child: ImageZoomViewer(
                imageProvider: _DeterministicImageProvider(image),
                controller: controller,
                initialFit: initialFit,
                gesturesEnabled: gesturesEnabled,
                loadingBuilder: _emptyLoadingBuilder,
                onInteractionLockChanged: onInteractionLockChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return _ViewerHarness(
    controller: controller,
    viewportTopLeft: tester.getTopLeft(find.byKey(viewportKey)),
  );
}

Future<_PageHarness> _pumpPageHarness(
  WidgetTester tester, {
  required ui.Image image,
  GestureDragUpdateCallback? onVerticalDragUpdate,
}) async {
  final viewportKey = GlobalKey();
  final zoomController = ImageZoomController();
  final pageController = PageController(initialPage: 1);
  final imageProvider = _DeterministicImageProvider(image);
  addTearDown(zoomController.dispose);
  addTearDown(pageController.dispose);
  var isLocked = false;
  late StateSetter setHostState;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return SizedBox(
                key: viewportKey,
                width: _viewportSize.width,
                height: _viewportSize.height,
                child: PageView.builder(
                  controller: pageController,
                  physics: isLocked
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    if (index != 1) {
                      return ColoredBox(
                        color: index == 0 ? Colors.red : Colors.blue,
                      );
                    }
                    return GestureDetector(
                      // Match ZoomableImage: vertical dismissal is removed while
                      // ImageZoomViewer reports an interaction lock.
                      onVerticalDragUpdate: isLocked
                          ? null
                          : onVerticalDragUpdate,
                      child: ImageZoomViewer(
                        imageProvider: imageProvider,
                        controller: zoomController,
                        loadingBuilder: _emptyLoadingBuilder,
                        onInteractionLockChanged: (value) {
                          if (isLocked == value) return;
                          setHostState(() => isLocked = value);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return _PageHarness(
    zoomController: zoomController,
    pageController: pageController,
    viewportTopLeft: tester.getTopLeft(find.byKey(viewportKey)),
    isLocked: () => isLocked,
  );
}

Widget _emptyLoadingBuilder(BuildContext context, ImageChunkEvent? progress) =>
    const SizedBox.shrink();

Future<void> _doubleTap(WidgetTester tester, Offset globalPosition) async {
  await _beginDoubleTap(tester, globalPosition);
  await tester.pumpAndSettle();
}

Future<void> _beginDoubleTap(WidgetTester tester, Offset globalPosition) async {
  await tester.tapAt(globalPosition);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(globalPosition);
  await tester.pump();
}

void _expectTransform(
  ImageZoomController controller, {
  required double scale,
  required Offset offset,
}) {
  expect(controller.transform.scale, closeTo(scale, 0.01));
  expect(controller.transform.offset.dx, closeTo(offset.dx, 0.5));
  expect(controller.transform.offset.dy, closeTo(offset.dy, 0.5));
}

void _expectSameTransform(
  ImageZoomTransform actual,
  ImageZoomTransform expected,
) {
  expect(actual.scale, closeTo(expected.scale, 0.01));
  expect(actual.offset.dx, closeTo(expected.offset.dx, 0.5));
  expect(actual.offset.dy, closeTo(expected.offset.dy, 0.5));
}

void _expectFiniteAndInBounds(
  ImageZoomTransform transform, {
  required Size viewportSize,
  required Size fittedImageSize,
}) {
  expect(transform.scale.isFinite, isTrue);
  expect(transform.scale, greaterThan(0));
  expect(transform.offset.dx.isFinite, isTrue);
  expect(transform.offset.dy.isFinite, isTrue);

  final maxOffsetX = math.max(
    0.0,
    (fittedImageSize.width * transform.scale - viewportSize.width) / 2,
  );
  final maxOffsetY = math.max(
    0.0,
    (fittedImageSize.height * transform.scale - viewportSize.height) / 2,
  );
  expect(
    transform.offset.dx,
    inInclusiveRange(-maxOffsetX - 0.01, maxOffsetX + 0.01),
  );
  expect(
    transform.offset.dy,
    inInclusiveRange(-maxOffsetY - 0.01, maxOffsetY + 0.01),
  );
}

Offset _applyTransform(
  ImageZoomTransform transform, {
  required Offset point,
  required Size viewportSize,
}) {
  final center = viewportSize.center(Offset.zero);
  return center + transform.offset + (point - center) * transform.scale;
}

Future<ui.Image> _createTestImage(Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Offset.zero & size,
    ui.Paint()..color = const Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  return image;
}

Future<Color> _centerPixel(Finder boundaryFinder) async {
  final boundary =
      boundaryFinder.evaluate().single.renderObject! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = image.width ~/ 2;
  final y = image.height ~/ 2;
  final offset = (y * image.width + x) * 4;
  final color = Color.fromARGB(
    data!.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
  image.dispose();
  return color;
}

class _DeterministicImageProvider
    extends ImageProvider<_DeterministicImageProvider> {
  const _DeterministicImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_DeterministicImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_DeterministicImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _DeterministicImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
  );
}

class _ViewerHarness {
  const _ViewerHarness({
    required this.controller,
    required this.viewportTopLeft,
  });

  final ImageZoomController controller;
  final Offset viewportTopLeft;

  Offset globalPoint(Offset localPoint) => viewportTopLeft + localPoint;
}

class _PageHarness {
  const _PageHarness({
    required this.zoomController,
    required this.pageController,
    required this.viewportTopLeft,
    required bool Function() isLocked,
  }) : _isLocked = isLocked;

  final ImageZoomController zoomController;
  final PageController pageController;
  final Offset viewportTopLeft;
  final bool Function() _isLocked;

  bool get isLocked => _isLocked();

  Offset globalPoint(Offset localPoint) => viewportTopLeft + localPoint;
}
