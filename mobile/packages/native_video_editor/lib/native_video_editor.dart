import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class NativeVideoEditorException implements Exception {
  NativeVideoEditorException(
    this.message, {
    this.code,
    this.details,
    this.cause,
  });

  final String message;
  final String? code;
  final Object? details;
  final Object? cause;

  @override
  String toString() =>
      'NativeVideoEditorException(message: $message, code: $code, details: $details)';
}

class VideoEditResult {
  final String outputPath;
  final bool isReEncoded;
  final Duration? processingTime;

  VideoEditResult({
    required this.outputPath,
    required this.isReEncoded,
    this.processingTime,
  });
}

class VideoTrimParams {
  final String inputPath;
  final String outputPath;
  final Duration startTime;
  final Duration endTime;

  VideoTrimParams({
    required this.inputPath,
    required this.outputPath,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'startTimeMs': startTime.inMilliseconds,
    'endTimeMs': endTime.inMilliseconds,
  };
}

class VideoRotateParams {
  final String inputPath;
  final String outputPath;
  final int degrees; // Must be 90, 180, or 270

  VideoRotateParams({
    required this.inputPath,
    required this.outputPath,
    required this.degrees,
  }) : assert(degrees == 90 || degrees == 180 || degrees == 270);

  Map<String, dynamic> toMap() => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'degrees': degrees,
  };
}

class VideoCropParams {
  final String inputPath;
  final String outputPath;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool forceReEncode;

  VideoCropParams({
    required this.inputPath,
    required this.outputPath,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.forceReEncode = false,
  });

  Map<String, dynamic> toMap() => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'forceReEncode': forceReEncode,
  };
}

class NativeVideoEditor {
  static const MethodChannel _channel = MethodChannel('native_video_editor');
  static const EventChannel _progressChannel = EventChannel(
    'native_video_editor/progress',
  );

