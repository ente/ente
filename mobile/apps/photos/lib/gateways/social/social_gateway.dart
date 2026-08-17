import "package:dio/dio.dart";
import "package:photos/models/social/api_responses.dart";

class SocialGateway {
  final Dio _enteDio;

  SocialGateway(this._enteDio);

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

  Future<void> deleteComment(String commentID) async {
    await _enteDio.delete("/comments/$commentID");
  }

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

  Future<void> deleteReaction(String reactionID) async {
    await _enteDio.delete("/reactions/$reactionID");
  }

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

  Future<LatestUpdatesResponse> fetchLatestUpdates() async {
    final response = await _enteDio.get("/comments-reactions/updated-at");
    return LatestUpdatesResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<AnonProfilesResponse> fetchAnonProfiles(int collectionID) async {
    final response = await _enteDio.get(
      "/social/anon-profiles",
      queryParameters: {"collectionID": collectionID},
    );
    return AnonProfilesResponse.fromJson(response.data as Map<String, dynamic>);
  }

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
