import 'package:flutter/services.dart';

class VisionTextRecognizer {
  VisionTextRecognizer({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName);

  static final instance = VisionTextRecognizer();
  static const _methodChannelName = 'io.ente.photos.vision/text_recognition';

  final MethodChannel _methodChannel;

  Future<Map<dynamic, dynamic>> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) async {
    final result = await _methodChannel
        .invokeMapMethod<dynamic, dynamic>('textRecognition.detectText', {
          'imagePath': imagePath,
          'includeAllConfidenceScores': includeAllConfidenceScores,
          'requestId': requestId,
        });
    return result ?? const {};
  }

  Future<Map<dynamic, dynamic>> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) async {
    final result = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
      'textRecognition.detectTextRegions',
      {'imagePath': imagePath, 'requestId': requestId},
    );
    return result ?? const {};
  }

  Future<void> cancelRequest(String requestId) {
    return _methodChannel.invokeMethod<void>('textRecognition.cancelRequest', {
      'requestId': requestId,
    });
  }
}
