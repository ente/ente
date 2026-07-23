import "package:dio/dio.dart";
import "package:photos/models/social/api_responses.dart";

/// Gateway for social features API endpoints (comments and reactions).
class SocialGateway {
  final Dio _enteDio;

  SocialGateway(this._enteDio);

  // ============ Comments API ============

  /// Creates a new comment on the server.
  ///
  /// [id] - The comment ID
  /// [collectionID] - The collection this comment belongs to
  /// [cipher] - The encrypted comment text (base64)
  /// [nonce] - The encryption nonce (base64)
  /// [fileID] - Optional file ID if commenting on a file
  /// [parentCommentID] - Optional parent comment ID for replies
  ///
  /// Returns the comment ID from the server response.
  Future<String> createComment({
    required String id,
    required int collectionID,
    required String cipher,
    required String nonce,
    int? fileID,
    String? parentCommentID,
  }) async {
    final data = <String, dynamic>{
      "id": id,
      "collectionID": collectionID,
      "cipher": cipher,
      "nonce": nonce,
    };

    if (fileID != null) {
      data["fileID"] = fileID;
    }
    if (parentCommentID != null) {
      data["parentCommentID"] = parentCommentID;
    }

    final response = await _enteDio.post("/comments", data: data);
    return response.data["id"] as String;
  }

  /// Updates an existing comment.
  ///
  /// [commentID] - The comment ID to update
  /// [cipher] - The new encrypted comment text (base64)
  /// [nonce] - The new encryption nonce (base64)
  Future<void> updateComment({
    required String commentID,
    required String cipher,
    required String nonce,
  }) async {
    await _enteDio.put(
      "/comments/$commentID",
      data: {"cipher": cipher, "nonce": nonce},
    );
  }

  /// Deletes a comment (soft delete on server).
  Future<void> deleteComment(String commentID) async {
    await _enteDio.delete("/comments/$commentID");
  }

