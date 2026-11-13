import "dart:ui";

enum OcrModelComponent { detector, recognizer }

class ModelPreparationStatus {
  final bool isReady;
  final String? version;
  final String? modelPath;

  const ModelPreparationStatus({
    required this.isReady,
    this.version,
    this.modelPath,
  });
}

class OcrException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const OcrException({required this.code, required this.message, this.details});

  @override
  String toString() => "OcrException($code, $message)";
}

class TextBlock {
  final String text;
  final double confidence;
  final List<Offset> points;
  final List<CharacterBox> characters;

  const TextBlock({
    required this.text,
    required this.confidence,
    required this.points,
    required this.characters,
  });

  Rect get boundingBox => _boundingBoxOf(points);

  Offset get center => boundingBox.center;

  factory TextBlock.fromMap(Map<dynamic, dynamic> map) {
    final pointsList = map["points"] as List?;
    final points = (pointsList == null || pointsList.isEmpty)
        ? _fallbackPointsFromRect(map)
        : _pointsFromList(pointsList);
    final charactersList = map["characters"] as List?;
    final characters = charactersList == null
        ? const <CharacterBox>[]
        : charactersList
              .whereType<Map<dynamic, dynamic>>()
              .map(CharacterBox.fromMap)
              .toList(growable: false);
    return TextBlock(
      text: map["text"] as String? ?? "",
      confidence: (map["confidence"] as num?)?.toDouble() ?? 0.0,
      points: points,
      characters: characters,
    );
  }

  Map<String, dynamic> toMap() => {
    "text": text,
    "confidence": confidence,
    "points": _pointsToList(points),
    "characters": characters
        .map((character) => character.toMap())
        .toList(growable: false),
  };

  static List<Offset> _fallbackPointsFromRect(Map<dynamic, dynamic> map) {
    final x = map["x"] as num?;
    final y = map["y"] as num?;
    final width = map["width"] as num?;
    final height = map["height"] as num?;
    if (x == null || y == null || width == null || height == null) {
      throw ArgumentError(
        "TextBlock map is missing polygon points and fallback rectangle.",
      );
    }
    final left = x.toDouble();
    final top = y.toDouble();
    final right = left + width.toDouble();
    final bottom = top + height.toDouble();
    return <Offset>[
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
      Offset(left, bottom),
    ];
  }
}

class CharacterBox {
  final String text;
  final double confidence;
  final List<Offset> points;

  const CharacterBox({
    required this.text,
    required this.confidence,
    required this.points,
  });

  Rect get boundingBox => _boundingBoxOf(points);

  factory CharacterBox.fromMap(Map<dynamic, dynamic> map) {
    return CharacterBox(
      text: map["text"] as String? ?? "",
      confidence: (map["confidence"] as num?)?.toDouble() ?? 0.0,
      points: _pointsFromList(map["points"] as List?),
    );
  }

  Map<String, dynamic> toMap() => {
    "text": text,
    "confidence": confidence,
    "points": _pointsToList(points),
  };
}

class TextRegion {
  final double confidence;
  final List<Offset> points;

  const TextRegion({required this.confidence, required this.points});

  Rect get boundingBox => _boundingBoxOf(points);

  factory TextRegion.fromMap(Map<dynamic, dynamic> map) {
    return TextRegion(
      confidence: (map["confidence"] as num?)?.toDouble() ?? 0,
      points: _pointsFromList(map["points"] as List?),
    );
  }
}

class TextDetectionResult {
  final List<TextBlock> blocks;
  final Size imageSize;

  const TextDetectionResult({required this.blocks, required this.imageSize});

  factory TextDetectionResult.fromMap(Map<dynamic, dynamic> map) {
    final blocks = (map["blocks"] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(TextBlock.fromMap)
        .toList(growable: false);
    return TextDetectionResult(blocks: blocks, imageSize: _imageSizeOf(map));
  }
}

class TextRegionDetectionResult {
  final List<TextRegion> regions;
  final Size imageSize;

  const TextRegionDetectionResult({
    required this.regions,
    required this.imageSize,
  });

  factory TextRegionDetectionResult.fromMap(Map<dynamic, dynamic> map) {
    final regions = (map["regions"] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(TextRegion.fromMap)
        .toList(growable: false);
    return TextRegionDetectionResult(
      regions: regions,
      imageSize: _imageSizeOf(map),
    );
  }
}

Size _imageSizeOf(Map<dynamic, dynamic> map) => Size(
  (map["imageWidth"] as num?)?.toDouble() ?? 0,
  (map["imageHeight"] as num?)?.toDouble() ?? 0,
);

List<Offset> _pointsFromList(List? pointsList) => (pointsList ?? const [])
    .whereType<Map<dynamic, dynamic>>()
    .map(
      (point) => Offset(
        (point["x"] as num).toDouble(),
        (point["y"] as num).toDouble(),
      ),
    )
    .toList(growable: false);

List<Map<String, double>> _pointsToList(List<Offset> points) => points
    .map((point) => {"x": point.dx, "y": point.dy})
    .toList(growable: false);

Rect _boundingBoxOf(List<Offset> points) {
  if (points.isEmpty) {
    return Rect.zero;
  }
  var left = points.first.dx;
  var top = points.first.dy;
  var right = left;
  var bottom = top;
  for (final point in points.skip(1)) {
    if (point.dx < left) left = point.dx;
    if (point.dy < top) top = point.dy;
    if (point.dx > right) right = point.dx;
    if (point.dy > bottom) bottom = point.dy;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
