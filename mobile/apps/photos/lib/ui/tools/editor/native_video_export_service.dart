import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:native_video_editor/native_video_editor.dart';
import 'package:photos/ui/tools/editor/export_video_service.dart';
import 'package:photos/ui/tools/editor/video_crop_util.dart';
import 'package:video_editor/video_editor.dart';

/// Service that uses native video editing operations when possible
/// Falls back to FFmpeg for operations that require re-encoding
class NativeVideoExportService {
  static const Duration _nativeFallbackThreshold = Duration(seconds: 3);

  /// Export video using native operations
  ///
  /// [allowFfmpegFallback] - If true (default), automatically falls back to
  /// FFmpeg if native export fails quickly. Set to false to test native-only
  /// processing (useful for integration tests).
  static Future<File> exportVideo({
    required VideoEditorController controller,
    required String outputPath,
    void Function(double)? onProgress,
    void Function(Object, StackTrace)? onError,
    bool allowFfmpegFallback = true,
  }) async {
    final startTime = DateTime.now();
    try {
      final inputPath = controller.file.path;

      // Always use the unified native operations path
      final result = await _performNativeOperations(
        inputPath: inputPath,
        outputPath: outputPath,
        controller: controller,
        onProgress: onProgress,
      );

      return File(result.outputPath);
    } catch (error, stackTrace) {
      final elapsed = DateTime.now().difference(startTime);

      if (onError != null) {
        onError(error, stackTrace);
      }

      // If native export fails quickly, attempt FFmpeg fallback automatically
      // (only if fallback is enabled)
      if (allowFfmpegFallback && elapsed <= _nativeFallbackThreshold) {
        return await ExportService.exportVideo(
          controller: controller,
          outputPath: outputPath,
          onProgress: onProgress,
          onError: onError,
        );
      }

      rethrow;
    }
  }

  /// Perform native video operations
  static Future<VideoEditResult> _performNativeOperations({
    required String inputPath,
    required String outputPath,
    required VideoEditorController controller,
    void Function(double)? onProgress,
  }) async {
    // Use the combined native path only when needed; otherwise do a fast copy.
    // Note: despite legacy comments, Android cropping is supported via Media3
    // Transformer, so we keep native for crop/trim/rotate combinations.
    final needsCrop =
        controller.minCrop != Offset.zero ||
        controller.maxCrop != const Offset(1.0, 1.0);
    final needsRotate = controller.rotation != 0;
    final needsTrim = controller.isTrimmed;

    if (!(needsCrop || needsRotate || needsTrim)) {
      await File(inputPath).copy(outputPath);
      return VideoEditResult(
        outputPath: outputPath,
        isReEncoded: false,
        processingTime: Duration.zero,
      );
    }

    Duration? trimStart;
    Duration? trimEnd;
    if (needsTrim) {
      trimStart = controller.startTrim;
      trimEnd = controller.endTrim;
    }

    final int? rotateDegrees = needsRotate ? controller.rotation : null;
    Rect? cropRect;
    if (needsCrop) {
      // Always compute a display-space crop; both iOS & Android plugins
      // take display coordinates and do the right transform internally.
      final displayCrop = VideoCropUtil.calculateDisplaySpaceCropRect(
        controller: controller,
      );
      if (displayCrop.width <= 0 || displayCrop.height <= 0) {
        throw ArgumentError('Invalid crop rectangle computed: $displayCrop');
      }
      cropRect = displayCrop;
    }

    final result = await NativeVideoEditor.processVideo(
      inputPath: inputPath,
      outputPath: outputPath,
      trimStart: trimStart,
      trimEnd: trimEnd,
      rotateDegrees: rotateDegrees,
      cropRect: cropRect,
      onProgress: onProgress,
    );
    return result;
  }

  /// Get video information using native methods
  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    try {
      return await NativeVideoEditor.getVideoInfo(videoPath);
    } catch (e) {
      // Fallback to MediaInfo or FFprobe if needed
      return {};
    }
  }

  /// Cancel any ongoing export operation
  static Future<void> cancelExport() async {
    try {
      // Cancel native operation
      await NativeVideoEditor.cancelProcessing();
    } catch (e) {
      // Silently fail
    }
  }

  // No extra helpers needed; crop mapping is centralized in VideoCropUtil
}
