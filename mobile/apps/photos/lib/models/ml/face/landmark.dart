/// Landmark coordinate data.
///
/// WARNING: All coordinates are relative to the image size, so in the range [0, 1]!
class Landmark {
  double x;
  double y;

  Landmark({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory Landmark.fromJson(Map<String, dynamic> json) {
    return Landmark(
      x: (json['x'] is int
          ? (json['x'] as int).toDouble()
          : json['x'] as double),
      y: (json['y'] is int
          ? (json['y'] as int).toDouble()
          : json['y'] as double),
    );
  }

  @override
  toString() {
    return '(x: ${x.toStringAsFixed(4)}, y: ${y.toStringAsFixed(4)})';
  }
}
