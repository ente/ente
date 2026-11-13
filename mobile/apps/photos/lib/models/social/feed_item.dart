enum FeedItemType {
  photoLike,
  comment,
  reply,
  commentLike,
  replyLike,
  sharedPhoto,
  sharedCollection,
}

class FeedItem {
  final FeedItemType type;
  final int collectionID;
  final int? fileID;
  final String? commentID;
  final List<int> actorUserIDs;
  final List<String?> actorAnonIDs;
  final int createdAt;
  final bool isOwnedByCurrentUser;
  final List<int>? sharedFileIDs;
  final String? collectionName;
  final bool isVideo;

  const FeedItem({
    required this.type,
    required this.collectionID,
    this.fileID,
    this.commentID,
    required this.actorUserIDs,
    required this.actorAnonIDs,
    required this.createdAt,
    required this.isOwnedByCurrentUser,
    this.sharedFileIDs,
    this.collectionName,
    this.isVideo = false,
  });

  int get actorCount => actorUserIDs.length;

  bool get hasMultipleActors => actorCount > 1;

  int get primaryActorUserID => actorUserIDs.first;

  String? get primaryActorAnonID => actorAnonIDs.first;

  int get additionalActorCount => actorCount - 1;

  int get sharedFileCount => sharedFileIDs?.length ?? 0;

  @override
  String toString() {
    return 'FeedItem(type: $type, collectionID: $collectionID, '
        'fileID: $fileID, commentID: $commentID, '
        'actorCount: $actorCount, createdAt: $createdAt, '
        'sharedFileCount: $sharedFileCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeedItem &&
        other.type == type &&
        other.collectionID == collectionID &&
        other.fileID == fileID &&
        other.commentID == commentID &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(type, collectionID, fileID, commentID, createdAt);
  }

  FeedItem copyWith({
    FeedItemType? type,
    int? collectionID,
    int? fileID,
    String? commentID,
    List<int>? actorUserIDs,
    List<String?>? actorAnonIDs,
    int? createdAt,
    bool? isOwnedByCurrentUser,
    List<int>? sharedFileIDs,
    String? collectionName,
    bool? isVideo,
  }) {
    return FeedItem(
      type: type ?? this.type,
      collectionID: collectionID ?? this.collectionID,
      fileID: fileID ?? this.fileID,
      commentID: commentID ?? this.commentID,
      actorUserIDs: actorUserIDs ?? this.actorUserIDs,
      actorAnonIDs: actorAnonIDs ?? this.actorAnonIDs,
      createdAt: createdAt ?? this.createdAt,
      isOwnedByCurrentUser: isOwnedByCurrentUser ?? this.isOwnedByCurrentUser,
      sharedFileIDs: sharedFileIDs ?? this.sharedFileIDs,
      collectionName: collectionName ?? this.collectionName,
      isVideo: isVideo ?? this.isVideo,
    );
  }
}
