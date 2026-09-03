import "package:ente_vision/ente_vision.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/services/machine_learning/ocr/vision_ocr_backend.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("io.ente.photos.vision/text_recognition");
  final backend = VisionOcrBackend(
    recognizer: VisionTextRecognizer(methodChannel: channel),
  );
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

  test("prepareModels is ready without downloading anything", () async {
    final status = await backend.prepareModels(
      OcrModelComponent.values.toSet(),
    );

    expect(status.isReady, isTrue);
    expect(status.version, "iOS-Vision");
    expect(status.modelPath, "system");
    expect(calls, isEmpty);
  });

  test("detectText forwards its arguments and parses the result", () async {
    reply = (_) async => {
      "blocks": [
        {
          "text": "hello",
          "confidence": 0.9,
          "points": [
            {"x": 1.0, "y": 2.0},
            {"x": 10.0, "y": 2.0},
            {"x": 10.0, "y": 8.0},
            {"x": 1.0, "y": 8.0},
          ],
          "characters": <Object?>[],
        },
      ],
      "imageWidth": 640,
      "imageHeight": 480,
    };

    final result = await backend.detectText(
      imagePath: "/tmp/photo.jpg",
      includeAllConfidenceScores: true,
      requestId: "request-1",
    );

    expect(calls.single.method, "textRecognition.detectText");
    expect(calls.single.arguments, {
      "imagePath": "/tmp/photo.jpg",
      "includeAllConfidenceScores": true,
      "requestId": "request-1",
    });
    expect(result.blocks.single.text, "hello");
    expect(result.blocks.single.boundingBox, const Rect.fromLTRB(1, 2, 10, 8));
    expect(result.imageSize, const Size(640, 480));
  });

  test(
    "detectTextRegions forwards its arguments and parses the result",
    () async {
      reply = (_) async => {
        "regions": [
          {
            "confidence": 0.75,
            "points": [
              {"x": 0.0, "y": 0.0},
              {"x": 5.0, "y": 0.0},
              {"x": 5.0, "y": 3.0},
              {"x": 0.0, "y": 3.0},
            ],
          },
        ],
        "imageWidth": 320,
        "imageHeight": 240,
      };

      final result = await backend.detectTextRegions(
        imagePath: "/tmp/photo.jpg",
        requestId: "request-2",
      );

      expect(calls.single.method, "textRecognition.detectTextRegions");
      expect(calls.single.arguments, {
        "imagePath": "/tmp/photo.jpg",
        "requestId": "request-2",
      });
      expect(result.regions.single.confidence, 0.75);
      expect(result.imageSize, const Size(320, 240));
    },
  );

  test("an empty native result becomes an empty detection", () async {
    final result = await backend.detectText(imagePath: "/tmp/photo.jpg");

    expect(result.blocks, isEmpty);
    expect(result.imageSize, Size.zero);
  });

  test("cancelRequest forwards the request id", () async {
    await backend.cancelRequest("request-3");

    expect(calls.single.method, "textRecognition.cancelRequest");
    expect(calls.single.arguments, {"requestId": "request-3"});
  });

  test("platform exceptions become OcrExceptions", () async {
    reply = (_) async => throw PlatformException(
      code: "IMAGE_DECODE_ERROR",
      message: "Failed to decode image",
      details: {"path": "/tmp/photo.jpg"},
    );

    await expectLater(
      backend.detectText(imagePath: "/tmp/photo.jpg"),
      throwsA(
        isA<OcrException>()
            .having((e) => e.code, "code", "IMAGE_DECODE_ERROR")
            .having((e) => e.message, "message", "Failed to decode image")
            .having((e) => e.details, "details", {"path": "/tmp/photo.jpg"}),
      ),
    );
  });

  test("a platform exception without a message gets a default one", () async {
    reply = (_) async => throw PlatformException(code: "CANCELLED");

    await expectLater(
      backend.detectTextRegions(imagePath: "/tmp/photo.jpg"),
      throwsA(
        isA<OcrException>()
            .having((e) => e.code, "code", "CANCELLED")
            .having((e) => e.message, "message", "OCR operation failed"),
      ),
    );
  });

  test("ensureDisplayablePath returns the path unchanged", () async {
    expect(
      await backend.ensureDisplayablePath("/tmp/photo.heic"),
      "/tmp/photo.heic",
    );
    expect(calls, isEmpty);
  });
}
