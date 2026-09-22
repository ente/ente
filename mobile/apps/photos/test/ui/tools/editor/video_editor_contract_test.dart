import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ui/tools/editor/export_video_service.dart';
import 'package:photos/ui/tools/editor/video_crop_util.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';

void main() {
  group('calculateDisplaySpaceCropRectFromData', () {
    test('keeps encoder dimensions even and within an odd-sized source', () {
      final crop = VideoCropUtil.calculateDisplaySpaceCropRectFromData(
        minCrop: const Offset(0.1, 0.1),
        maxCrop: const Offset(0.9, 0.9),
        videoSize: const Size(321, 241),
      );

      expect(crop.left, greaterThanOrEqualTo(0));
      expect(crop.top, greaterThanOrEqualTo(0));
      expect(crop.right, lessThanOrEqualTo(321));
      expect(crop.bottom, lessThanOrEqualTo(241));
      expect(crop.width.toInt().isEven, isTrue);
      expect(crop.height.toInt().isEven, isTrue);
    });

    test('preserves a full even-sized source', () {
      expect(
        VideoCropUtil.calculateDisplaySpaceCropRectFromData(
          minCrop: Offset.zero,
          maxCrop: const Offset(1, 1),
          videoSize: const Size(320, 180),
        ),
        const Rect.fromLTWH(0, 0, 320, 180),
      );
    });
  });

  group('buildFfmpegVideoFilters', () {
    test('crops before rotating and normalizes encoder dimensions', () {
      final filters = buildFfmpegVideoFilters(
        crop: CropCalculation(x: 10, y: 20, width: 301, height: 199),
        rotation: 90,
      );
      expect(filters, [
        'crop=301:199:10:20',
        'transpose=1',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      ]);
    });

    test('represents a half turn without transpose ambiguity', () {
      expect(buildFfmpegVideoFilters(crop: null, rotation: 180), [
        'hflip',
        'vflip',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
      ]);
    });

    test('applies speed after spatial edits', () {
      expect(buildFfmpegVideoFilters(crop: null, rotation: 90, speed: 2), [
        'transpose=1',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        'setpts=PTS/2.0',
      ]);
    });
  });

  test(
    'audio tempo scales the initial offset without stretching samples twice',
    () {
      expect(buildFfmpegAudioTempoFilters(0.25), [
        'atempo=0.5',
        'atempo=0.5',
        'asetpts=PTS-STARTPTS+STARTPTS/0.25',
      ]);
      expect(buildFfmpegAudioTempoFilters(2), [
        'atempo=2.0',
        'asetpts=PTS-STARTPTS+STARTPTS/2.0',
      ]);
      expect(buildFfmpegAudioTempoFilters(1), isEmpty);
    },
  );

  test('FFmpeg plan preserves file paths as structured arguments', () {
    final controller = VideoEditorController.file(
      File("/tmp/input video's source.mp4"),
    );
    addTearDown(controller.dispose);

    final plan = ExportService.createPlan(
      controller: controller,
      outputPath: '/tmp/output video.mp4',
    );

    expect(plan.arguments, contains("/tmp/input video's source.mp4"));
    expect(plan.arguments, contains('/tmp/output video.mp4'));
    expect(plan.arguments, containsAllInOrder(['-map', '0:a?']));
  });

  test('FFmpeg reads only the trimmed source before changing speed', () {
    final controller = VideoEditorController.file(File('/tmp/input.mp4'));
    addTearDown(controller.dispose);
    controller.updateSpeed(0.25);

    final plan = ExportService.createPlan(
      controller: controller,
      outputPath: '/tmp/output.mp4',
    );

    expect(plan.arguments, containsAllInOrder(['-t', '0.000000', '-i']));
    expect(
      plan.arguments,
      containsAllInOrder([
        '-vf',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2,setpts=PTS/0.25',
      ]),
    );
    expect(
      plan.arguments,
      containsAllInOrder([
        '-af',
        'atempo=0.5,atempo=0.5,asetpts=PTS-STARTPTS+STARTPTS/0.25',
      ]),
    );
  });
}
