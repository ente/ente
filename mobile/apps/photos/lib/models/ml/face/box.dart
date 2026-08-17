import "package:ente_pure_utils/ente_pure_utils.dart";

// x and y are the top-left corner; all values are fractions of the image.
class FaceBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const FaceBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory FaceBox.fromJson(Map<String, dynamic> json) {
    return FaceBox(
      x:
          parseIntOrDoubleAsDouble(json['x']) ??
          parseIntOrDoubleAsDouble(json['xMin'])!,
      y:
          parseIntOrDoubleAsDouble(json['y']) ??
          parseIntOrDoubleAsDouble(json['yMin'])!,
      width: parseIntOrDoubleAsDouble(json['width'])!,
      height: parseIntOrDoubleAsDouble(json['height'])!,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}
