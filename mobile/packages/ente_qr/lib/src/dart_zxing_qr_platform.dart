import 'dart:io';
import 'dart:typed_data';

import 'package:ente_qr/ente_qr_platform_interface.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

final class DartZxingQrPlatform extends EnteQrPlatform {
  static const int _defaultMaxInputBytes = 16 * 1024 * 1024;
  static const int _defaultMaxInputPixels = 4096 * 4096;
  static const int _maxScanDimension = 1200;

  DartZxingQrPlatform({
    int maxInputBytes = _defaultMaxInputBytes,
    int maxInputPixels = _defaultMaxInputPixels,
  }) : _maxInputBytes = maxInputBytes,
       _maxInputPixels = maxInputPixels;

  final int _maxInputBytes;
  final int _maxInputPixels;

  @override
  Future<String?> getPlatformVersion() async {
    return 'Dart zxing2';
  }

  @override
  Future<QrScanResult> scanQrFromImage(
    String imagePath, {
    bool tryOriginalResolution = false,
  }) async {
    try {
      final content = await _decodeQrFromImagePath(
        imagePath,
        maxInputBytes: _maxInputBytes,
        maxInputPixels: _maxInputPixels,
        tryOriginalResolution: tryOriginalResolution,
      );
      return QrScanResult.success(content);
    } catch (e) {
      return QrScanResult.error(e.toString());
    }
  }

  @override
  Future<QrScanResults> scanAllQrFromImage(String imagePath) async {
    final result = await scanQrFromImage(imagePath);
    final content = result.content;
    if (!result.success || content == null) {
      return QrScanResults.error(result.error ?? 'No QR code found in image');
    }
    return QrScanResults.fromDetections([
      QrDetection(content: content, x: 0, y: 0, width: 1, height: 1),
    ]);
  }
}

Future<String> _decodeQrFromImagePath(
  String imagePath, {
  required int maxInputBytes,
  required int maxInputPixels,
  required bool tryOriginalResolution,
}) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    throw StateError('Image file not found: $imagePath');
  }

  final fileSize = await file.length();
  if (fileSize > maxInputBytes) {
    throw StateError('Image file is too large for QR scanning');
  }

  final bytes = await file.readAsBytes();
  if (bytes.length > maxInputBytes) {
    throw StateError('Image file is too large for QR scanning');
  }

  final decoder = _validatedDecoder(bytes, maxInputPixels: maxInputPixels);
  final image = decoder.decodeFrame(0);
  if (image == null) {
    throw StateError('Unable to decode image file');
  }

  return _decodeImage(image, tryOriginalResolution: tryOriginalResolution).text;
}

img.Decoder _validatedDecoder(Uint8List bytes, {required int maxInputPixels}) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null) {
    throw StateError('Unable to decode image file');
  }
  if (info.width <= 0 || info.height <= 0) {
    throw StateError('Unable to decode image file');
  }
  if (info.width * info.height > maxInputPixels) {
    throw StateError('Image dimensions are too large for QR scanning');
  }
  return decoder;
}

Result _decodeImage(img.Image source, {required bool tryOriginalResolution}) {
  Object? lastError;
  Result? tryDecode(img.Image attempt) {
    final converted = attempt.convert(numChannels: 4);
    final pixels = converted
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List();
    final luminanceSource = RGBLuminanceSource(
      converted.width,
      converted.height,
      pixels,
    );

    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    for (final bitmap in [
      BinaryBitmap(GlobalHistogramBinarizer(luminanceSource)),
      BinaryBitmap(HybridBinarizer(luminanceSource)),
    ]) {
      try {
        return QRCodeReader().decode(bitmap, hints: hints);
      } catch (error) {
        lastError = error;
      }
    }
    return null;
  }

  Result? tryDecodeVariants(img.Image attempt) {
    final result = tryDecode(attempt);
    if (result != null) {
      return result;
    }
    return tryDecode(img.invert(img.Image.from(attempt)));
  }

  if (tryOriginalResolution) {
    final result = tryDecodeVariants(source);
    if (result != null) {
      return result;
    }
  }

  final scanSource = _scanSource(source);
  if (!tryOriginalResolution || !identical(scanSource, source)) {
    final result = tryDecodeVariants(scanSource);
    if (result != null) {
      return result;
    }
  }

  if (_maxDimension(scanSource) < 600) {
    final upscaled = img.copyResize(
      scanSource,
      width: scanSource.width * 2,
      height: scanSource.height * 2,
      interpolation: img.Interpolation.linear,
    );
    final result = tryDecodeVariants(upscaled);
    if (result != null) {
      return result;
    }
  }

  throw StateError(lastError?.toString() ?? 'No QR code found in image');
}

img.Image _scanSource(img.Image source) {
  if (_maxDimension(source) <= DartZxingQrPlatform._maxScanDimension) {
    return source;
  }
  return img.copyResize(
    source,
    width: source.width >= source.height
        ? DartZxingQrPlatform._maxScanDimension
        : null,
    height: source.height > source.width
        ? DartZxingQrPlatform._maxScanDimension
        : null,
  );
}

int _maxDimension(img.Image image) {
  return image.width > image.height ? image.width : image.height;
}
