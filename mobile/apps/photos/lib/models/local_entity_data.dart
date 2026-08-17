import "package:equatable/equatable.dart";
import "package:photos/gateways/entity/models/type.dart";

class LocalEntityData {
  final String id;
  final EntityType type;
  final String data;
  final int ownerID;
  final int updatedAt;

  LocalEntityData({
    required this.id,
    required this.type,
    required this.data,
    required this.ownerID,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "type": type.name,
      "data": data,
      "ownerID": ownerID,
      "updatedAt": updatedAt,
    };
  }

  factory LocalEntityData.fromJson(Map<String, dynamic> json) {
    return LocalEntityData(
      id: json["id"],
      type: entityTypeFromString(json["type"]),
      data: json["data"],
      ownerID: json["ownerID"] as int,
      updatedAt: json["updatedAt"] as int,
    );
  }
}

class LocalEntity<T> extends Equatable {
  final T item;
  final String id;

  const LocalEntity(this.item, this.id);

  @override
  List<Object?> get props => [item, id];
}
