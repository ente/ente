import 'package:ente_qr/ente_qr_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The result of QR code scanning
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

/// A single detected QR code with its content and normalized bounding box.
class QrDetection {
  /// The decoded QR code content.
  final String content;

  /// Normalized x coordinate of the bounding box (0.0 to 1.0).
  final double x;

  /// Normalized y coordinate of the bounding box (0.0 to 1.0).
  final double y;

  /// Normalized width of the bounding box (0.0 to 1.0).
  final double width;

  /// Normalized height of the bounding box (0.0 to 1.0).
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

/// The result of scanning for multiple QR codes.
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
  /// Constructs a EnteQrPlatform.
  EnteQrPlatform() : super(token: _token);

  static final Object _token = Object();

  static EnteQrPlatform _instance = MethodChannelEnteQr();

  /// The default instance of [EnteQrPlatform] to use.
  ///
  /// Defaults to [MethodChannelEnteQr].
  static EnteQrPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EnteQrPlatform] when
  /// they register themselves.
  static set instance(EnteQrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Scans a QR code from an image file at the given path.
  /// Returns the QR code content as a string if successful, null otherwise.
  Future<QrScanResult> scanQrFromImage(
    String imagePath, {
    bool tryOriginalResolution = false,
  }) {
    throw UnimplementedError('scanQrFromImage() has not been implemented.');
  }

  /// Scans all QR codes from an image file at the given path.
  /// Returns a list of detections with content and bounding boxes.
  Future<QrScanResults> scanAllQrFromImage(String imagePath) {
    throw UnimplementedError('scanAllQrFromImage() has not been implemented.');
  }
}
