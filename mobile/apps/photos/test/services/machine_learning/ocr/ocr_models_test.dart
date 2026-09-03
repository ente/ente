import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";

void main() {
  const quad = [
    {"x": 1, "y": 2},
    {"x": 11, "y": 2},
    {"x": 11, "y": 8.5},
    {"x": 1, "y": 8.5},
  ];

  group("TextBlock.fromMap", () {
    test("parses points and characters", () {
      final block = TextBlock.fromMap({
        "text": "hello",
        "confidence": 0.93,
        "points": quad,
        "characters": [
          {
            "text": "h",
            "confidence": 0.9,
            "points": [
              {"x": 1, "y": 2},
              {"x": 3, "y": 2},
              {"x": 3, "y": 8.5},
              {"x": 1, "y": 8.5},
            ],
          },
          "not a map",
        ],
      });

      expect(block.text, "hello");
      expect(block.confidence, 0.93);
      expect(block.points, const [
        Offset(1, 2),
        Offset(11, 2),
        Offset(11, 8.5),
        Offset(1, 8.5),
      ]);
      expect(block.characters, hasLength(1));
      expect(block.characters.single.text, "h");
      expect(block.characters.single.confidence, 0.9);
      expect(
        block.characters.single.boundingBox,
        const Rect.fromLTRB(1, 2, 3, 8.5),
      );
      expect(block.boundingBox, const Rect.fromLTRB(1, 2, 11, 8.5));
      expect(block.center, const Offset(6, 5.25));
    });

    test("falls back to the rectangle when points are missing", () {
      final block = TextBlock.fromMap({
        "text": "rect",
        "x": 10,
        "y": 20,
        "width": 30,
        "height": 5,
      });

      expect(block.points, const [
        Offset(10, 20),
        Offset(40, 20),
        Offset(40, 25),
        Offset(10, 25),
      ]);
      expect(block.characters, isEmpty);
      expect(block.confidence, 0);
    });

    test("falls back to the rectangle when points are empty", () {
      final block = TextBlock.fromMap({
        "points": <Object?>[],
        "x": 0,
        "y": 0,
        "width": 4,
        "height": 4,
      });

      expect(block.boundingBox, const Rect.fromLTRB(0, 0, 4, 4));
      expect(block.text, "");
    });

    test("rejects a map without points or rectangle", () {
      expect(() => TextBlock.fromMap({"text": "x"}), throwsArgumentError);
    });

    test("round trips through toMap", () {
      final block = TextBlock.fromMap({
        "text": "hello",
        "confidence": 0.5,
        "points": quad,
        "characters": [
          {"text": "h", "confidence": 0.4, "points": quad},
        ],
      });

      final copy = TextBlock.fromMap(block.toMap());

      expect(copy.text, block.text);
      expect(copy.confidence, block.confidence);
      expect(copy.points, block.points);
      expect(copy.characters.single.text, "h");
      expect(copy.characters.single.points, block.characters.single.points);
    });
  });

  test("CharacterBox.fromMap tolerates missing fields", () {
    final character = CharacterBox.fromMap(const {});

    expect(character.text, "");
    expect(character.confidence, 0);
    expect(character.points, isEmpty);
    expect(character.boundingBox, Rect.zero);
  });

  test("TextRegion.fromMap parses confidence and points", () {
    final region = TextRegion.fromMap({"confidence": 0.75, "points": quad});

    expect(region.confidence, 0.75);
    expect(region.points, hasLength(4));
    expect(region.boundingBox, const Rect.fromLTRB(1, 2, 11, 8.5));
  });

  test("TextDetectionResult.fromMap parses blocks and image size", () {
    final result = TextDetectionResult.fromMap({
      "blocks": [
        {"text": "a", "confidence": 1, "points": quad},
        "ignored",
      ],
      "imageWidth": 640,
      "imageHeight": 480.0,
    });

    expect(result.blocks.single.text, "a");
    expect(result.imageSize, const Size(640, 480));
  });

  test("TextDetectionResult.fromMap tolerates missing keys", () {
    final result = TextDetectionResult.fromMap(const {});

    expect(result.blocks, isEmpty);
    expect(result.imageSize, Size.zero);
  });

  test("TextRegionDetectionResult.fromMap parses regions and size", () {
    final result = TextRegionDetectionResult.fromMap({
      "regions": [
        {"confidence": 0.6, "points": quad},
      ],
      "imageWidth": 320,
      "imageHeight": 240,
    });

    expect(result.regions.single.confidence, 0.6);
    expect(result.imageSize, const Size(320, 240));
  });

  test("TextRegionDetectionResult.fromMap tolerates missing keys", () {
    final result = TextRegionDetectionResult.fromMap(const {});

    expect(result.regions, isEmpty);
    expect(result.imageSize, Size.zero);
  });

  test("OcrException prints its code and message", () {
    const exception = OcrException(
      code: "IMAGE_NOT_FOUND",
      message: "Image file does not exist",
      details: 42,
    );

    expect(
      exception.toString(),
      "OcrException(IMAGE_NOT_FOUND, Image file does not exist)",
    );
    expect(exception.details, 42);
  });
}
