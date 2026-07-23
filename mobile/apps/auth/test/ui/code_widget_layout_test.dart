import 'package:ente_auth/ui/code_widget_layout_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capCodeWidgetTextScaleForIOS', () {
    test('caps iOS text scale at 2.0', () {
      final value = capCodeWidgetTextScaleForIOS(3.12);

      expect(value, 2.0);
    });

    test('preserves iOS text scale exactly at 2.0', () {
      final value = capCodeWidgetTextScaleForIOS(2.0);

      expect(value, 2.0);
    });

    test('preserves smaller iOS text scales', () {
      final value = capCodeWidgetTextScaleForIOS(0.85);

      expect(value, 0.85);
    });
  });
}
