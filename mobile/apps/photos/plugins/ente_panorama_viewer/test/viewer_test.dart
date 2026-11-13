import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:ente_panorama_viewer/ente_panorama_viewer.dart";
import "package:ente_panorama_viewer/src/camera.dart";
import "package:ente_panorama_viewer/src/motion.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

final _tinyImage = base64Decode(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12P4z8DwHwAFAAH/"
  "iZnRjQAAAABJRU5ErkJggg==",
);

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: child)),
    );
  }

  Widget wrapSized(Widget child, Size size) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    );
  }

  testWidgets("retains the placeholder and reports image decode errors", (
    tester,
  ) async {
    Object? reportedError;
    await tester.pumpWidget(
      wrap(
        EntePanoramaViewer(
          image: MemoryImage(Uint8List.fromList(const [1, 2, 3])),
          geometry: const PanoramaGeometry.fullSphere(),
          placeholder: const ColoredBox(
            key: Key("placeholder"),
            color: Colors.black,
          ),
          onError: (error, _) {
            reportedError = error;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(reportedError, isNotNull);
    expect(find.byKey(const Key("placeholder")), findsOneWidget);
  });

  testWidgets("reports taps and view changes from touch gestures", (
    tester,
  ) async {
    var taps = 0;
    final views = <PanoramaView>[];
    await tester.pumpWidget(
      wrap(
        EntePanoramaViewer(
          image: MemoryImage(_tinyImage),
          geometry: const PanoramaGeometry.fullSphere(),
          onTap: () => taps++,
          onViewChanged: views.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EntePanoramaViewer));
    expect(taps, 1);

    await tester.drag(find.byType(EntePanoramaViewer), const Offset(150, 50));
    await tester.pumpAndSettle();
    expect(views, isNotEmpty);
    expect(views.last.longitude, isNot(0));
  });

  testWidgets("motion stop rejects a sensor frame that is already queued", (
    tester,
  ) async {
    final events = StreamController<Object?>.broadcast(sync: true);
    final deltas = <PanoramaView>[];
    final errors = <Object>[];
    final controller = MotionController(
      deltas.add,
      onReferenceChanged: () {},
      onError: (error, _) => errors.add(error),
      eventStream: () => events.stream,
    );

    controller.start();
    await tester.pump();
    events.add(const <Object?>[1.0, 0.0, 0.0, 0.0, 0]);
    unawaited(controller.stop());
    await tester.pump();

    expect(deltas, isEmpty);
    expect(errors, isEmpty);
    unawaited(events.close());
  });

  testWidgets("motion stream errors are reported and stop sensor delivery", (
    tester,
  ) async {
    final events = StreamController<Object?>.broadcast(sync: true);
    final deltas = <PanoramaView>[];
    final errors = <Object>[];
    final controller = MotionController(
      deltas.add,
      onReferenceChanged: () {},
      onError: (error, _) => errors.add(error),
      eventStream: () => events.stream,
    );

    controller.start();
    await tester.pump();
    final sensorError = StateError("sensor failed");
    events.addError(sensorError, StackTrace.current);
    events.add(const <Object?>[1.0, 0.0, 0.0, 0.0, 0]);
    await tester.pump();

    expect(errors, [sensorError]);
    expect(deltas, isEmpty);
    unawaited(controller.stop());
    await tester.pump();
    unawaited(events.close());
  });

  testWidgets("initial view resets only when the image is replaced", (
    tester,
  ) async {
    var image = MemoryImage(_tinyImage);
    var initialView = const PanoramaView();
    final views = <PanoramaView>[];
    late StateSetter rebuild;

    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return EntePanoramaViewer(
              image: image,
              geometry: const PanoramaGeometry.fullSphere(),
              initialView: initialView,
              onViewChanged: views.add,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(EntePanoramaViewer), const Offset(150, 0));
    await tester.pumpAndSettle();
    final liveLongitude = views.last.longitude;

    rebuild(() {
      initialView = const PanoramaView(longitude: 90);
    });
    await tester.pump();
    expect(views.last.longitude, liveLongitude);

    rebuild(() {
      image = MemoryImage(Uint8List.fromList(_tinyImage));
      initialView = const PanoramaView(longitude: 45);
    });
    await tester.pumpAndSettle();
    expect(views.last.longitude, closeTo(45, 1e-9));
  });

  testWidgets("rotation preserves the live camera", (tester) async {
    var size = const Size(400, 700);
    final image = MemoryImage(_tinyImage);
    final views = <PanoramaView>[];
    late StateSetter rebuild;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return wrapSized(
            EntePanoramaViewer(
              image: image,
              geometry: const PanoramaGeometry.fullSphere(),
              onViewChanged: views.add,
            ),
            size,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(EntePanoramaViewer), const Offset(100, 0));
    await tester.pumpAndSettle();
    final beforeRotation = views.last.longitude;

    rebuild(() {
      size = const Size(700, 400);
    });
    await tester.pump();
    await tester.timedDrag(
      find.byType(EntePanoramaViewer),
      const Offset(1, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect((views.last.longitude - beforeRotation).abs(), lessThan(5));
  });

  testWidgets("crop updates clamp the live camera", (tester) async {
    final image = MemoryImage(_tinyImage);
    var geometry = const PanoramaGeometry.fullSphere();
    final views = <PanoramaView>[];
    late StateSetter rebuild;

    await tester.pumpWidget(
      wrapSized(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return EntePanoramaViewer(
              image: image,
              geometry: geometry,
              onViewChanged: views.add,
            );
          },
        ),
        const Size(400, 700),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(EntePanoramaViewer), const Offset(150, 0));
    await tester.pumpAndSettle();

    rebuild(() {
      geometry = PanoramaGeometry(
        fullSize: const Size(8762, 4381),
        croppedArea: const Rect.fromLTWH(6183, 1040, 2520, 1664),
      );
    });
    await tester.pump();

    final validator = PanoramaCamera(geometry: geometry)
      ..updateViewport(const Size(400, 700), notify: false)
      ..setView(views.last);
    expect(validator.view, views.last);
  });

  testWidgets("pinch zoom preserves its focal panorama point", (tester) async {
    const size = Size(600, 400);
    const focal = Offset(370, 180);
    PanoramaView? lastView;
    const geometry = PanoramaGeometry.fullSphere();
    final camera = PanoramaCamera(geometry: geometry)
      ..updateViewport(size, notify: false);

    await tester.pumpWidget(
      wrapSized(
        EntePanoramaViewer(
          image: MemoryImage(_tinyImage),
          geometry: geometry,
          onViewChanged: (view) {
            lastView = view;
          },
        ),
        size,
      ),
    );
    await tester.pumpAndSettle();
    final topLeft = tester.getTopLeft(find.byType(EntePanoramaViewer));
    final first = await tester.startGesture(
      topLeft + focal - const Offset(50, 0),
    );
    final second = await tester.startGesture(
      topLeft + focal + const Offset(50, 0),
    );
    await tester.pump();
    await first.moveTo(topLeft + focal - const Offset(51, 0));
    await second.moveTo(topLeft + focal + const Offset(51, 0));
    await tester.pump();
    camera.setView(lastView!);
    final sourceBefore = camera.sourcePointAt(focal);

    await first.moveTo(topLeft + focal - const Offset(100, 0));
    await second.moveTo(topLeft + focal + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    camera.setView(lastView!);
    final sourceAfter = camera.sourcePointAt(focal);
    expect(sourceAfter.dx, closeTo(sourceBefore.dx, 1e-4));
    expect(sourceAfter.dy, closeTo(sourceBefore.dy, 1e-4));
  });

  testWidgets("inertia stops when a partial panorama boundary is reached", (
    tester,
  ) async {
    final geometry = PanoramaGeometry(
      fullSize: const Size(8762, 4381),
      croppedArea: const Rect.fromLTWH(6183, 1040, 2520, 1664),
    );
    final views = <PanoramaView>[];

    await tester.pumpWidget(
      wrapSized(
        EntePanoramaViewer(
          image: MemoryImage(_tinyImage),
          geometry: geometry,
          onViewChanged: views.add,
        ),
        const Size(400, 700),
      ),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(EntePanoramaViewer),
      const Offset(350, 0),
      5000,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    final countAtBoundary = views.length;
    await tester.pump(const Duration(seconds: 1));

    expect(views.length, countAtBoundary);
    final validator = PanoramaCamera(geometry: geometry)
      ..updateViewport(const Size(400, 700), notify: false);
    for (final view in views) {
      validator.setView(view);
      expect(validator.view, view);
    }
  });
}
