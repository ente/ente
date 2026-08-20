import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_widgets.dart';

void main() {
  const sourceCrop = Rect.fromLTRB(0.1, 0.2, 0.6, 0.8);

  test('clockwise crop rotation preserves the selected visual region', () {
    _expectRectClose(
      rotateNormalizedRect(sourceCrop, 90),
      const Rect.fromLTRB(0.2, 0.1, 0.8, 0.6),
    );
    _expectRectClose(
      rotateNormalizedRect(sourceCrop, 180),
      const Rect.fromLTRB(0.4, 0.2, 0.9, 0.8),
    );
    _expectRectClose(
      rotateNormalizedRect(sourceCrop, 270),
      const Rect.fromLTRB(0.2, 0.4, 0.8, 0.9),
    );
  });

  test('fixed-ratio crop remains in bounds without changing ratio', () {
    final crop = constrainNormalizedCropRect(
      rect: const Rect.fromLTRB(-0.1, 0.1, 0.8, 0.9),
      movesLeft: true,
      movesTop: true,
      normalizedRatio: 16 / 9,
      minimumWidth: 0.05,
      minimumHeight: 0.05,
    );

    expect(crop.left, greaterThanOrEqualTo(0));
    expect(crop.top, greaterThanOrEqualTo(0));
    expect(crop.right, lessThanOrEqualTo(1));
    expect(crop.bottom, lessThanOrEqualTo(1));
    expect(crop.width / crop.height, closeTo(16 / 9, 1e-12));
  });
}

void _expectRectClose(Rect actual, Rect expected) {
  const tolerance = 1e-12;
  expect(actual.left, closeTo(expected.left, tolerance));
  expect(actual.top, closeTo(expected.top, tolerance));
  expect(actual.right, closeTo(expected.right, tolerance));
  expect(actual.bottom, closeTo(expected.bottom, tolerance));
}
