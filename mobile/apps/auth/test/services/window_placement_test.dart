import 'dart:ui';

import 'package:ente_auth/services/window_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const primary = Monitor(
    'primary',
    Rect.fromLTWH(48, 40, 700, 900),
    1,
    primary: true,
  );
  test('restores secondary monitor geometry after DPI and layout changes', () {
    const secondary = Monitor(
      'second',
      Rect.fromLTWH(-2560, 60, 2560, 1380),
      1.5,
    );
    const bounds = Rect.fromLTWH(-2260, 210, 750, 630);
    final saved = captureBounds(bounds, secondary, false);
    expect(
      restoreBounds(saved, [primary, secondary], const Size(800, 1200)),
      bounds,
    );
    const moved = Monitor('second', Rect.fromLTWH(1920, 80, 2560, 1360), 2);
    expect(
      restoreBounds(saved, [primary, moved], const Size(800, 1200)),
      const Rect.fromLTWH(2320, 280, 1000, 840),
    );
  });
  test('missing geometry or monitor fits the primary work area', () {
    for (final saved in const [
      null,
      Placement('removed', Rect.fromLTWH(2000, 2000, 3000, 2000), false),
    ]) {
      expect(
        restoreBounds(saved, [primary], const Size(800, 1200)),
        primary.workArea,
      );
    }
  });
  test('invalid persisted geometry is rejected', () {
    for (final invalid in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(
        () => readRect({'x': 0, 'y': 0, 'width': invalid, 'height': 400}),
        throwsFormatException,
      );
    }
  });
}
