import 'dart:io';
import 'dart:typed_data';

import 'package:ente_qr/src/dart_zxing_qr_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ente_qr_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('scanQrFromImage decodes a QR PNG', () async {
    const payload =
        'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
    final imagePath = '${tempDir.path}/qr.png';
    await File(imagePath).writeAsBytes(img.encodePng(_qrImage(payload)));

    final result = await DartZxingQrPlatform().scanQrFromImage(imagePath);

    expect(result.success, true);
    expect(result.content, payload);
  });

  test('scanQrFromImage rejects files above the byte limit', () async {
    final imagePath = '${tempDir.path}/oversized.bin';
    await File(imagePath).writeAsBytes(List<int>.filled(32, 0));

    final result = await DartZxingQrPlatform(
      maxInputBytes: 16,
    ).scanQrFromImage(imagePath);

    expect(result.success, false);
    expect(result.error, contains('too large for QR scanning'));
  });

  test('scanQrFromImage rejects images above the pixel limit', () async {
    final imagePath = '${tempDir.path}/oversized.bmp';
    await File(imagePath).writeAsBytes(_bmpHeader(width: 50, height: 50));

    final result = await DartZxingQrPlatform(
      maxInputBytes: 1024,
      maxInputPixels: 100,
    ).scanQrFromImage(imagePath);

    expect(result.success, false);
    expect(result.error, contains('dimensions are too large'));
  });

  test('scanQrFromImage returns an error when no QR is present', () async {
    final imagePath = '${tempDir.path}/blank.png';
    final blank = img.Image(width: 320, height: 320)
      ..clear(img.ColorRgb8(255, 255, 255));
    await File(imagePath).writeAsBytes(img.encodePng(blank));

    final result = await DartZxingQrPlatform().scanQrFromImage(imagePath);

    expect(result.success, false);
    expect(result.error, isNotEmpty);
  });

  test('scanQrFromImage decodes a low-resolution screenshot', () async {
    const payload =
        'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
    final imagePath = '${tempDir.path}/low_resolution_screenshot.png';
    await File(
      imagePath,
    ).writeAsBytes(img.encodePng(_lowResolutionScreenshot(payload)));

    final result = await DartZxingQrPlatform().scanQrFromImage(imagePath);

    expect(result.success, true);
    expect(result.content, payload);
  });
}

img.Image _qrImage(String payload, {int pixelsPerModule = 8}) {
  final qrcode = Encoder.encode(payload, ErrorCorrectionLevel.h);
  final matrix = qrcode.matrix!;
  const quietZoneModules = 4;
  final size = (matrix.width + quietZoneModules * 2) * pixelsPerModule;
  final image = img.Image(width: size, height: size)
    ..clear(img.ColorRgb8(255, 255, 255));

  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) != 1) {
        continue;
      }
      final left = (x + quietZoneModules) * pixelsPerModule;
      final top = (y + quietZoneModules) * pixelsPerModule;
      img.fillRect(
        image,
        x1: left,
        y1: top,
        x2: left + pixelsPerModule - 1,
        y2: top + pixelsPerModule - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return image;
}

img.Image _lowResolutionScreenshot(String payload) {
  final screenshot = img.Image(width: 288, height: 272)
    ..clear(img.ColorRgb8(26, 26, 26));
  final qr = img.copyResize(
    _qrImage(payload, pixelsPerModule: 14),
    width: 200,
    height: 200,
    interpolation: img.Interpolation.linear,
  );
  img.compositeImage(screenshot, qr, dstX: 44, dstY: 29);
  return screenshot;
}

Uint8List _bmpHeader({required int width, required int height}) {
  final bytes = Uint8List(54);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 0x42;
  bytes[1] = 0x4d;
  data.setUint32(2, bytes.length, Endian.little);
  data.setUint32(10, 54, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, height, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  return bytes;
}
