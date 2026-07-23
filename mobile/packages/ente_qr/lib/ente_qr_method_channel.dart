import 'package:ente_qr/ente_qr_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An implementation of [EnteQrPlatform] that uses method channels.
class MethodChannelEnteQr extends EnteQrPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ente_qr');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<QrScanResult> scanQrFromImage(
    String imagePath, {
    bool tryOriginalResolution = false,
  }) async {
    try {
      final dynamic result = await methodChannel.invokeMethod(
        'scanQrFromImage',
        {
          'imagePath': imagePath,
          'tryOriginalResolution': tryOriginalResolution,
        },
      );

      if (result == null) {
        return QrScanResult.error('Failed to scan QR code');
      }

      // Convert to Map<String, dynamic> safely
      final Map<String, dynamic> resultMap = Map<String, dynamic>.from(
        result as Map,
      );

      final bool success = resultMap['success'] as bool? ?? false;
      if (success) {
        final String? content = resultMap['content'] as String?;
        if (content != null && content.isNotEmpty) {
          return QrScanResult.success(content);
        } else {
          return QrScanResult.error('No QR code found in image');
        }
      } else {
        final String? error = resultMap['error'] as String?;
        return QrScanResult.error(error ?? 'Unknown error occurred');
      }
    } on PlatformException catch (e) {
      return QrScanResult.error('Platform error: ${e.message}');
    } catch (e) {
      return QrScanResult.error('Unexpected error: $e');
    }
  }

  @override
  Future<QrScanResults> scanAllQrFromImage(String imagePath) async {
    try {
      final dynamic result = await methodChannel.invokeMethod(
        'scanAllQrFromImage',
        {'imagePath': imagePath},
      );

      if (result == null) {
        return QrScanResults.error('Failed to scan QR codes');
      }

      final Map<String, dynamic> resultMap = Map<String, dynamic>.from(
        result as Map,
      );

      final bool success = resultMap['success'] as bool? ?? false;
      if (success) {
        final List<dynamic>? rawDetections =
            resultMap['detections'] as List<dynamic>?;
        if (rawDetections != null && rawDetections.isNotEmpty) {
          final detections = rawDetections.map((d) {
            return QrDetection.fromMap(Map<String, dynamic>.from(d as Map));
          }).toList();
          return QrScanResults.fromDetections(detections);
        } else {
          return QrScanResults.error('No QR codes found in image');
        }
      } else {
        final String? error = resultMap['error'] as String?;
        return QrScanResults.error(error ?? 'Unknown error occurred');
      }
    } on PlatformException catch (e) {
      return QrScanResults.error('Platform error: ${e.message}');
    } catch (e) {
      return QrScanResults.error('Unexpected error: $e');
    }
  }
}
