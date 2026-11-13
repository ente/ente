import "dart:math" as math;
import "dart:ui";

import "package:ente_panorama_viewer/src/camera.dart";
import "package:ente_panorama_viewer/src/models.dart";
import "package:ente_panorama_viewer/src/motion.dart";
import "package:flutter_test/flutter_test.dart";

final _pixelGeometry = PanoramaGeometry(
  fullSize: const Size(8762, 4381),
  croppedArea: const Rect.fromLTWH(6183, 1040, 2520, 1664),
);

void main() {
  test("rejects crop geometry outside the full panorama", () {
    expect(
      () => PanoramaGeometry(
        fullSize: const Size(100, 50),
        croppedArea: const Rect.fromLTWH(90, 0, 20, 20),
      ),
      throwsArgumentError,
    );
  });

  test("replaces non-finite camera values before rendering", () {
    final camera = PanoramaCamera(
      geometry: _pixelGeometry,
      initialView: const PanoramaView(
        longitude: double.nan,
        latitude: double.infinity,
        zoom: double.nan,
      ),
    )..updateViewport(const Size(400, 700), notify: false);

    expect(camera.view.longitude.isFinite, isTrue);
    expect(camera.view.latitude.isFinite, isTrue);
    expect(camera.view.zoom.isFinite, isTrue);
  });

  test(
    "centers a partial panorama and fits portrait and landscape viewports",
    () {
      final camera = PanoramaCamera(geometry: _pixelGeometry);

      camera.updateViewport(const Size(1080, 2115), notify: false);
      expect(camera.view.longitude, closeTo(125.81, 0.01));
      expect(camera.view.latitude, closeTo(13.09, 0.01));
      expect(camera.minimumZoom, 1);
      expect(camera.cropFitZoom, closeTo(1.13, 0.02));
      expect(camera.view.zoom, camera.cropFitZoom);

      camera.updateViewport(const Size(2000, 1000), notify: false);
      expect(camera.cropFitZoom, closeTo(1.42, 0.02));
      expect(camera.view.zoom, camera.cropFitZoom);
    },
  );

  test("opens crop-fit without making it the zoom-out limit", () {
    final camera = PanoramaCamera(
      geometry: PanoramaGeometry(
        fullSize: const Size(4000, 2000),
        croppedArea: const Rect.fromLTWH(1500, 950, 1000, 100),
      ),
    );

    camera.updateViewport(const Size(500, 1000), notify: false);

    expect(camera.minimumZoom, 1);
    expect(camera.cropFitZoom, greaterThan(5));
    expect(camera.maximumZoom, camera.cropFitZoom);
    expect(camera.view.zoom, camera.cropFitZoom);
  });

  test("maps the viewport center to the center of the source crop", () {
    final camera = PanoramaCamera(geometry: _pixelGeometry)
      ..updateViewport(const Size(1080, 2115), notify: false);
    final point = camera.sourcePointAt(const Offset(540, 1057.5));
    final crop = _pixelGeometry.normalizedCrop;

    expect(point.dx, closeTo(crop.center.dx, 1e-6));
    expect(point.dy, closeTo(crop.center.dy, 1e-6));
  });

  test(
    "keeps the camera center in the crop while allowing blur-backed edges",
    () {
      final camera = PanoramaCamera(geometry: _pixelGeometry)
        ..updateViewport(const Size(2000, 1000), notify: false);
      camera.setView(
        const PanoramaView(longitude: -1000, latitude: 1000, zoom: 1),
      );
      final crop = _pixelGeometry.normalizedCrop;
      final center = camera.sourcePointAt(const Offset(1000, 500));

      expect(center.dx, inInclusiveRange(crop.left - 1e-9, crop.right + 1e-9));
      expect(center.dy, inInclusiveRange(crop.top - 1e-9, crop.bottom + 1e-9));
      final edges = [
        camera.sourcePointAt(const Offset(1000, 0)),
        camera.sourcePointAt(const Offset(1000, 1000)),
        camera.sourcePointAt(const Offset(0, 500)),
        camera.sourcePointAt(const Offset(2000, 500)),
      ];
      expect(
        edges.any(
          (point) =>
              point.dx < crop.left ||
              point.dx > crop.right ||
              point.dy < crop.top ||
              point.dy > crop.bottom,
        ),
        isTrue,
      );
    },
  );

  test("preserves the panorama point beneath a pinch focal point", () {
    final camera = PanoramaCamera(geometry: _pixelGeometry)
      ..updateViewport(const Size(1000, 1500), notify: false);
    const focalPoint = Offset(700, 800);
    final sourceBefore = camera.sourcePointAt(focalPoint);

    camera.setView(camera.view.copyWith(zoom: camera.view.zoom * 2));
    camera.anchorSourcePoint(focalPoint, sourceBefore);
    final sourceAfter = camera.sourcePointAt(focalPoint);

    expect(sourceAfter.dx, closeTo(sourceBefore.dx, 1e-5));
    expect(sourceAfter.dy, closeTo(sourceBefore.dy, 1e-5));
  });

  test("wraps longitude across the full-sphere seam", () {
    final camera = PanoramaCamera(geometry: const PanoramaGeometry.fullSphere())
      ..updateViewport(const Size(1000, 1000), notify: false);

    expect(camera.wouldConstrain(const PanoramaView(longitude: 540)), isFalse);
    camera.setView(const PanoramaView(longitude: 540));

    expect(camera.view.longitude, closeTo(-180, 1e-9));
    expect(camera.sourcePointAt(const Offset(500, 500)).dx, closeTo(0, 1e-9));
  });

  test("keeps rays past a partial right seam outside the crop", () {
    final camera = PanoramaCamera(
      geometry: PanoramaGeometry(
        fullSize: const Size(1000, 500),
        croppedArea: const Rect.fromLTWH(700, 0, 300, 500),
      ),
    )..updateViewport(const Size(1000, 1000), notify: false);

    const requested = PanoramaView(longitude: 1000);
    expect(camera.wouldConstrain(requested), isTrue);
    camera.setView(requested);

    expect(camera.sourcePointAt(const Offset(500, 500)).dx, closeTo(1, 1e-9));
    expect(camera.sourcePointAt(const Offset(1000, 500)).dx, greaterThan(1));
  });

  test(
    "normalizes quaternion magnitude and reports relative yaw and pitch",
    () {
      const angle = 20 * math.pi / 180;
      final tracker = MotionViewTracker();
      expect(
        tracker.updateValues(w: 2, x: 0, y: 0, z: 0),
        const PanoramaView(),
      );

      final yaw = tracker.updateValues(
        w: 2 * math.cos(angle / 2),
        x: 0,
        y: -2 * math.sin(angle / 2),
        z: 0,
      );
      expect(yaw.longitude, closeTo(20, 1e-6));
      expect(yaw.latitude, closeTo(0, 1e-6));

      tracker.reset();
      tracker.updateValues(w: 1, x: 0, y: 0, z: 0);
      final pitch = tracker.updateValues(
        w: math.cos(angle / 2),
        x: math.sin(angle / 2),
        y: 0,
        z: 0,
      );
      expect(pitch.longitude, closeTo(0, 1e-6));
      expect(pitch.latitude, closeTo(20, 1e-6));
    },
  );

  test("normalizes motion to the current screen orientation", () {
    const angle = 20 * math.pi / 180;

    PanoramaView landscapeDelta({
      required int quarterTurns,
      required double xAngle,
      required double yAngle,
    }) {
      final tracker = MotionViewTracker();
      tracker.updateScreenAdjustedValues(
        w: 1,
        x: 0,
        y: 0,
        z: 0,
        quarterTurns: quarterTurns,
      );
      final halfX = xAngle / 2;
      final halfY = yAngle / 2;
      return tracker.updateScreenAdjustedValues(
        w: math.cos(halfX) * math.cos(halfY),
        x: math.sin(halfX) * math.cos(halfY),
        y: math.cos(halfX) * math.sin(halfY),
        z: -math.sin(halfX) * math.sin(halfY),
        quarterTurns: quarterTurns,
      );
    }

    for (final delta in [
      landscapeDelta(quarterTurns: 1, xAngle: angle, yAngle: 0),
      landscapeDelta(quarterTurns: 2, xAngle: 0, yAngle: angle),
      landscapeDelta(quarterTurns: 3, xAngle: -angle, yAngle: 0),
    ]) {
      expect(delta.longitude, closeTo(20, 1e-6));
      expect(delta.latitude, closeTo(0, 1e-6));
    }
  });
}
