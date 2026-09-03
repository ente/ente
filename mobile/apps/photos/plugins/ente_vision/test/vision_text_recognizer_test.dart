import 'package:ente_vision/ente_vision.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.ente.photos.vision/text_recognition');
  final recognizer = VisionTextRecognizer(methodChannel: channel);
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall call) reply = (_) async => null;

  setUp(() {
    calls.clear();
    reply = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return reply(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('detectText sends its arguments and returns the native map', () async {
    final payload = {
      'blocks': [
        {
          'text': 'hello',
          'confidence': 0.9,
          'points': [
            {'x': 1.0, 'y': 2.0},
            {'x': 10.0, 'y': 2.0},
            {'x': 10.0, 'y': 8.0},
            {'x': 1.0, 'y': 8.0},
          ],
          'characters': <Object?>[],
        },
      ],
      'imageWidth': 640,
      'imageHeight': 480,
    };
    reply = (_) async => payload;

    final result = await recognizer.detectText(
      imagePath: '/tmp/photo.jpg',
      requestId: 'request-1',
    );

    expect(calls.single.method, 'textRecognition.detectText');
    expect(calls.single.arguments, {
      'imagePath': '/tmp/photo.jpg',
      'includeAllConfidenceScores': false,
      'requestId': 'request-1',
    });
    expect(result, payload);
  });

  test('detectText forwards includeAllConfidenceScores', () async {
    await recognizer.detectText(
      imagePath: '/tmp/photo.jpg',
      includeAllConfidenceScores: true,
    );

    expect(calls.single.arguments, {
      'imagePath': '/tmp/photo.jpg',
      'includeAllConfidenceScores': true,
      'requestId': null,
    });
  });

  test(
    'detectTextRegions sends its arguments and returns the native map',
    () async {
      final payload = {
        'regions': [
          {
            'confidence': 0.75,
            'points': [
              {'x': 0.0, 'y': 0.0},
              {'x': 5.0, 'y': 0.0},
              {'x': 5.0, 'y': 3.0},
              {'x': 0.0, 'y': 3.0},
            ],
          },
        ],
        'imageWidth': 320,
        'imageHeight': 240,
      };
      reply = (_) async => payload;

      final result = await recognizer.detectTextRegions(
        imagePath: '/tmp/photo.jpg',
        requestId: 'request-2',
      );

      expect(calls.single.method, 'textRecognition.detectTextRegions');
      expect(calls.single.arguments, {
        'imagePath': '/tmp/photo.jpg',
        'requestId': 'request-2',
      });
      expect(result, payload);
    },
  );

  test('cancelRequest sends the request id', () async {
    await recognizer.cancelRequest('request-3');

    expect(calls.single.method, 'textRecognition.cancelRequest');
    expect(calls.single.arguments, {'requestId': 'request-3'});
  });

  test('a null native result becomes an empty map', () async {
    final result = await recognizer.detectText(imagePath: '/tmp/photo.jpg');

    expect(result, isEmpty);
  });

  test('platform exceptions propagate unchanged', () async {
    reply = (_) async =>
        throw PlatformException(code: 'CANCELLED', message: 'cancelled');

    await expectLater(
      recognizer.detectText(imagePath: '/tmp/photo.jpg', requestId: 'r'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'CANCELLED'),
      ),
    );
  });
}
