import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/models/ml/face/face.dart";

const _faceKey = 'face';
const _clipKey = 'clip';

enum DataType {
  mlData('mldata');

  final String value;
  const DataType(this.value);

  static DataType fromString(String type) {
    return DataType.values.firstWhere(
      (e) => e.value == type,
      orElse: () {
        throw Exception('Unknown type: $type');
      },
    );
  }

  String toJson() => value;
  static DataType fromJson(String json) => DataType.fromString(json);
}

class FileDataEntity {
  final int fileID;
  final Map<String, dynamic> remoteRawData;
  final DataType type;

  FileDataEntity(this.fileID, this.remoteRawData, this.type);

  void validate() {
    if (type == DataType.mlData) {
      if (remoteRawData[_faceKey] == null) {
        throw Exception('Face embedding is null');
      }
      if (remoteRawData[_clipKey] == null) {
        throw Exception('Clip embedding is null');
      }
    } else {
      throw Exception('Invalid type ${type.value}');
    }
  }

  factory FileDataEntity.fromRemote(
    int fileID,
    String type,
    Map<String, dynamic> json,
  ) {
    return FileDataEntity(fileID, json, DataType.fromString(type));
  }

  static FileDataEntity empty(int fileID, DataType type) {
    final Map<String, dynamic> json = {};
    return FileDataEntity(fileID, json, type);
  }

  void putFace(RemoteFaceEmbedding faceEmbedding) {
    assert(type == DataType.mlData, 'Invalid type ${type.value}');
    remoteRawData[_faceKey] = faceEmbedding.toJson();
  }

  void putClip(RemoteClipEmbedding clipEmbedding) {
    assert(type == DataType.mlData, 'Invalid type ${type.value}');
    remoteRawData[_clipKey] = clipEmbedding.toJson();
  }

  RemoteFaceEmbedding? get faceEmbedding => remoteRawData[_faceKey] != null
      ? RemoteFaceEmbedding.fromJson(
          remoteRawData[_faceKey] as Map<String, dynamic>,
        )
      : null;

  RemoteClipEmbedding? getClipEmbeddingIfCompatible(int minClipMlVersion) {
    final clipData = remoteRawData[_clipKey];
    if (clipData == null) return null;

    final clipEmbedding = RemoteClipEmbedding.fromJson(
      clipData as Map<String, dynamic>,
    );
    return clipEmbedding.version >= minClipMlVersion ? clipEmbedding : null;
  }
}

class RemoteFaceEmbedding {
  final List<Face> faces;
  final int version;

  // packageName/version
  final String client;
  final int height;
  final int width;

  /// Bitmask describing properties of this index (e.g. which runtime produced
  /// it). Bits are defined in `ml_versions.dart`. Absent on the wire => 0
  /// (legacy).
  final int flags;

  RemoteFaceEmbedding(
    this.faces,
    this.version, {
    required this.client,
    required this.height,
    required this.width,
    this.flags = 0,
  });

  // toJson
  Map<String, dynamic> toJson() => {
    'faces': faces.map((x) => x.toJson()).toList(),
    'version': version,
    'client': client,
    'height': height,
    'width': width,
    if (flags != 0) 'flags': flags,
  };

  // fromJson
  factory RemoteFaceEmbedding.fromJson(Map<String, dynamic> json) {
    return RemoteFaceEmbedding(
      List<Face>.from(
        json['faces'].map((x) => Face.fromJson(x as Map<String, dynamic>)),
      ),
      json['version'] as int,
      client: json['client'] as String,
      height: json['height'] as int,
      width: json['width'] as int,
      flags: (json['flags'] as int?) ?? 0,
    );
  }
}

class RemoteClipEmbedding {
  final int version;
  final String client;
  final List<double> embedding;

  /// Bitmask describing properties of this index (e.g. which runtime produced
  /// it). Bits are defined in `ml_versions.dart`. Absent on the wire => 0
  /// (legacy).
  final int flags;

  RemoteClipEmbedding(
    this.embedding, {
    required this.version,
    required this.client,
    this.flags = 0,
  });

  // toJson
  Map<String, dynamic> toJson() => {
    'embedding': embedding,
    'version': version,
    'client': client,
    if (flags != 0) 'flags': flags,
  };

  // fromJson
  factory RemoteClipEmbedding.fromJson(Map<String, dynamic> json) {
    return RemoteClipEmbedding(
      parseAsDoubleList(json['embedding'] as List),
      version: json['version'] as int,
      client: json['client'] as String,
      flags: (json['flags'] as int?) ?? 0,
    );
  }
}

// FDStatus represents the status of a file data entry.
class FDStatus {
  final int fileID;
  final int userID;
  final String type;
  final bool isDeleted;
  final int size;
  final int updatedAt;
  final String? objectID;
  final String? objectNonce;
  FDStatus({
    required this.fileID,
    required this.userID,
    required this.type,
    required this.size,
    required this.updatedAt,
    this.isDeleted = false,
    this.objectID,
    this.objectNonce,
  });

  factory FDStatus.fromJson(Map<String, dynamic> json) {
    return FDStatus(
      fileID: json['fileID'] as int,
      userID: json['userID'] as int,
      type: json['type'] as String,
      isDeleted: json['isDeleted'] as bool? ?? false,
      size: json['size'] as int,
      objectID: json['objectID'] as String?,
      objectNonce: json['objectNonce'] as String?,
      updatedAt: json['updatedAt'] as int,
    );
  }
}

class PreviewInfo {
  final String objectId;
  final int objectSize;
  String? nonce;
  PreviewInfo({required this.objectId, required this.objectSize, this.nonce});
}
