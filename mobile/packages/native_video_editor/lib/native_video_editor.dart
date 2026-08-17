import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

String _normalizedPath(String path) =>
    File(path).absolute.uri.normalizePath().toFilePath();

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

  const VideoEditResult({required this.outputPath, required this.isReEncoded});
}

enum VideoFramePolicy { precise, nearestSync }

class NativeVideoInfo {
  const NativeVideoInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.displayWidth,
    required this.displayHeight,
    required this.rotationDegrees,
    this.bitrate,
    this.frameRate,
  });

  factory NativeVideoInfo.fromMap(Map<dynamic, dynamic> map) {
    int requiredInt(String key) {
      final value = map[key];
      if (value is! num) {
        throw FormatException('Missing numeric video metadata: $key');
      }
      return value.toInt();
    }

    int? positiveInt(String key) {
      final value = map[key];
      if (value is! num || value <= 0) return null;
      return value.toInt();
    }

    double? positiveDouble(String key) {
      final value = map[key];
      if (value is! num || value <= 0) return null;
      return value.toDouble();
    }

    final rotation = requiredInt('rotation') % 360;
    final normalizedRotation = rotation < 0 ? rotation + 360 : rotation;
    final durationMs = requiredInt('duration');
    final width = requiredInt('width');
    final height = requiredInt('height');
    final displayWidth = requiredInt('displayWidth');
    final displayHeight = requiredInt('displayHeight');
    if (durationMs < 0 ||
        width <= 0 ||
        height <= 0 ||
        displayWidth <= 0 ||
        displayHeight <= 0) {
      throw const FormatException('Video metadata contains invalid dimensions');
    }
    if (!const {0, 90, 180, 270}.contains(normalizedRotation)) {
      throw const FormatException('Video metadata has unsupported rotation');
    }
    return NativeVideoInfo(
      duration: Duration(milliseconds: durationMs),
      width: width,
      height: height,
      displayWidth: displayWidth,
      displayHeight: displayHeight,
      rotationDegrees: normalizedRotation,
      bitrate: positiveInt('bitrate'),
      frameRate: positiveDouble('frameRate'),
    );
  }

  final Duration duration;
  final int width;
  final int height;
  final int displayWidth;
  final int displayHeight;

  // Clockwise quarter-turn rotation required to display encoded pixels.
  final int rotationDegrees;
  final int? bitrate;
  final double? frameRate;
}

class VideoFrameRequest {
  const VideoFrameRequest({
    required this.inputPath,
    required this.outputPath,
    required this.position,
    required this.maxWidth,
    required this.maxHeight,
    this.quality = 80,
    this.policy = VideoFramePolicy.nearestSync,
  });

  final String inputPath;
  final String outputPath;
  final Duration position;
  final int maxWidth;
  final int maxHeight;
  final int quality;
  final VideoFramePolicy policy;

  Map<String, dynamic> toMap() => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'positionMs': position.inMilliseconds,
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
    'quality': quality,
    'policy': policy.name,
  };
}

class VideoFrameResult {
  const VideoFrameResult({
    required this.outputPath,
    required this.width,
    required this.height,
  });

  factory VideoFrameResult.fromMap(
    Map<dynamic, dynamic> map, {
    required String expectedOutputPath,
    required int maxWidth,
    required int maxHeight,
  }) {
    final outputPath = map['outputPath'];
    final width = map['width'];
    final height = map['height'];
    if (outputPath is! String || width is! num || height is! num) {
      throw const FormatException('Frame result is missing required values');
    }
    final parsedWidth = width.toInt();
    final parsedHeight = height.toInt();
    if (_normalizedPath(outputPath) != _normalizedPath(expectedOutputPath)) {
      throw const FormatException('Frame result has an unexpected output path');
    }
    if (parsedWidth <= 0 ||
        parsedHeight <= 0 ||
        parsedWidth > maxWidth ||
        parsedHeight > maxHeight) {
      throw const FormatException('Frame result has invalid dimensions');
    }
    return VideoFrameResult(
      outputPath: outputPath,
      width: parsedWidth,
      height: parsedHeight,
    );
  }

  final String outputPath;
  final int width;
  final int height;
}

class VideoFrameExtractionResult {
  const VideoFrameExtractionResult({
    required this.videoInfo,
    required this.frames,
  });

