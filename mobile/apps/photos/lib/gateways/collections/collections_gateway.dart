import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/create_request.dart";
import "package:photos/gateways/collections/models/metadata.dart";

class CollectionsGateway {
  final Dio _enteDio;

  CollectionsGateway(this._enteDio);

  Future<Map<String, dynamic>> createCollection(
    CreateRequest createRequest,
  ) async {
    final response = await _enteDio.post(
      "/collections",
      data: createRequest.toJson(),
    );
    return response.data["collection"];
  }

  Future<Map<String, dynamic>> getCollection(int collectionID) async {
    final response = await _enteDio.get("/collections/$collectionID");
    return response.data["collection"];
  }

  Future<void> deleteCollection({
    required int collectionID,
    required bool keepFiles,
  }) async {
    await _enteDio.delete(
      "/collections/v3/$collectionID?keepFiles=$keepFiles&collectionID=$collectionID",
    );
  }

  Future<void> renameCollection({
    required int collectionID,
    required String encryptedName,
    required String nameDecryptionNonce,
  }) async {
    await _enteDio.post(
      "/collections/rename",
      data: {
        "collectionID": collectionID,
        "encryptedName": encryptedName,
        "nameDecryptionNonce": nameDecryptionNonce,
      },
    );
  }

  Future<void> leaveCollection(int collectionID) async {
    await _enteDio.post("/collections/leave/$collectionID");
  }

  Future<Map<String, dynamic>> getDiff({
    required int collectionID,
    required int sinceTime,
  }) async {
    final response = await _enteDio.get(
      "/collections/v2/diff",
      queryParameters: {"collectionID": collectionID, "sinceTime": sinceTime},
    );
    return response.data;
  }

  Future<void> updateMagicMetadata(UpdateMagicMetadataRequest request) async {
    await _enteDio.put("/collections/magic-metadata", data: request.toJson());
  }

  Future<void> updatePublicMagicMetadata(
    UpdateMagicMetadataRequest request,
  ) async {
    await _enteDio.put(
      "/collections/public-magic-metadata",
      data: request.toJson(),
    );
  }

  Future<void> updateShareeMagicMetadata(
    UpdateMagicMetadataRequest request,
  ) async {
    await _enteDio.put(
      "/collections/sharee-magic-metadata",
      data: request.toJson(),
    );
  }

  Future<void> joinViaLink({
    required int collectionID,
    required String encryptedKey,
    required Map<String, String> headers,
  }) async {
    await _enteDio.post(
      "/collections/join-link",
      data: {"collectionID": collectionID, "encryptedKey": encryptedKey},
      options: Options(headers: headers),
    );
  }

  Future<Map<String, dynamic>> getAll({
    required int sinceTime,
    required String source,
  }) async {
    final response = await _enteDio.get(
      "/collections/v2",
      queryParameters: {"sinceTime": sinceTime, "source": source},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> fetchPendingRemovalActions() async {
    final response = await _enteDio.get("/collection-actions/pending-remove");
    return response.data;
  }

  Future<Map<String, dynamic>> fetchDeleteSuggestions() async {
    final response = await _enteDio.get(
      "/collection-actions/delete-suggestions",
    );
    return response.data;
  }

  Future<void> rejectDeleteSuggestions(List<int> fileIDs) async {
    await _enteDio.post(
      "/collection-actions/reject-delete-suggestions",
      data: {"fileIDs": fileIDs},
    );
  }
}
