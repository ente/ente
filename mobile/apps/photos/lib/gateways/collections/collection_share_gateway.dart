import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/public_url.dart";
import "package:photos/models/api/collection/user.dart";

const _linkDeviceLimitExceededCode = "LINK_DEVICE_LIMIT_EXCEEDED";

/// Gateway for collection sharing API endpoints.
///
/// Handles sharing collections with other users and managing public links.
class CollectionShareGateway {
  final Dio _enteDio;

  CollectionShareGateway(this._enteDio);

  /// Gets the list of users a collection is shared with.
  ///
  /// [collectionID] - The collection to get sharees for.
  ///
  /// Returns a list of [User] objects representing the sharees.
  Future<List<User>> getSharees(int collectionID) async {
    final response = await _enteDio.get(
      "/collections/sharees",
      queryParameters: {"collectionID": collectionID},
    );
    final sharees = <User>[];
    for (final user in response.data["sharees"]) {
      sharees.add(User.fromMap(user));
    }
    return sharees;
  }

  /// Shares a collection with another user.
  ///
  /// [collectionID] - The collection to share.
  /// [email] - The email of the user to share with.
  /// [encryptedKey] - The collection key encrypted for the recipient.
  /// [role] - The role to grant (e.g., "VIEWER", "COLLABORATOR").
  ///
  /// Returns the updated list of sharees.
  Future<List<User>> share({
    required int collectionID,
    required String email,
    required String encryptedKey,
    required String role,
  }) async {
    final response = await _enteDio.post(
      "/collections/share",
      data: {
        "collectionID": collectionID,
        "email": email,
        "encryptedKey": encryptedKey,
        "role": role,
      },
    );
    final sharees = <User>[];
    for (final user in response.data["sharees"]) {
      sharees.add(User.fromMap(user));
    }
    return sharees;
  }

  /// Removes sharing of a collection with a user.
  ///
  /// [collectionID] - The collection to unshare.
  /// [email] - The email of the user to remove sharing for.
  ///
  /// Returns the updated list of sharees.
  Future<List<User>> unshare({
    required int collectionID,
    required String email,
  }) async {
    final response = await _enteDio.post(
      "/collections/unshare",
      data: {"collectionID": collectionID, "email": email},
    );
    final sharees = <User>[];
    for (final user in response.data["sharees"]) {
      sharees.add(User.fromMap(user));
    }
    return sharees;
  }

  /// Creates a public share URL for a collection.
  ///
  /// [collectionID] - The collection to create a public link for.
  /// [enableCollect] - Whether to allow others to add files.
  /// [enableJoin] - Whether to allow others to join the album.
  /// [enableComment] - Whether to allow comments.
  ///
  /// Returns the created [PublicURL].
  Future<PublicURL> createShareUrl({
    required int collectionID,
    bool enableCollect = false,
    bool enableJoin = false,
    bool enableComment = true,
  }) async {
    final response = await _enteDio.post(
      "/collections/share-url",
      data: {
        "collectionID": collectionID,
        "enableCollect": enableCollect,
        "enableJoin": enableJoin,
        "enableComment": enableComment,
      },
    );
    return PublicURL.fromMap(response.data["result"]);
  }

  /// Updates a public share URL for a collection.
  ///
  /// [collectionID] - The collection whose public link to update.
  /// [props] - Map of properties to update on the public URL.
  ///
  /// Returns the updated [PublicURL].
  Future<PublicURL> updateShareUrl({
    required int collectionID,
    required Map<String, dynamic> props,
  }) async {
    final data = Map<String, dynamic>.from(props);
    data["collectionID"] = collectionID;
    final response = await _enteDio.put("/collections/share-url", data: data);
    return PublicURL.fromMap(response.data["result"]);
  }

  /// Deletes a public share URL for a collection.
  ///
  /// [collectionID] - The collection whose public link to delete.
  Future<void> deleteShareUrl(int collectionID) async {
    await _enteDio.delete("/collections/share-url/$collectionID");
  }

  /// Gets information about a public collection.
  ///
  /// [authToken] - The public access token from the share URL.
  ///
  /// Returns the raw response data containing collection information.
  ///
  /// Throws:
  /// - [PublicCollectionInfoUnauthorizedException] when the token is invalid.
  /// - [PublicCollectionInfoExpiredException] when the link has expired/disabled.
  /// - [PublicCollectionDeviceLimitExceededException] when the link device
  ///   limit is reached.
  /// - [PublicCollectionRateLimitedException] when API rate limits are hit.
  Future<Map<String, dynamic>> getPublicCollectionInfo(String authToken) async {
    try {
      final response = await _enteDio.get(
        "/public-collection/info",
        options: Options(headers: {"X-Auth-Access-Token": authToken}),
      );
      return response.data;
    } on DioException catch (e) {
      switch (e.response?.statusCode) {
        case 401:
          throw PublicCollectionInfoUnauthorizedException();
        case 410:
          throw PublicCollectionInfoExpiredException();
        case 403:
          if (_hasErrorCode(e.response?.data, _linkDeviceLimitExceededCode)) {
            throw PublicCollectionDeviceLimitExceededException();
          }
          rethrow;
        case 429:
          final errorMessage = _extractErrorMessage(e.response?.data);
          if (errorMessage?.toLowerCase().contains("device limit") ?? false) {
            throw PublicCollectionDeviceLimitExceededException();
          }
          throw PublicCollectionRateLimitedException();
        default:
          rethrow;
      }
    }
  }

  /// Verifies the password for a password-protected public collection.
  ///
  /// [authToken] - The public access token from the share URL.
  /// [passwordHash] - The hash of the password to verify.
  ///
  /// Returns the JWT token if verification succeeds.
  Future<String> verifyPublicPassword({
    required String authToken,
    required String passwordHash,
  }) async {
    final response = await _enteDio.post(
      "/public-collection/verify-password",
      data: {"passHash": passwordHash},
      options: Options(headers: {"X-Auth-Access-Token": authToken}),
    );
    return response.data["jwtToken"];
  }

  /// Gets the diff of files in a public collection.
  ///
  /// [headers] - The authentication headers for the public collection.
  /// [sinceTime] - The timestamp to get changes since.
  ///
  /// Returns the raw response data containing the diff.
  Future<Map<String, dynamic>> getPublicDiff({
    required Map<String, String> headers,
    required int sinceTime,
  }) async {
    final response = await _enteDio.get(
      "/public-collection/diff",
      options: Options(headers: headers),
      queryParameters: {"sinceTime": sinceTime},
    );
    return response.data;
  }
}

String? _extractErrorMessage(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data["error"]?.toString();
  }
  if (data is Map) {
    return data["error"]?.toString();
  }
  return null;
}

bool _hasErrorCode(dynamic data, String code) {
  if (data is Map<String, dynamic>) {
    return data["code"] == code;
  }
  if (data is Map) {
    return data["code"] == code;
  }
  return false;
}

class PublicCollectionInfoUnauthorizedException implements Exception {}

class PublicCollectionInfoExpiredException implements Exception {}

class PublicCollectionDeviceLimitExceededException implements Exception {}

class PublicCollectionRateLimitedException implements Exception {}