  /// Fetches comments diff for a collection.
  ///
  /// [collectionID] - The collection to fetch comments from
  /// [sinceTime] - Only fetch comments updated after this timestamp
  /// [limit] - Maximum number of comments to fetch (default 1000, max 2000)
  /// [fileID] - Optional filter for comments on a specific file
  ///
  /// Returns [CommentsDiffResponse] with comments and hasMore flag.
  Future<CommentsDiffResponse> fetchCommentsDiff({
    required int collectionID,
    int? sinceTime,
    int? limit,
    int? fileID,
  }) async {
    final queryParams = <String, dynamic>{"collectionID": collectionID};

    if (sinceTime != null) {
      queryParams["sinceTime"] = sinceTime;
    }
    if (limit != null) {
      queryParams["limit"] = limit;
    }
    if (fileID != null) {
      queryParams["fileID"] = fileID;
    }

    final response = await _enteDio.get(
      "/comments/diff",
      queryParameters: queryParams,
    );
    return CommentsDiffResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ============ Reactions API ============

  /// Creates or updates a reaction (upsert).
  ///
  /// [id] - The reaction ID
  /// [collectionID] - The collection this reaction belongs to
  /// [cipher] - The encrypted reaction type (base64)
  /// [nonce] - The encryption nonce (base64)
  /// [fileID] - Optional file ID if reacting to a file
  /// [commentID] - Optional comment ID if reacting to a comment
  ///
  /// Returns the reaction ID from the server response.
  Future<String> upsertReaction({
    required String id,
    required int collectionID,
    required String cipher,
    required String nonce,
    int? fileID,
    String? commentID,
  }) async {
    final data = <String, dynamic>{
      "id": id,
      "collectionID": collectionID,
      "cipher": cipher,
      "nonce": nonce,
    };

    if (fileID != null) {
      data["fileID"] = fileID;
    }
    if (commentID != null) {
      data["commentID"] = commentID;
    }

    final response = await _enteDio.put("/reactions", data: data);
    return response.data["id"] as String;
  }

  /// Deletes a reaction (soft delete on server).
  Future<void> deleteReaction(String reactionID) async {
    await _enteDio.delete("/reactions/$reactionID");
  }

  /// Fetches reactions diff for a collection.
  ///
  /// [collectionID] - The collection to fetch reactions from
  /// [sinceTime] - Only fetch reactions updated after this timestamp
  /// [limit] - Maximum number of reactions to fetch (default 1000, max 2000)
  /// [fileID] - Optional filter for reactions on a specific file
  /// [commentID] - Optional filter for reactions on a specific comment
  ///
  /// Returns [ReactionsDiffResponse] with reactions and hasMore flag.
  Future<ReactionsDiffResponse> fetchReactionsDiff({
    required int collectionID,
    int? sinceTime,
    int? limit,
    int? fileID,
    String? commentID,
  }) async {
    final queryParams = <String, dynamic>{"collectionID": collectionID};

    if (sinceTime != null) {
      queryParams["sinceTime"] = sinceTime;
    }
    if (limit != null) {
      queryParams["limit"] = limit;
    }
    if (fileID != null) {
      queryParams["fileID"] = fileID;
    }
    if (commentID != null) {
      queryParams["commentID"] = commentID;
    }

    final response = await _enteDio.get(
      "/reactions/diff",
      queryParameters: queryParams,
    );
    return ReactionsDiffResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  // ============ Latest Updates API ============

  /// Fetches latest update timestamps for all collections accessible to the
  /// user.
  ///
  /// Returns per-collection timestamps for comments, reactions, and anonymous
  /// profiles. Use this to determine which collections need syncing.
  Future<LatestUpdatesResponse> fetchLatestUpdates() async {
    final response = await _enteDio.get("/comments-reactions/updated-at");
    return LatestUpdatesResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Fetches anonymous profiles for a collection.
  ///
  /// Returns encrypted profile data that needs to be decrypted with the
  /// collection key.
  Future<AnonProfilesResponse> fetchAnonProfiles(int collectionID) async {
    final response = await _enteDio.get(
      "/social/anon-profiles",
      queryParameters: {"collectionID": collectionID},
    );
    return AnonProfilesResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ============ Unified/Social API ============

  /// Fetches both comments and reactions in a single call.
  ///
  /// [collectionID] - The collection to fetch social data from
  /// [commentsSinceTime] - Only fetch comments updated after this timestamp
  /// [reactionsSinceTime] - Only fetch reactions updated after this timestamp
  /// [limit] - Maximum number of items per type (default 1000, max 2000)
  /// [fileID] - Optional filter for items on a specific file
  ///
  /// Returns [SocialDiffResponse] with comments, reactions, and hasMore flags.
  Future<SocialDiffResponse> fetchSocialDiff({
    required int collectionID,
    int? commentsSinceTime,
    int? reactionsSinceTime,
    int? limit,
    int? fileID,
  }) async {
    final queryParams = <String, dynamic>{"collectionID": collectionID};

    if (commentsSinceTime != null) {
      queryParams["commentsSinceTime"] = commentsSinceTime;
    }
    if (reactionsSinceTime != null) {
      queryParams["reactionsSinceTime"] = reactionsSinceTime;
    }
    if (limit != null) {
      queryParams["limit"] = limit;
    }
    if (fileID != null) {
      queryParams["fileID"] = fileID;
    }

    final response = await _enteDio.get(
      "/social/diff",
      queryParameters: queryParams,
    );
    return SocialDiffResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches comment and reaction counts for all collections.
  ///
  /// Returns a map of collectionID -> count.
  Future<Map<int, int>> fetchCounts() async {
    final response = await _enteDio.get("/comments-reactions/counts");
    final countsData = response.data["counts"] as Map<String, dynamic>?;
    if (countsData == null) {
      return {};
    }
    return countsData.map(
      (key, value) => MapEntry(int.parse(key), value as int),
    );
  }
}
