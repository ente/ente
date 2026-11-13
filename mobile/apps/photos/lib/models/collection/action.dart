class CollectionAction {
  const CollectionAction({
    required this.id,
    required this.userID,
    required this.actorID,
    required this.collectionID,
    this.fileID,
    required this.action,
  });

  final String id;
  final int userID;
  final int actorID;
  final int collectionID;
  final int? fileID;
  final String action;

  factory CollectionAction.fromJson(Map<String, dynamic> json) {
    final userID =
        _parseInt(json["userID"] ?? json["userId"]) ??
        (throw ArgumentError("CollectionAction.userID is missing"));
    final actorID =
        _parseInt(json["actorUserID"] ?? json["actorUserId"]) ??
        (throw ArgumentError("CollectionAction.actorID is missing"));
    final collectionID =
        _parseInt(json["collectionID"] ?? json["collectionId"]) ??
        (throw ArgumentError("CollectionAction.collectionID is missing"));

    return CollectionAction(
      id: (json["id"] ?? "").toString(),
      userID: userID,
      actorID: actorID,
      collectionID: collectionID,
      fileID: _parseInt(json["fileID"] ?? json["fileId"]),
      action: (json["action"] ?? "").toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "userID": userID,
      "actorID": actorID,
      "collectionID": collectionID,
      if (fileID != null) "fileID": fileID,
      "action": action,
    };
  }

  static int? _parseInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
