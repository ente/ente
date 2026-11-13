import "dart:convert";
import "package:ml_linalg/vector.dart";

class EmbeddingVector {
  final int fileID;
  final Vector vector;

  bool get isEmpty => vector.isEmpty;

  EmbeddingVector({required this.fileID, required List<double> embedding})
    : vector = Vector.fromList(embedding);

  static EmbeddingVector fromJsonString(String jsonString) {
    return _fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  String toJsonString() {
    return jsonEncode(_toJson());
  }

  Map<String, dynamic> _toJson() {
    return {"fileID": fileID, "embedding": vector.toList()};
  }

  static EmbeddingVector _fromJson(Map<String, dynamic> json) {
    return EmbeddingVector(
      fileID: json["fileID"] as int,
      embedding: List<double>.from(json["embedding"] as List),
    );
  }
}
