import "package:ente_pure_utils/ente_pure_utils.dart";

/// Bounding box of a face.
///
/// [ x] and [y] are the minimum coordinates, so the top left corner of the box.
/// [width] and [height] are the width and height of the box.
///
/// WARNING: All values are relative to the original image size, so in the range [0, 1].
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
