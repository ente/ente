import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_editor/native_video_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('native_video_editor');
  late Directory directory;
  late File input;
  MethodCall? lastCall;
  Map<dynamic, dynamic>? extractionResultOverride;
  Map<dynamic, dynamic>? processResultOverride;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-video-test-');
    input = await File('${directory.path}/input.mp4').writeAsBytes([0]);
    extractionResultOverride = null;
    processResultOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          lastCall = call;
          switch (call.method) {
            case 'processVideo':
              final arguments = call.arguments as Map<dynamic, dynamic>;
              return processResultOverride ??
                  {'outputPath': arguments['outputPath'], 'isReEncoded': true};
            case 'getVideoInfo':
              return _videoInfoMap;
            case 'extractFrame':
            case 'extractTimeline':
              if (extractionResultOverride != null) {
                return extractionResultOverride;
              }
              final arguments = call.arguments as Map<dynamic, dynamic>;
              final outputPaths = call.method == 'extractFrame'
                  ? [arguments['outputPath'] as String]
                  : (arguments['outputPaths'] as List<dynamic>).cast<String>();
              return {
                'videoInfo': _videoInfoMap,
                'frames': [
                  for (var index = 0; index < outputPaths.length; index++)
                    {
                      'outputPath': outputPaths[index],
                      'width': 120,
                      'height': 90,
                    },
                ],
              };
            case 'cancelFrameExtraction':
              return null;
          }
          throw PlatformException(code: 'UNEXPECTED_METHOD');
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('inspectVideo returns normalized display metadata', () async {
    final info = await NativeVideoEditor.inspectVideo(input.path);

    expect(info.duration, const Duration(milliseconds: 4200));
    expect(info.width, 1920);
    expect(info.height, 1080);
    expect(info.displayWidth, 1080);
    expect(info.displayHeight, 1920);
    expect(info.rotationDegrees, 270);
    expect(info.bitrate, 8000000);
    expect(info.frameRate, 29.97);
  });

  test('non-quarter-turn metadata rotation is rejected', () {
    expect(
      () => NativeVideoInfo.fromMap({..._videoInfoMap, 'rotation': 45}),
      throwsFormatException,
    );
  });

  test('extractFrame sends bounded JPEG policy and parses result', () async {
    final output = '${directory.path}/frame.jpg';
    final extraction = await NativeVideoEditor.extractFrame(
      VideoFrameRequest(
        inputPath: input.path,
        outputPath: output,
        position: const Duration(milliseconds: 900),
        maxWidth: 320,
        maxHeight: 180,
        quality: 76,
        policy: VideoFramePolicy.precise,
      ),
    );

    expect(lastCall?.method, 'extractFrame');
    expect(lastCall?.arguments, containsPair('maxWidth', 320));
    expect(lastCall?.arguments, containsPair('maxHeight', 180));
    expect(lastCall?.arguments, containsPair('quality', 76));
    expect(lastCall?.arguments, containsPair('policy', 'precise'));
    expect(extraction.frames.single.outputPath, output);
    expect(extraction.frames.single.width, 120);
    expect(extraction.videoInfo.displayHeight, 1920);
  });

  test('extractTimeline preserves request and timestamp ordering', () async {
    final outputs = [
      '${directory.path}/0.jpg',
      '${directory.path}/1.jpg',
      '${directory.path}/2.jpg',
    ];
    final positions = [
      Duration.zero,
      const Duration(milliseconds: 2100),
      const Duration(milliseconds: 4199),
    ];

    final extraction = await NativeVideoEditor.extractTimeline(
      VideoTimelineRequest(
        requestId: 'trim-1',
        inputPath: input.path,
        outputPaths: outputs,
        positions: positions,
        maxWidth: 144,
        maxHeight: 120,
      ),
    );

    expect(lastCall?.arguments, containsPair('requestId', 'trim-1'));
    expect(
      extraction.frames.map((frame) => frame.outputPath),
      orderedEquals(outputs),
    );
  });

  test('invalid pixel bounds fail before invoking native code', () async {
    lastCall = null;

    await expectLater(
      NativeVideoEditor.extractFrame(
        VideoFrameRequest(
          inputPath: input.path,
          outputPath: '${directory.path}/invalid.jpg',
          position: Duration.zero,
          maxWidth: 0,
          maxHeight: 120,
        ),
      ),
      throwsArgumentError,
    );
    expect(lastCall, isNull);
  });

  test('timeline requires one destination for every timestamp', () async {
    await expectLater(
      NativeVideoEditor.extractTimeline(
        VideoTimelineRequest(
          requestId: 'trim-2',
          inputPath: input.path,
          outputPaths: ['${directory.path}/only-one.jpg'],
          positions: [Duration.zero, const Duration(seconds: 1)],
          maxWidth: 144,
          maxHeight: 120,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('timeline result must contain every requested frame', () async {
    extractionResultOverride = {
      'videoInfo': _videoInfoMap,
      'frames': const <Map<String, dynamic>>[],
    };

    await expectLater(
      NativeVideoEditor.extractTimeline(
        VideoTimelineRequest(
          requestId: 'trim-incomplete',
          inputPath: input.path,
          outputPaths: ['${directory.path}/expected.jpg'],
          positions: [Duration.zero],
          maxWidth: 144,
          maxHeight: 120,
        ),
      ),
      throwsFormatException,
    );
  });

  test('processing requires both trim boundaries', () async {
    lastCall = null;

    await expectLater(
      NativeVideoEditor.processVideo(
        inputPath: input.path,
        outputPath: '${directory.path}/output.mp4',
        trimStart: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(lastCall, isNull);
  });

  test('processing sends the requested speed', () async {
    await NativeVideoEditor.processVideo(
      inputPath: input.path,
      outputPath: '${directory.path}/output.mp4',
      speed: 0.25,
    );

    expect(lastCall?.arguments, containsPair('speed', 0.25));
  });

  test('processing result must match the requested output path', () async {
    processResultOverride = {
      'outputPath': '${directory.path}/wrong.mp4',
      'isReEncoded': true,
    };

    await expectLater(
      NativeVideoEditor.processVideo(
        inputPath: input.path,
        outputPath: '${directory.path}/expected.mp4',
      ),
      throwsFormatException,
    );
  });
}

const _videoInfoMap = <String, dynamic>{
  'duration': 4200,
  'width': 1920,
  'height': 1080,
  'displayWidth': 1080,
  'displayHeight': 1920,
  'rotation': -90,
  'bitrate': 8000000,
  'frameRate': 29.97,
};