  factory VideoFrameExtractionResult.fromMap(
    Map<dynamic, dynamic> map, {
    required List<String> expectedOutputPaths,
    required int maxWidth,
    required int maxHeight,
  }) {
    final frameMaps = map['frames'];
    final videoInfo = map['videoInfo'];
    if (frameMaps is! List<dynamic> ||
        frameMaps.length != expectedOutputPaths.length ||
        videoInfo is! Map<dynamic, dynamic>) {
      throw const FormatException(
        'Frame extraction returned an invalid result',
      );
    }
    return VideoFrameExtractionResult(
      videoInfo: NativeVideoInfo.fromMap(videoInfo),
      frames: [
        for (var index = 0; index < frameMaps.length; index++)
          VideoFrameResult.fromMap(
            frameMaps[index] as Map<dynamic, dynamic>,
            expectedOutputPath: expectedOutputPaths[index],
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
      ],
    );
  }

  final NativeVideoInfo videoInfo;
  final List<VideoFrameResult> frames;
}

class VideoTimelineRequest {
  const VideoTimelineRequest({
    required this.requestId,
    required this.inputPath,
    required this.outputPaths,
    required this.positions,
    required this.maxWidth,
    required this.maxHeight,
    this.quality = 70,
    this.policy = VideoFramePolicy.nearestSync,
  });

  final String requestId;
  final String inputPath;
  final List<String> outputPaths;
  final List<Duration> positions;
  final int maxWidth;
  final int maxHeight;
  final int quality;
  final VideoFramePolicy policy;

  Map<String, dynamic> toMap() => {
    'requestId': requestId,
    'inputPath': inputPath,
    'outputPaths': outputPaths,
    'positionsMs': positions
        .map((position) => position.inMilliseconds)
        .toList(),
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
    'quality': quality,
    'policy': policy.name,
  };
}

class NativeVideoEditor {
  static const MethodChannel _channel = MethodChannel('native_video_editor');
  static const EventChannel _progressChannel = EventChannel(
    'native_video_editor/progress',
  );

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
    _validateOutputPath(inputPath: inputPath, outputPath: outputPath);
    _ensureOutputDirectoryExists(outputPath);
    if ((trimStart == null) != (trimEnd == null)) {
      throw ArgumentError('trimStart and trimEnd must be provided together');
    }
    if (trimStart != null && (trimStart.isNegative || trimStart >= trimEnd!)) {
      throw ArgumentError(
        'trimStart must be non-negative and earlier than trimEnd',
      );
    }
    if (rotateDegrees != null && rotateDegrees != 0) {
      _validateRotationDegrees(rotateDegrees);
    }
    if (cropRect != null &&
        (!cropRect.left.isFinite ||
            !cropRect.top.isFinite ||
            !cropRect.width.isFinite ||
            !cropRect.height.isFinite ||
            cropRect.left < 0 ||
            cropRect.top < 0 ||
            cropRect.width < 1 ||
            cropRect.height < 1 ||
            cropRect.left != cropRect.left.truncateToDouble() ||
            cropRect.top != cropRect.top.truncateToDouble() ||
            cropRect.width != cropRect.width.truncateToDouble() ||
            cropRect.height != cropRect.height.truncateToDouble())) {
      throw ArgumentError('cropRect must contain positive whole pixels');
    }

    final params = <String, dynamic>{
      'inputPath': inputPath,
      'outputPath': outputPath,
      if (trimStart != null) ...{
        'trimStartMs': trimStart.inMilliseconds,
        'trimEndMs': trimEnd!.inMilliseconds,
      },
      'rotateDegrees': ?rotateDegrees,
      if (cropRect != null) ...{
        'cropX': cropRect.left.toInt(),
        'cropY': cropRect.top.toInt(),
        'cropWidth': cropRect.width.toInt(),
        'cropHeight': cropRect.height.toInt(),
      },
    };
    final progressSubscription = onProgress == null
        ? null
        : _progressChannel.receiveBroadcastStream().listen((dynamic event) {
            if (event is num) onProgress(event.toDouble());
          }, onError: (_) {});
    try {
      final result = await _invokeMap(
        'processVideo',
        params,
        operation: 'process video',
      );
      final resultOutputPath = result['outputPath'];
      final isReEncoded = result['isReEncoded'];
      if (resultOutputPath is! String ||
          isReEncoded is! bool ||
          _normalizedPath(resultOutputPath) != _normalizedPath(outputPath)) {
        throw const FormatException(
          'Video processing returned an invalid result',
        );
      }
      return VideoEditResult(
        outputPath: resultOutputPath,
        isReEncoded: isReEncoded,
      );
    } finally {
      await progressSubscription?.cancel();
    }
  }

  static Future<VideoFrameExtractionResult> extractFrame(
    VideoFrameRequest request,
  ) async {
    _validateFrameRequest(request);
    final result = await _invokeMap(
      'extractFrame',
      request.toMap(),
      operation: 'extract video frame',
    );
    return VideoFrameExtractionResult.fromMap(
      result,
      expectedOutputPaths: [request.outputPath],
      maxWidth: request.maxWidth,
      maxHeight: request.maxHeight,
    );
  }

