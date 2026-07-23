class AlignmentResult {
  final List<List<double>> affineMatrix; // 3x3
  final List<double> center; // [x, y]
  final double size; // 1 / scale
  final double rotation; // atan2(simRotation[1][0], simRotation[0][0]);

  AlignmentResult({
    required this.affineMatrix,
    required this.center,
    required this.size,
    required this.rotation,
  });

  factory AlignmentResult.fromJson(Map<String, dynamic> json) {
    return AlignmentResult(
      affineMatrix: (json['affineMatrix'] as List)
          .map((item) => List<double>.from(item))
          .toList(),
      center: List<double>.from(json['center'] as List),
      size: json['size'] as double,
      rotation: json['rotation'] as double,
    );
  }

  Map<String, dynamic> toJson() => {
    'affineMatrix': affineMatrix,
    'center': center,
    'size': size,
    'rotation': rotation,
  };
}
