import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/collection_file_item.dart";

/// Gateway for collection file operations API endpoints.
///
/// Handles adding, removing, moving, copying, and restoring files
/// to/from collections.
class CollectionFilesGateway {
  final Dio _enteDio;

  CollectionFilesGateway(this._enteDio);

  /// Adds files to a collection.
  ///
  /// [collectionID] - The collection to add files to.
  /// [files] - List of [CollectionFileItem] containing file IDs and encrypted keys.
  Future<void> addFiles(
    int collectionID,
    List<CollectionFileItem> files,
  ) async {
    await _enteDio.post(
      "/collections/add-files",
      data: {
        "collectionID": collectionID,
        "files": files.map((f) => f.toMap()).toList(),
      },
    );
  }

  /// Restores files from trash to a collection.
  ///
  /// [collectionID] - The collection to restore files to.
  /// [files] - List of [CollectionFileItem] containing file IDs and encrypted keys.
  Future<void> restoreFiles(
    int collectionID,
    List<CollectionFileItem> files,
  ) async {
    await _enteDio.post(
      "/collections/restore-files",
      data: {
        "collectionID": collectionID,
        "files": files.map((f) => f.toMap()).toList(),
      },
    );
  }

  /// Moves files from one collection to another.
  ///
  /// [toCollectionID] - The destination collection.
  /// [fromCollectionID] - The source collection.
  /// [files] - List of [CollectionFileItem] with encrypted keys for the destination.
  Future<void> moveFiles({
    required int toCollectionID,
    required int fromCollectionID,
    required List<CollectionFileItem> files,
  }) async {
    await _enteDio.post(
      "/collections/move-files",
      data: {
        "toCollectionID": toCollectionID,
        "fromCollectionID": fromCollectionID,
        "files": files.map((f) => f.toMap()).toList(),
      },
    );
  }

  /// Removes files from a collection.
  ///
  /// [collectionID] - The collection to remove files from.
  /// [fileIDs] - List of uploaded file IDs to remove.
  Future<void> removeFiles(int collectionID, List<int> fileIDs) async {
    final response = await _enteDio.post(
      "/collections/v3/remove-files",
      data: {"collectionID": collectionID, "fileIDs": fileIDs},
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to remove files from collection");
    }
  }

  /// Suggests files for deletion in a shared collection.
  ///
  /// This is used when a non-owner wants to suggest deleting files
  /// from a shared collection.
  ///
  /// [collectionID] - The collection containing the files.
  /// [fileIDs] - List of uploaded file IDs to suggest for deletion.
  Future<void> suggestDelete(int collectionID, List<int> fileIDs) async {
    final response = await _enteDio.post(
      "/collections/suggest-delete",
      data: {"collectionID": collectionID, "fileIDs": fileIDs},
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to send delete suggestion");
    }
  }

  /// Copies files from one collection to another (for files owned by others).
  ///
  /// This creates new copies of files that are owned by other users.
  ///
  /// [dstCollectionID] - The destination collection (must be owned by current user).
  /// [srcCollectionID] - The source collection.
  /// [files] - List of [CollectionFileItem] with encrypted keys for the destination.
  ///
  /// Returns a map of original file IDs to new copied file IDs.
  Future<Map<int, int>> copyFiles({
    required int dstCollectionID,
    required int srcCollectionID,
    required List<CollectionFileItem> files,
  }) async {
    final response = await _enteDio.post(
      "/files/copy",
      data: {
        "dstCollectionID": dstCollectionID,
        "srcCollectionID": srcCollectionID,
        "files": files.map((f) => f.toMap()).toList(),
      },
    );
    return Map<int, int>.from(
      (response.data["oldToNewFileIDMap"] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), value as int),
      ),
    );
  }
}
