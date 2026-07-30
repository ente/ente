import 'package:ente_auth/utils/debug_build_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen capture stays disabled without the debug build flag', () {
    expect(shouldAllowAuthScreenCapture, isFalse);
  });
}
