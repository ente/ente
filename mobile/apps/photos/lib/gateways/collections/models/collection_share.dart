enum CollectionShareSource { manual, automatic }

enum CollectionShareStatus {
  shared,
  alreadyShared,
  unshared,
  alreadyUnshared,
  notShared,
  blockedPreviousRemoval,
  failed,
  unknown;

  factory CollectionShareStatus.fromString(String value) => switch (value) {
    'shared' => shared,
    'already_shared' => alreadyShared,
    'unshared' => unshared,
    'already_unshared' => alreadyUnshared,
    'not_shared' => notShared,
    'blocked_previous_removal' => blockedPreviousRemoval,
    'failed' => failed,
    _ => unknown,
  };
}

class BulkCollectionShareItem {
  const BulkCollectionShareItem({
    required this.collectionID,
    required this.encryptedKey,
    required this.role,
  });

  final int collectionID;
  final String encryptedKey;
  final String role;

  Map<String, dynamic> toJson() => {
    'collectionID': collectionID,
    'encryptedKey': encryptedKey,
    'role': role,
  };
}

class CollectionShareResult {
  const CollectionShareResult({
    required this.collectionID,
    required this.status,
  });

  final int collectionID;
  final CollectionShareStatus status;

  factory CollectionShareResult.fromJson(Map<String, dynamic> json) =>
      CollectionShareResult(
        collectionID: json['collectionID'] as int,
        status: CollectionShareStatus.fromString(json['status'] as String),
      );
}
