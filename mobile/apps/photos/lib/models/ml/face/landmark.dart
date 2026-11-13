// Coordinates are fractions of the original image dimensions.
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
