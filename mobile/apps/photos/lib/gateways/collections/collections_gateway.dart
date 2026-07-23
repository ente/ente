import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/create_request.dart";
import "package:photos/gateways/collections/models/metadata.dart";

/// Gateway for collection CRUD and metadata API endpoints.
///
/// Handles collection creation, retrieval, deletion, renaming, and
/// metadata updates for the Ente Photos API.
class CollectionsGateway {
  final Dio _enteDio;

  CollectionsGateway(this._enteDio);

  /// Creates a new collection.
  ///
  /// [createRequest] - The request containing collection details.
  ///
  /// Returns the raw collection data from the API response.
  Future<Map<String, dynamic>> createCollection(
    CreateRequest createRequest,
  ) async {
    final response = await _enteDio.post(
      "/collections",
      data: createRequest.toJson(),
    );
    return response.data["collection"];
  }

  /// Gets a collection by its ID.
  ///
  /// [collectionID] - The ID of the collection to retrieve.
  ///
  /// Returns the raw collection data from the API response.
  Future<Map<String, dynamic>> getCollection(int collectionID) async {
    final response = await _enteDio.get("/collections/$collectionID");
    return response.data["collection"];
  }

  /// Deletes a collection.
  ///
  /// [collectionID] - The ID of the collection to delete.
  /// [keepFiles] - If true, files are kept; if false, files are moved to trash.
  Future<void> deleteCollection({
    required int collectionID,
    required bool keepFiles,
  }) async {
    await _enteDio.delete(
      "/collections/v3/$collectionID?keepFiles=$keepFiles&collectionID=$collectionID",
    );
  }

  /// Renames a collection.
  ///
  /// [collectionID] - The ID of the collection to rename.
  /// [encryptedName] - The new name, encrypted with the collection key.
  /// [nameDecryptionNonce] - The nonce used for encryption.
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

  /// Leaves a shared collection.
  ///
  /// [collectionID] - The ID of the collection to leave.
  Future<void> leaveCollection(int collectionID) async {
    await _enteDio.post("/collections/leave/$collectionID");
  }

  /// Gets the diff of files in a collection since a given time.
  ///
  /// [collectionID] - The ID of the collection.
  /// [sinceTime] - The timestamp to get changes since.
  ///
  /// Returns the raw response data containing the diff.
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

  /// Updates the private magic metadata of a collection.
  ///
  /// [request] - The request containing the collection ID and metadata.
  Future<void> updateMagicMetadata(UpdateMagicMetadataRequest request) async {
    await _enteDio.put("/collections/magic-metadata", data: request.toJson());
  }

  /// Updates the public magic metadata of a collection.
  ///
  /// [request] - The request containing the collection ID and metadata.
  Future<void> updatePublicMagicMetadata(
    UpdateMagicMetadataRequest request,
  ) async {
    await _enteDio.put(
      "/collections/public-magic-metadata",
      data: request.toJson(),
    );
  }

  /// Updates the sharee magic metadata of a collection.
  ///
  /// [request] - The request containing the collection ID and metadata.
  Future<void> updateShareeMagicMetadata(
    UpdateMagicMetadataRequest request,
  ) async {
    await _enteDio.put(
      "/collections/sharee-magic-metadata",
      data: request.toJson(),
    );
  }

  /// Joins a collection via a public link.
  ///
  /// [collectionID] - The ID of the collection to join.
  /// [encryptedKey] - The collection key encrypted for the joining user.
  /// [headers] - The public collection authentication headers.
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

  /// Gets all collections for the current user.
  ///
  /// [sinceTime] - The timestamp to get collections updated since.
  /// [source] - The source of the request (e.g., "fg" for foreground).
  ///
  /// Returns the raw response data containing the collections list.
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

  /// Fetches pending removal actions for collections.
  ///
  /// Returns the raw response data containing pending actions.
  Future<Map<String, dynamic>> fetchPendingRemovalActions() async {
    final response = await _enteDio.get("/collection-actions/pending-remove");
    return response.data;
  }

  /// Fetches delete suggestion actions for collections.
  ///
  /// Returns the raw response data containing delete suggestion actions.
  Future<Map<String, dynamic>> fetchDeleteSuggestions() async {
    final response = await _enteDio.get(
      "/collection-actions/delete-suggestions",
    );
    return response.data;
  }

  /// Rejects delete suggestions for specified files.
  ///
  /// [fileIDs] - The list of file IDs to reject delete suggestions for.
  Future<void> rejectDeleteSuggestions(List<int> fileIDs) async {
    await _enteDio.post(
      "/collection-actions/reject-delete-suggestions",
      data: {"fileIDs": fileIDs},
    );
  }
}
