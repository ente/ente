/// Raw comment data from the API (encrypted).
///
/// This represents the wire format from the server with cipher/nonce pairs.
/// Decryption happens in the sync service before storing locally.
class CommentApiResponse {
  final String id;
  final int collectionID;
  final int? fileID;
  final String? parentCommentID;
  final int? parentCommentUserID;
  final int userID;
  final String? anonUserID;
  final String? cipher;
  final String? nonce;
  final bool isDeleted;
  final int createdAt;
  final int updatedAt;

  CommentApiResponse({
    required this.id,
    required this.collectionID,
    this.fileID,
    this.parentCommentID,
    this.parentCommentUserID,
    required this.userID,
    this.anonUserID,
    this.cipher,
    this.nonce,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommentApiResponse.fromJson(Map<String, dynamic> json) {
    return CommentApiResponse(
      id: json['id'] as String,
      collectionID: json['collectionID'] as int,
      fileID: json['fileID'] as int?,
      parentCommentID: json['parentCommentID'] as String?,
      parentCommentUserID: json['parentCommentUserID'] as int?,
      userID: json['userID'] as int,
      anonUserID: json['anonUserID'] as String?,
      cipher: json['cipher'] as String?,
      nonce: json['nonce'] as String?,
      isDeleted: json['isDeleted'] as bool? ?? false,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }
}

/// Raw reaction data from the API (encrypted).
///
/// This represents the wire format from the server with cipher/nonce pairs.
/// Decryption happens in the sync service before storing locally.
class ReactionApiResponse {
  final String id;
  final int collectionID;
  final int? fileID;
  final String? commentID;
  final bool? isCommentReply;
  final int userID;
  final String? anonUserID;
  final String? cipher;
  final String? nonce;
  final bool isDeleted;
  final int createdAt;
  final int updatedAt;

  ReactionApiResponse({
    required this.id,
    required this.collectionID,
    this.fileID,
    this.commentID,
    this.isCommentReply,
    required this.userID,
    this.anonUserID,
    this.cipher,
    this.nonce,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReactionApiResponse.fromJson(Map<String, dynamic> json) {
    return ReactionApiResponse(
      id: json['id'] as String,
      collectionID: json['collectionID'] as int,
      fileID: json['fileID'] as int?,
      commentID: json['commentID'] as String?,
      isCommentReply: json['isCommentReply'] as bool?,
      userID: json['userID'] as int,
      anonUserID: json['anonUserID'] as String?,
      cipher: json['cipher'] as String?,
      nonce: json['nonce'] as String?,
      isDeleted: json['isDeleted'] as bool? ?? false,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }
}

/// Response from GET /comments/diff
class CommentsDiffResponse {
  final List<CommentApiResponse> comments;
  final bool hasMore;

  CommentsDiffResponse({required this.comments, required this.hasMore});

  factory CommentsDiffResponse.fromJson(Map<String, dynamic> json) {
    final commentsList = json['comments'] as List<dynamic>? ?? [];
    return CommentsDiffResponse(
      comments: commentsList
          .map((e) => CommentApiResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}

/// Response from GET /reactions/diff
class ReactionsDiffResponse {
  final List<ReactionApiResponse> reactions;
  final bool hasMore;

  ReactionsDiffResponse({required this.reactions, required this.hasMore});

  factory ReactionsDiffResponse.fromJson(Map<String, dynamic> json) {
    final reactionsList = json['reactions'] as List<dynamic>? ?? [];
    return ReactionsDiffResponse(
      reactions: reactionsList
          .map((e) => ReactionApiResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}

/// Response from GET /social/diff (unified endpoint)
class SocialDiffResponse {
  final List<CommentApiResponse> comments;
  final List<ReactionApiResponse> reactions;
  final bool hasMoreComments;
  final bool hasMoreReactions;

  SocialDiffResponse({
    required this.comments,
    required this.reactions,
    required this.hasMoreComments,
    required this.hasMoreReactions,
  });

  factory SocialDiffResponse.fromJson(Map<String, dynamic> json) {
    final commentsList = json['comments'] as List<dynamic>? ?? [];
    final reactionsList = json['reactions'] as List<dynamic>? ?? [];
    return SocialDiffResponse(
      comments: commentsList
          .map((e) => CommentApiResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      reactions: reactionsList
          .map((e) => ReactionApiResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMoreComments: json['hasMoreComments'] as bool? ?? false,
      hasMoreReactions: json['hasMoreReactions'] as bool? ?? false,
    );
  }
}

/// Per-collection latest update timestamps from GET /comments-reactions/updated-at
class CollectionLatestUpdate {
  final int collectionID;
  final int? commentsUpdatedAt;
  final int? reactionsUpdatedAt;
  final int? anonProfilesUpdatedAt;

  CollectionLatestUpdate({
    required this.collectionID,
    this.commentsUpdatedAt,
    this.reactionsUpdatedAt,
    this.anonProfilesUpdatedAt,
  });

  factory CollectionLatestUpdate.fromJson(Map<String, dynamic> json) {
    return CollectionLatestUpdate(
      collectionID: json['collectionID'] as int,
      commentsUpdatedAt: json['commentsUpdatedAt'] as int?,
      reactionsUpdatedAt: json['reactionsUpdatedAt'] as int?,
      anonProfilesUpdatedAt: json['anonProfilesUpdatedAt'] as int?,
    );
  }
}

/// Response from GET /comments-reactions/updated-at
class LatestUpdatesResponse {
  final List<CollectionLatestUpdate> updates;

  LatestUpdatesResponse({required this.updates});

  factory LatestUpdatesResponse.fromJson(Map<String, dynamic> json) {
    final updatesList = json['updates'] as List<dynamic>? ?? [];
    return LatestUpdatesResponse(
      updates: updatesList
          .map(
            (e) => CollectionLatestUpdate.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

/// Anonymous user profile from GET /social/anon-profiles (encrypted)
class AnonProfileApiResponse {
  final String anonUserID;
  final int collectionID;
  final String cipher;
  final String nonce;
  final int createdAt;
  final int updatedAt;

  AnonProfileApiResponse({
    required this.anonUserID,
    required this.collectionID,
    required this.cipher,
    required this.nonce,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AnonProfileApiResponse.fromJson(Map<String, dynamic> json) {
    return AnonProfileApiResponse(
      anonUserID: json['anonUserID'] as String,
      collectionID: json['collectionID'] as int,
      cipher: json['cipher'] as String,
      nonce: json['nonce'] as String,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }
}

/// Response from GET /social/anon-profiles
class AnonProfilesResponse {
  final List<AnonProfileApiResponse> profiles;

  AnonProfilesResponse({required this.profiles});

  factory AnonProfilesResponse.fromJson(Map<String, dynamic> json) {
    final profilesList = json['profiles'] as List<dynamic>? ?? [];
    return AnonProfilesResponse(
      profiles: profilesList
          .map(
            (e) => AnonProfileApiResponse.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
