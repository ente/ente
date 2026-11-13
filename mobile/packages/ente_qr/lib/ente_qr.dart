import 'dart:io';

import 'package:ente_qr/ente_qr_method_channel.dart';
import 'package:ente_qr/ente_qr_platform_interface.dart';
import 'package:ente_qr/src/dart_zxing_qr_platform.dart';
import 'package:ente_qr/src/desktop_qr_platform.dart';
import 'package:image/image.dart' as img;

export 'ente_qr_platform_interface.dart'
    show QrDetection, QrScanResult, QrScanResults;

class EnteQr {
  static const int _dartFallbackMaxBytes = 2 * 1024 * 1024;
  static const int _dartFallbackMaxPixels = 1200 * 1200;

  EnteQrPlatform get _scanPlatform {
    final currentPlatform = EnteQrPlatform.instance;
    if (currentPlatform is! MethodChannelEnteQr) {
      return currentPlatform;
    }
    return desktopQrPlatform() ?? currentPlatform;
  }

  Future<String?> getPlatformVersion() {
    return EnteQrPlatform.instance.getPlatformVersion();
  }

  Future<QrScanResult> scanQrFromImage(
    String imagePath, {
    bool tryOriginalResolution = false,
  }) async {
    final platform = _scanPlatform;
    final result = await platform.scanQrFromImage(
      imagePath,
      tryOriginalResolution: tryOriginalResolution,
    );
    if (result.success ||
        !tryOriginalResolution ||
        platform is! MethodChannelEnteQr) {
      return result;
    }
    if (!await _shouldRunDartFallback(imagePath)) {
      return result;
    }

    final fallbackResult = await DartZxingQrPlatform().scanQrFromImage(
      imagePath,
      tryOriginalResolution: tryOriginalResolution,
    );
    return fallbackResult.success ? fallbackResult : result;
  }

  Future<QrScanResults> scanAllQrFromImage(String imagePath) {
    return _scanPlatform.scanAllQrFromImage(imagePath);
  }

  Future<bool> _shouldRunDartFallback(String imagePath) async {
    try {
      final file = File(imagePath);
      final fileSize = await file.length();
      if (fileSize > _dartFallbackMaxBytes) {
        return false;
      }

      final bytes = await file.readAsBytes();
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info == null) {
        return false;
      }
      return info.width * info.height <= _dartFallbackMaxPixels;
    } catch (_) {
      return false;
    }
  }
}