  static Future<VideoFrameExtractionResult> extractTimeline(
    VideoTimelineRequest request,
  ) async {
    _ensureInputPathExists(request.inputPath);
    if (request.requestId.isEmpty) {
      throw ArgumentError.value(request.requestId, 'requestId', 'is empty');
    }
    if (request.positions.isEmpty) {
      throw ArgumentError.value(request.positions, 'positions', 'is empty');
    }
    if (request.positions.length != request.outputPaths.length) {
      throw ArgumentError('positions and outputPaths must have equal lengths');
    }
    _validateFrameOptions(
      maxWidth: request.maxWidth,
      maxHeight: request.maxHeight,
      quality: request.quality,
    );
    final outputPaths = <String>{};
    for (var index = 0; index < request.positions.length; index++) {
      if (request.positions[index].isNegative) {
        throw ArgumentError.value(
          request.positions[index],
          'positions[$index]',
          'is negative',
        );
      }
      _validateOutputPath(
        inputPath: request.inputPath,
        outputPath: request.outputPaths[index],
      );
      final absoluteOutputPath = _normalizedPath(request.outputPaths[index]);
      if (!outputPaths.add(absoluteOutputPath)) {
        throw ArgumentError.value(
          request.outputPaths[index],
          'outputPaths[$index]',
          'is duplicated',
        );
      }
      _ensureOutputDirectoryExists(request.outputPaths[index]);
    }

    final result = await _invokeMap(
      'extractTimeline',
      request.toMap(),
      operation: 'extract video timeline',
    );
    return VideoFrameExtractionResult.fromMap(
      result,
      expectedOutputPaths: request.outputPaths,
      maxWidth: request.maxWidth,
      maxHeight: request.maxHeight,
    );
  }

  static Future<void> cancelFrameExtraction(String requestId) async {
    if (requestId.isEmpty) return;
    await _invokeVoid('cancelFrameExtraction', {
      'requestId': requestId,
    }, operation: 'cancel frame extraction');
  }

  static Future<NativeVideoInfo> inspectVideo(String videoPath) async {
    _ensureInputPathExists(videoPath);
    final result = await _invokeMap('getVideoInfo', {
      'videoPath': videoPath,
    }, operation: 'inspect video');
    return NativeVideoInfo.fromMap(result);
  }

  static Future<void> cancelProcessing() async {
    await _invokeVoid('cancelProcessing', null, operation: 'cancel processing');
  }

  static Future<Map<dynamic, dynamic>> _invokeMap(
    String method,
    Map<String, dynamic> arguments, {
    required String operation,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        arguments,
      );
      if (result == null) {
        throw NativeVideoEditorException('Failed to $operation: no result');
      }
      return result;
    } on PlatformException catch (error) {
      throw _platformException(operation, error);
    }
  }

  static Future<void> _invokeVoid(
    String method,
    Map<String, dynamic>? arguments, {
    required String operation,
  }) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw _platformException(operation, error);
    }
  }

  static NativeVideoEditorException _platformException(
    String operation,
    PlatformException error,
  ) => NativeVideoEditorException(
    'Failed to $operation: ${error.message}',
    code: error.code,
    details: error.details,
    cause: error,
  );

  static void _ensureInputPathExists(String inputPath) {
    if (!File(inputPath).existsSync()) {
      throw ArgumentError('Input file does not exist: $inputPath');
    }
  }

  static void _validateFrameRequest(VideoFrameRequest request) {
    _ensureInputPathExists(request.inputPath);
    if (request.position.isNegative) {
      throw ArgumentError.value(request.position, 'position', 'is negative');
    }
    _validateOutputPath(
      inputPath: request.inputPath,
      outputPath: request.outputPath,
    );
    _ensureOutputDirectoryExists(request.outputPath);
    _validateFrameOptions(
      maxWidth: request.maxWidth,
      maxHeight: request.maxHeight,
      quality: request.quality,
    );
  }

  static void _validateFrameOptions({
    required int maxWidth,
    required int maxHeight,
    required int quality,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) {
      throw ArgumentError('maxWidth and maxHeight must both be positive');
    }
    if (quality < 1 || quality > 100) {
      throw RangeError.range(quality, 1, 100, 'quality');
    }
  }

  static void _ensureOutputDirectoryExists(String outputPath) {
    final parent = File(outputPath).parent;
    if (!parent.existsSync()) {
      throw ArgumentError('Output directory does not exist: ${parent.path}');
    }
  }

  static void _validateOutputPath({
    required String inputPath,
    required String outputPath,
  }) {
    if (_normalizedPath(inputPath) == _normalizedPath(outputPath)) {
      throw ArgumentError('Output path must differ from the input path');
    }
  }

  static void _validateRotationDegrees(int degrees) {
    if (degrees != 90 && degrees != 180 && degrees != 270) {
      throw ArgumentError('Rotation degrees must be 90, 180, or 270');
    }
  }
}
