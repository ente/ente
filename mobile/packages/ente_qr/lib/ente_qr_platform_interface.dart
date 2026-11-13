import 'package:ente_qr/ente_qr_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class QrScanResult {
  final String? content;
  final String? error;
  final bool success;

  const QrScanResult({this.content, this.error, required this.success});

  factory QrScanResult.success(String content) {
    return QrScanResult(content: content, success: true);
  }

  factory QrScanResult.error(String error) {
    return QrScanResult(error: error, success: false);
  }
}

// Bounding boxes use normalized 0..1 coordinates.
class QrDetection {
  final String content;

  final double x;

  final double y;

  final double width;

  final double height;

  const QrDetection({
    required this.content,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory QrDetection.fromMap(Map<String, dynamic> map) {
    return QrDetection(
      content: map['content'] as String,
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
    );
  }
}

class QrScanResults {
  final List<QrDetection> detections;
  final String? error;
  final bool success;

  const QrScanResults({
    required this.detections,
    this.error,
    required this.success,
  });

  factory QrScanResults.fromDetections(List<QrDetection> detections) {
    return QrScanResults(detections: detections, success: true);
  }

  factory QrScanResults.error(String error) {
    return QrScanResults(detections: const [], error: error, success: false);
  }
}

abstract class EnteQrPlatform extends PlatformInterface {
  EnteQrPlatform() : super(token: _token);

  static final Object _token = Object();

  static EnteQrPlatform _instance = MethodChannelEnteQr();

  static EnteQrPlatform get instance => _instance;

  static set instance(EnteQrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<QrScanResult> scanQrFromImage(
    String imagePath, {
    bool tryOriginalResolution = false,
  }) {
    throw UnimplementedError('scanQrFromImage() has not been implemented.');
  }

  Future<QrScanResults> scanAllQrFromImage(String imagePath) {
    throw UnimplementedError('scanAllQrFromImage() has not been implemented.');
  }
}
