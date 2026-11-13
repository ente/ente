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
  }) async {
    final result = await _methodChannel
        .invokeMapMethod<dynamic, dynamic>('textRecognition.detectText', {
          'imagePath': imagePath,
          'includeAllConfidenceScores': includeAllConfidenceScores,
        });
    return result ?? const {};
  }

  Future<Map<dynamic, dynamic>> detectTextRegions({
    required String imagePath,
  }) async {
    final result = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
      'textRecognition.detectTextRegions',
      {'imagePath': imagePath},
    );
    return result ?? const {};
  }
}
