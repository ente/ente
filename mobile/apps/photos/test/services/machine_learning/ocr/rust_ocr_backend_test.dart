import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/services/machine_learning/ocr/rust_ocr_backend.dart";
import "package:photos/src/rust/api/ocr_api.dart";

void main() {
  const quad = [
    RustOcrPoint(x: 1, y: 2),
    RustOcrPoint(x: 11, y: 2),
    RustOcrPoint(x: 11, y: 8.5),
    RustOcrPoint(x: 1, y: 8.5),
  ];
  const offsets = [
    Offset(1, 2),
    Offset(11, 2),
    Offset(11, 8.5),
    Offset(1, 8.5),
  ];

  test("converts a Rust text detection result", () {
    const rustResult = RustTextDetectionResult(
      blocks: [
        RustTextBlock(
          text: "hello",
          confidence: 0.91,
          points: quad,
          characters: [
            RustCharacterBox(text: "h", confidence: 0.8, points: quad),
          ],
        ),
      ],
      imageWidth: 640,
      imageHeight: 480,
    );

    final result = textDetectionResultFromRust(rustResult);

    expect(result.imageSize, const Size(640, 480));
    final block = result.blocks.single;
    expect(block.text, "hello");
    expect(block.confidence, 0.91);
    expect(block.points, offsets);
    expect(block.characters.single.text, "h");
    expect(block.characters.single.confidence, 0.8);
    expect(block.characters.single.points, offsets);
  });

  test("converts a Rust text region detection result", () {
    const rustResult = RustTextRegionDetectionResult(
      regions: [RustTextRegion(confidence: 0.7, points: quad)],
      imageWidth: 320,
      imageHeight: 240,
    );

    final result = textRegionDetectionResultFromRust(rustResult);

    expect(result.imageSize, const Size(320, 240));
    expect(result.regions.single.confidence, 0.7);
    expect(result.regions.single.points, offsets);
  });

  group("RustOcrError mapping", () {
    const imagePath = "/tmp/photo.jpg";
    OcrException map(RustOcrError error, {String otherCode = "OTHER"}) =>
        ocrExceptionFromRustError(
          error,
          imagePath: imagePath,
          otherCode: otherCode,
        );

    test("maps each variant to the legacy code and message", () {
      expect(
        map(const RustOcrError.imageNotFound(message: "image not found: a")),
        isA<OcrException>()
            .having((e) => e.code, "code", "IMAGE_NOT_FOUND")
            .having(
              (e) => e.message,
              "message",
              "Image file does not exist at path: $imagePath",
            )
            .having((e) => e.details, "details", "image not found: a"),
      );
      expect(
        map(const RustOcrError.invalidImage(message: "bad bytes")),
        isA<OcrException>()
            .having((e) => e.code, "code", "IMAGE_DECODE_ERROR")
            .having(
              (e) => e.message,
              "message",
              "Failed to decode image: bad bytes",
            ),
      );
      expect(
        map(const RustOcrError.cancelled()),
        isA<OcrException>()
            .having((e) => e.code, "code", "CANCELLED")
            .having((e) => e.message, "message", isNotEmpty),
      );
      expect(
        map(const RustOcrError.corruptModel(message: "vocab mismatch")),
        isA<OcrException>()
            .having((e) => e.code, "code", "MODEL_PREP_ERROR")
            .having((e) => e.message, "message", "vocab mismatch"),
      );
    });

    test("maps other errors to the code of the failing operation", () {
      const error = RustOcrError.other(message: "ort failure");

      expect(
        map(error, otherCode: "RECOGNITION_ERROR").code,
        "RECOGNITION_ERROR",
      );
      expect(map(error, otherCode: "DETECTION_ERROR").code, "DETECTION_ERROR");
      expect(map(error, otherCode: "DETECTION_ERROR").message, "ort failure");
    });

    test("messages carry the phrases the text detector widget matches", () {
      final missing = map(
        const RustOcrError.imageNotFound(message: "image not found: a"),
      ).toString().toLowerCase();
      final undecodable = map(
        const RustOcrError.invalidImage(message: "bad bytes"),
      ).toString().toLowerCase();

      expect(missing, contains("image"));
      expect(missing, contains("not"));
      expect(missing, contains("exist"));
      expect(undecodable, contains("failed to decode"));
    });
  });

  group("without a prepared engine", () {
    final backend = RustOcrBackend();

    test("cancelRequest completes", () async {
      await backend.cancelRequest("request");
    });

    test("ensureDisplayablePath returns every path unchanged", () async {
      for (final path in ["/tmp/photo.JPG", "/tmp/photo", "/tmp/photo.heic"]) {
        expect(await backend.ensureDisplayablePath(path), path);
      }
    });
  });
}
