import "dart:typed_data";

import "package:ente_crypto/src/uint8_list_equals.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("compares empty, byte-tail and complete-word lengths", () {
    for (final length in [0, 1, 7, 8, 9, 15, 16, 17]) {
      final a = Uint8List.fromList(
        List.generate(length, (index) => (index * 131 + 19) & 255),
      );
      final b = Uint8List.fromList(a);

      expect(uint8ListEquals(a, a), isTrue);
      expect(uint8ListEquals(a, b), isTrue);
      expect(uint8ListEquals(a, Uint8List(length + 1)), isFalse);

      for (var index = 0; index < length; index++) {
        b[index] ^= 0x80;
        expect(
          uint8ListEquals(a, b),
          isFalse,
          reason: "Mismatch at byte $index of $length",
        );
        b[index] ^= 0x80;
      }
    }
  });
}