  /// Trim video without re-encoding when possible
  /// Returns the output file path
  static Future<VideoEditResult> trimVideo(VideoTrimParams params) async {
    _ensureInputPathExists(params.inputPath);
    if (params.startTime >= params.endTime) {
      throw ArgumentError('startTime must be earlier than endTime');
    }

    try {
      final stopwatch = Stopwatch()..start();

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'trimVideo',
        params.toMap(),
      );

      stopwatch.stop();

      if (result == null) {
        throw Exception('Failed to trim video: no result');
      }

      return VideoEditResult(
        outputPath: result['outputPath'] as String,
        isReEncoded: result['isReEncoded'] as bool? ?? false,
        processingTime: stopwatch.elapsed,
      );
    } on PlatformException catch (e) {
      throw NativeVideoEditorException(
        'Failed to trim video: ${e.message}',
        code: e.code,
        details: e.details,
        cause: e,
      );
    }
  }

  /// Rotate video using metadata when possible (Android) or transform (iOS)
  /// Avoids re-encoding when possible
  static Future<VideoEditResult> rotateVideo(VideoRotateParams params) async {
    _ensureInputPathExists(params.inputPath);
    _validateRotationDegrees(params.degrees);

    try {
      final stopwatch = Stopwatch()..start();

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'rotateVideo',
        params.toMap(),
      );

      stopwatch.stop();

      if (result == null) {
        throw Exception('Failed to rotate video: no result');
      }

      return VideoEditResult(
        outputPath: result['outputPath'] as String,
        isReEncoded: result['isReEncoded'] as bool? ?? false,
        processingTime: stopwatch.elapsed,
      );
    } on PlatformException catch (e) {
      throw NativeVideoEditorException(
        'Failed to rotate video: ${e.message}',
        code: e.code,
        details: e.details,
        cause: e,
      );
    }
  }

  /// Crop video - may require re-encoding depending on the format
  static Future<VideoEditResult> cropVideo(VideoCropParams params) async {
    _ensureInputPathExists(params.inputPath);
    _validateCropDimensions(params.width, params.height);

    try {
      final stopwatch = Stopwatch()..start();

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'cropVideo',
        params.toMap(),
      );

      stopwatch.stop();

      if (result == null) {
        throw Exception('Failed to crop video: no result');
      }

      return VideoEditResult(
        outputPath: result['outputPath'] as String,
        isReEncoded: result['isReEncoded'] as bool? ?? true,
        processingTime: stopwatch.elapsed,
      );
    } on PlatformException catch (e) {
      throw NativeVideoEditorException(
        'Failed to crop video: ${e.message}',
        code: e.code,
        details: e.details,
        cause: e,
      );
    }
  }

  /// Combined operation: trim, rotate, and crop in a single pass
  /// More efficient when multiple operations are needed
  static Future<VideoEditResult> processVideo({
    required String inputPath,
    required String outputPath,
    Duration? trimStart,
    Duration? trimEnd,
    int? rotateDegrees,
    Rect? cropRect,
    void Function(double progress)? onProgress,
  }) async {
    _ensureInputPathExists(inputPath);
    if (trimStart != null && trimEnd != null && trimStart >= trimEnd) {
      throw ArgumentError('trimStart must be earlier than trimEnd');
    }
    if (rotateDegrees != null && rotateDegrees != 0) {
      _validateRotationDegrees(rotateDegrees);
    }
    if (cropRect != null && (cropRect.width <= 0 || cropRect.height <= 0)) {
      throw ArgumentError('cropRect must have positive width and height');
    }

    try {
      final stopwatch = Stopwatch()..start();

      final params = <String, dynamic>{
        'inputPath': inputPath,
        'outputPath': outputPath,
      };

      if (trimStart != null && trimEnd != null) {
        params['trimStartMs'] = trimStart.inMilliseconds;
        params['trimEndMs'] = trimEnd.inMilliseconds;
      }

      if (rotateDegrees != null) {
        params['rotateDegrees'] = rotateDegrees;
      }

      if (cropRect != null) {
        params['cropX'] = cropRect.left.toInt();
        params['cropY'] = cropRect.top.toInt();
        params['cropWidth'] = cropRect.width.toInt();
        params['cropHeight'] = cropRect.height.toInt();
      }

      StreamSubscription? progressSubscription;
      if (onProgress != null) {
        progressSubscription = _progressChannel.receiveBroadcastStream().listen(
          (dynamic event) {
            if (event is double) {
              onProgress(event);
            } else if (event is int) {
              onProgress(event.toDouble());
            }
          },
          onError: (error) {},
        );
      }

      try {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'processVideo',
          params,
        );

        stopwatch.stop();

        if (result == null) {
          throw Exception('Failed to process video: no result');
        }

        return VideoEditResult(
          outputPath: result['outputPath'] as String,
          isReEncoded: result['isReEncoded'] as bool? ?? false,
          processingTime: stopwatch.elapsed,
        );
      } finally {
        await progressSubscription?.cancel();
      }
    } on PlatformException catch (e) {
      throw NativeVideoEditorException(
        'Failed to process video: ${e.message}',
        code: e.code,
        details: e.details,
        cause: e,
      );
    }
  }

  /// Get video information without processing
  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVideoInfo',
        {'videoPath': videoPath},
      );

      if (result == null) {
        throw Exception('Failed to get video info: no result');
      }

      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw NativeVideoEditorException(
        'Failed to get video info: ${e.message}',
        code: e.code,
        details: e.details,
        cause: e,
      );
    }
  }

  /// Cancel any ongoing video processing
  static Future<void> cancelProcessing() async {
    try {
      await _channel.invokeMethod('cancelProcessing');
    } on PlatformException catch (e) {
      throw NativeVideoEditorException(
        'Failed to cancel processing: ${e.message}',
        code: e.code,
        details: e.details,
        cause: e,
      );
    }
  }

  static void _ensureInputPathExists(String inputPath) {
    if (!File(inputPath).existsSync()) {
      throw ArgumentError('Input file does not exist: $inputPath');
    }
  }

  static void _validateRotationDegrees(int degrees) {
    if (degrees != 90 && degrees != 180 && degrees != 270) {
      throw ArgumentError('Rotation degrees must be 90, 180, or 270');
    }
  }

  static void _validateCropDimensions(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Crop dimensions must be greater than zero');
    }
  }
}
