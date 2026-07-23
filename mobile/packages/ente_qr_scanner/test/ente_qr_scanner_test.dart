import 'package:ente_qr_scanner/ente_qr_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overlay serializes creation params', () {
    const overlay = EnteQrScannerOverlay(
      borderColor: Colors.green,
      overlayColor: Colors.black54,
      cutOutSize: 240,
      borderRadius: 10,
      borderLength: 28,
      borderWidth: 3,
    );

    expect(overlay.toCreationParams(), {'cutOutSize': 240.0});
  });
}
