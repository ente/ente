import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_geometry.dart";

void main() {
  group("ImageZoomGeometry", () {
    test("builds a bounded focal target around the tapped scene point", () {
      final geometry = _geometry(
        viewportSize: const Size(400, 400),
        imageSize: const Size(800, 800),
      );
      final initial = geometry.matrixForScaleAndOffset(1, Offset.zero);
      final target = geometry.matrixForFocalPoint(
        initial,
        const Offset(100, 120),
        2,
      );

      expect(geometry.scenePoint(target, geometry.viewportCenter).dx, 100);
      expect(geometry.scenePoint(target, geometry.viewportCenter).dy, 120);
      final state = geometry.describe(target);
      expect(state.absoluteScale, 2);
      expect(state.semanticOffset, const Offset(200, 160));
    });

    test("clamps scale and offsets to visible image bounds", () {
      final geometry = _geometry(
        viewportSize: const Size(400, 300),
        imageSize: const Size(1000, 500),
        maxScaleOverCover: 2,
      );
      final unbounded = geometry.matrixForScaleAndOffset(
        5,
        const Offset(900, -900),
      );
      final state = geometry.describe(geometry.sanitize(unbounded));

      expect(state.absoluteScale, 3);
      expect(state.relativeScale, 3);
      expect(state.semanticOffset, const Offset(400, -150));
      expect(state.isInitial, isFalse);
      expect(geometry.clampScale(0.5), 1);
      expect(geometry.clampScale(8), 3);
    });
  });

  group("ImageZoomRebase", () {
    test("preserves relative scale and normalized focus", () {
      final before = _geometry(
        viewportSize: const Size(400, 300),
        imageSize: const Size(1000, 500),
      );
      final after = _geometry(
        viewportSize: const Size(300, 400),
        imageSize: const Size(1000, 500),
      );
      final matrix = before.sanitize(
        before.matrixForScaleAndOffset(2, const Offset(50, 0)),
      );
      final rebase = ImageZoomRebase.capture(before, matrix);
      final resolved = rebase.resolve(after);
      final resolvedState = after.describe(resolved);
      final recaptured = ImageZoomRebase.capture(after, resolved);

      expect(resolvedState.relativeScale, closeTo(rebase.relativeScale, 1e-9));
      expect(
        recaptured.normalizedFocus.dx,
        closeTo(rebase.normalizedFocus.dx, 1e-9),
      );
      expect(
        recaptured.normalizedFocus.dy,
        closeTo(rebase.normalizedFocus.dy, 1e-9),
      );
    });
  });
}

ImageZoomGeometry _geometry({
  required Size viewportSize,
  required Size imageSize,
  BoxFit initialFit = BoxFit.contain,
  double maxScaleOverCover = double.infinity,
}) => ImageZoomGeometry.calculate(
  viewportSize: viewportSize,
  imageSize: imageSize,
  initialFit: initialFit,
  maxScaleOverCover: maxScaleOverCover,
)!;
