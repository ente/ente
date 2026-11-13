import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:native_video_editor/native_video_editor.dart';
import 'package:photos/ui/tools/editor/video_crop_util.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';

class NativeVideoExportService {
  static Future<File> exportVideo({
    required VideoEditorController controller,
    required String outputPath,
    void Function(double)? onProgress,
    void Function(Object, StackTrace)? onError,
  }) async {
    try {
      final result = await _performNativeOperations(
        outputPath: outputPath,
        controller: controller,
        onProgress: onProgress,
      );
      return File(result.outputPath);
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      rethrow;
    }
  }

  static Future<VideoEditResult> _performNativeOperations({
    required String outputPath,
    required VideoEditorController controller,
    void Function(double)? onProgress,
  }) async {
    final inputPath = controller.file.path;
    final needsCrop =
        controller.minCrop != Offset.zero ||
        controller.maxCrop != const Offset(1.0, 1.0);
    final needsRotate = controller.rotation != 0;
    final needsTrim = controller.isTrimmed;
    final needsSpeed = controller.speed != 1.0;

    if (!(needsCrop || needsRotate || needsTrim || needsSpeed)) {
      await File(inputPath).copy(outputPath);
      return VideoEditResult(outputPath: outputPath, isReEncoded: false);
    }

    Rect? cropRect;
    if (needsCrop) {
      cropRect = VideoCropUtil.calculateDisplaySpaceCropRect(
        controller: controller,
      );
    }

    return NativeVideoEditor.processVideo(
      inputPath: inputPath,
      outputPath: outputPath,
      trimStart: needsTrim ? controller.startTrim : null,
      trimEnd: needsTrim ? controller.endTrim : null,
      rotateDegrees: needsRotate ? controller.rotation : null,
      cropRect: cropRect,
      speed: controller.speed,
      onProgress: onProgress,
    );
  }
}
