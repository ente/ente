import "dart:convert" show jsonEncode, jsonDecode;

import "package:logging/logging.dart";
import "package:photos/models/ml/face/dimension.dart";
import 'package:photos/models/ml/ml_typedefs.dart';
import 'package:photos/services/machine_learning/face_ml/face_alignment/alignment_result.dart';
import 'package:photos/services/machine_learning/face_ml/face_detection/detection.dart';
import 'package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart';

class MLResult {
  int fileId;

  List<FaceResult>? faces = <FaceResult>[];
  ClipResult? clip;
  List<PetFaceResult>? petFaces;
  List<PetBodyResult>? petBodies;

  Dimensions decodedImageSize;

  bool get ranML => facesRan || clipRan || petsRan;
  bool get facesRan => faces != null;
  bool get clipRan => clip != null;
  bool get petsRan => petFaces != null || petBodies != null;

  MLResult({
    this.fileId = -1,
    this.faces,
    this.clip,
    this.petFaces,
    this.petBodies,
    this.decodedImageSize = const Dimensions(width: -1, height: -1),
  });

  MLResult.fromEnteFileID(
    int fileID, {
    this.decodedImageSize = const Dimensions(width: -1, height: -1),
  }) : fileId = fileID;

  Map<String, dynamic> _toJson() => {
    'fileId': fileId,
    'faces': faces?.map((face) => face.toJson()).toList(),
    'clip': clip?.toJson(),
    'petFaces': petFaces?.map((pf) => pf.toJson()).toList(),
    'petBodies': petBodies?.map((obj) => obj.toJson()).toList(),
    'decodedImageSize': {
      'width': decodedImageSize.width,
      'height': decodedImageSize.height,
    },
  };

  String toJsonString() => jsonEncode(_toJson());

  static MLResult _fromJson(Map<String, dynamic> json) {
    return MLResult(
      fileId: json['fileId'],
      faces: json['faces'] != null
          ? (json['faces'] as List)
                .map(
                  (item) => FaceResult.fromJson(item as Map<String, dynamic>),
                )
                .toList()
          : null,
      clip: json['clip'] != null
          ? ClipResult.fromJson(json['clip'] as Map<String, dynamic>)
          : null,
      petFaces: json['petFaces'] != null
          ? (json['petFaces'] as List)
                .map(
                  (item) =>
                      PetFaceResult.fromJson(item as Map<String, dynamic>),
                )
                .toList()
          : null,
      petBodies: json['petBodies'] != null
          ? (json['petBodies'] as List)
                .map(
                  (item) =>
                      PetBodyResult.fromJson(item as Map<String, dynamic>),
                )
                .toList()
          : null,
      decodedImageSize: json['decodedImageSize'] != null
          ? Dimensions(
              width: json['decodedImageSize']['width'],
              height: json['decodedImageSize']['height'],
            )
          : json['faceDetectionImageSize'] == null
          ? const Dimensions(width: -1, height: -1)
          : Dimensions(
              width: (json['faceDetectionImageSize']['width'] as double)
                  .truncate(),
              height: (json['faceDetectionImageSize']['height'] as double)
                  .truncate(),
            ),
    );
  }

  static MLResult fromJsonString(String jsonString) {
    return _fromJson(jsonDecode(jsonString));
  }
}

class ClipResult {
  final int fileID;
  final Embedding embedding;

  ClipResult({required this.fileID, required this.embedding});

  Map<String, dynamic> toJson() => {'fileID': fileID, 'embedding': embedding};

  static ClipResult fromJson(Map<String, dynamic> json) {
    return ClipResult(
      fileID: json['fileID'],
      embedding: Embedding.from(json['embedding']),
    );
  }
}

class FaceResult {
  late FaceDetectionRelative detection;
  late double blurValue;
  late AlignmentResult alignment;
  late Embedding embedding;
  late int fileId;
  late String faceId;

  bool get isBlurry => blurValue < kLaplacianHardThreshold;

  FaceResult({
    required this.fileId,
    required this.faceId,
    required this.detection,
    required this.blurValue,
    required this.alignment,
    required this.embedding,
  });

  FaceResult.fromFaceDetection(
    FaceDetectionRelative faceDetection,
    int fileID,
  ) {
    fileId = fileID;
    faceId = faceDetection.toFaceID(fileID: fileID);
    detection = faceDetection;
  }

  Map<String, dynamic> toJson() => {
    'detection': detection.toJson(),
    'blurValue': blurValue,
    'alignment': alignment.toJson(),
    'embedding': embedding,
    'fileId': fileId,
    'faceId': faceId,
  };

  static FaceResult fromJson(Map<String, dynamic> json) {
    return FaceResult(
      detection: FaceDetectionRelative.fromJson(json['detection']),
      blurValue: json['blurValue'],
      alignment: AlignmentResult.fromJson(json['alignment']),
      embedding: Embedding.from(json['embedding']),
      fileId: json['fileId'],
      faceId: json['faceId'],
    );
  }
}

T getFileIdFromFaceId<T extends Object>(String faceId) {
  final String faceIdSplit = faceId.substring(0, faceId.indexOf('_'));
  try {
    if (T == int) {
      return int.parse(faceIdSplit) as T;
    }
    if (T == String) {
      return faceIdSplit as T;
    }
  } catch (e) {
    Logger("FaceID").severe("Error parsing faceId: $faceId with type $T", e);
  }
  throw ArgumentError("Unsupported type: $T");
}

int? tryGetFileIdFromFaceId(String faceId) {
  try {
    return int.tryParse(faceId.substring(0, faceId.indexOf('_')));
  } catch (e, s) {
    Logger("FaceID").severe("Error parsing faceId: $faceId", e, s);
    return null;
  }
}

class PetFaceResult {
  final FaceDetectionRelative detection;
  final AlignmentResult alignment;
  final int species;
  final Embedding embedding;
  final int fileId;
  final String petFaceId;

  PetFaceResult({
    required this.fileId,
    required this.petFaceId,
    required this.detection,
    required this.alignment,
    required this.species,
    required this.embedding,
  });

  Map<String, dynamic> toJson() => {
    'detection': detection.toJson(),
    'alignment': alignment.toJson(),
    'species': species,
    'embedding': embedding,
    'fileId': fileId,
    'petFaceId': petFaceId,
  };

  static PetFaceResult fromJson(Map<String, dynamic> json) {
    return PetFaceResult(
      detection: FaceDetectionRelative.fromJson(json['detection']),
      alignment: AlignmentResult.fromJson(json['alignment']),
      species: json['species'],
      embedding: Embedding.from(json['embedding']),
      fileId: json['fileId'],
      petFaceId: json['petFaceId'],
    );
  }
}

class PetBodyResult {
  final List<double> boxXyxy;
  final double score;
  final int cocoClass;
  final String petBodyId;
  final Embedding embedding;

  PetBodyResult({
    required this.boxXyxy,
    required this.score,
    required this.cocoClass,
    required this.petBodyId,
    required this.embedding,
  });

  Map<String, dynamic> toJson() => {
    'boxXyxy': boxXyxy,
    'score': score,
    'cocoClass': cocoClass,
    'petBodyId': petBodyId,
    'embedding': embedding,
  };

  static PetBodyResult fromJson(Map<String, dynamic> json) {
    return PetBodyResult(
      boxXyxy: (json['boxXyxy'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      score: (json['score'] as num).toDouble(),
      cocoClass: json['cocoClass'],
      petBodyId: json['petBodyId'],
      embedding: Embedding.from(json['embedding']),
    );
  }
}
