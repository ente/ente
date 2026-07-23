class Dimensions {
  final int width;
  final int height;

  const Dimensions({required this.width, required this.height});

  @override
  String toString() {
    return 'Dimensions(width: $width, height: $height})';
  }

  Map<String, int> toJson() {
    return {'width': width, 'height': height};
  }

  factory Dimensions.fromJson(Map<String, dynamic> json) {
    return Dimensions(
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }
}
