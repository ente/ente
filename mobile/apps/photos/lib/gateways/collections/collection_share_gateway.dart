import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/collection_share.dart";
import "package:photos/gateways/collections/models/public_url.dart";
import "package:photos/models/api/collection/user.dart";

const _linkDeviceLimitExceededCode = "LINK_DEVICE_LIMIT_EXCEEDED";

class CollectionShareGateway {
  final Dio _enteDio;

  CollectionShareGateway(this._enteDio);

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

  Future<List<CollectionShareResult>> shareBulk({
    required int recipientUserID,
    required String recipientEmail,
    required CollectionShareSource source,
    required List<BulkCollectionShareItem> collections,
  }) async {
    final response = await _enteDio.post(
      "/collections/share/bulk",
      data: {
        "recipientUserID": recipientUserID,
        "recipientEmail": recipientEmail,
        "source": source.name,
        "collections": collections.map((item) => item.toJson()).toList(),
      },
    );
    return _parseBulkResults(response.data);
  }

  Future<List<CollectionShareResult>> unshareBulk({
    required int recipientUserID,
    required CollectionShareSource source,
    required List<int> collectionIDs,
  }) async {
    final response = await _enteDio.post(
      "/collections/unshare/bulk",
      data: {
        "recipientUserID": recipientUserID,
        "source": source.name,
        "collectionIDs": collectionIDs,
      },
    );
    return _parseBulkResults(response.data);
  }

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

  Future<PublicURL> updateShareUrl({
    required int collectionID,
    required Map<String, dynamic> props,
  }) async {
    final data = Map<String, dynamic>.from(props);
    data["collectionID"] = collectionID;
    final response = await _enteDio.put("/collections/share-url", data: data);
    return PublicURL.fromMap(response.data["result"]);
  }

  Future<void> deleteShareUrl(int collectionID) async {
    await _enteDio.delete("/collections/share-url/$collectionID");
  }

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

List<CollectionShareResult> _parseBulkResults(dynamic data) =>
    (data['results'] as List)
        .map(
          (result) => CollectionShareResult.fromJson(
            Map<String, dynamic>.from(result as Map),
          ),
        )
        .toList();

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
