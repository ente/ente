import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:ffmpeg_kit_flutter/statistics.dart';
import 'package:photos/ui/tools/editor/video_crop_util.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';

class FfmpegVideoExportPlan {
  const FfmpegVideoExportPlan({
    required this.arguments,
    required this.outputPath,
    required this.duration,
  });

  final List<String> arguments;
  final String outputPath;
  final Duration duration;
}

class ExportService {
  static FfmpegVideoExportPlan createPlan({
    required VideoEditorController controller,
    required String outputPath,
  }) {
    CropCalculation? crop;
    if (controller.minCrop != Offset.zero ||
        controller.maxCrop != const Offset(1, 1)) {
      crop = VideoCropUtil.calculateFileSpaceCrop(controller: controller);
    }
    final filters = buildFfmpegVideoFilters(
      crop: crop,
      rotation: controller.rotation,
      speed: controller.speed,
    );
    final audioFilters = buildFfmpegAudioTempoFilters(controller.speed);

    final start = _seconds(controller.startTrim);
    final duration = _seconds(controller.trimmedDuration);
    final arguments = <String>[
      '-y',
      '-ss',
      start,
      '-t',
      duration,
      '-i',
      controller.file.path,
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      if (filters.isNotEmpty) ...['-vf', filters.join(',')],
      if (audioFilters.isNotEmpty) ...['-af', audioFilters.join(',')],
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-map_metadata',
      '0',
      '-metadata:s:v:0',
      'rotate=0',
      '-movflags',
      '+faststart',
      outputPath,
    ];
    return FfmpegVideoExportPlan(
      arguments: arguments,
      outputPath: outputPath,
      duration: controller.editedDuration,
    );
  }

  static Future<File> runFFmpegCommand(
    FfmpegVideoExportPlan plan, {
    void Function(double)? onProgress,
  }) async {
    final completer = Completer<File>();
    try {
      await FFmpegKit.executeWithArgumentsAsync(
        plan.arguments,
        (session) async {
          try {
            final returnCode = await session.getReturnCode();
            if (returnCode != null && ReturnCode.isSuccess(returnCode)) {
              final file = File(plan.outputPath);
              if (!await file.exists() || await file.length() == 0) {
                completer.completeError(
                  StateError('FFmpeg produced no output at ${plan.outputPath}'),
                );
              } else {
                completer.complete(file);
              }
              return;
            }
            final output = await session.getOutput();
            completer.completeError(
              StateError(
                'FFmpeg exited with ${returnCode?.getValue() ?? -1}: $output',
              ),
            );
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        null,
        (statistics) {
          if (onProgress != null) {
            onProgress(_progress(statistics, plan.duration));
          }
        },
      );
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  static Future<File> exportVideo({
    required VideoEditorController controller,
    required String outputPath,
    void Function(double)? onProgress,
    void Function(Object, StackTrace)? onError,
  }) async {
    try {
      return await runFFmpegCommand(
        createPlan(controller: controller, outputPath: outputPath),
        onProgress: onProgress,
      );
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      rethrow;
    }
  }

  static double _progress(Statistics statistics, Duration duration) {
    if (duration.inMilliseconds <= 0) return 0;
    return (statistics.getTime() / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  static String _seconds(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerSecond)
          .toStringAsFixed(6);
}

List<String> buildFfmpegVideoFilters({
  required CropCalculation? crop,
  required int rotation,
  double speed = 1.0,
}) {
  final filters = <String>[];
  if (crop != null) filters.add(crop.toFFmpegFilter());
  switch (rotation) {
    case 0:
      break;
    case 90:
      filters.add('transpose=1');
    case 180:
      filters.add('hflip');
      filters.add('vflip');
    case 270:
      filters.add('transpose=2');
    default:
      throw ArgumentError.value(rotation, 'rotation');
  }
  filters.add('scale=trunc(iw/2)*2:trunc(ih/2)*2');
  if (speed != 1.0) {
    filters.add('setpts=PTS/$speed');
  }
  return filters;
}

List<String> buildFfmpegAudioTempoFilters(double speed) {
  if (!speed.isFinite || speed <= 0) {
    throw ArgumentError.value(speed, 'speed');
  }
  if (speed == 1.0) return [];

  final filters = <String>[];
  var remaining = speed;
  while (remaining < 0.5) {
    filters.add('atempo=0.5');
    remaining /= 0.5;
  }
  while (remaining > 2.0) {
    filters.add('atempo=2.0');
    remaining /= 2.0;
  }
  filters.add('atempo=$remaining');
  filters.add('asetpts=PTS-STARTPTS+STARTPTS/$speed');
  return filters;
}
