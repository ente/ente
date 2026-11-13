import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/collection_file_item.dart";

class CollectionFilesGateway {
  final Dio _enteDio;

  CollectionFilesGateway(this._enteDio);

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

  Future<void> removeFiles(int collectionID, List<int> fileIDs) async {
    final response = await _enteDio.post(
      "/collections/v3/remove-files",
      data: {"collectionID": collectionID, "fileIDs": fileIDs},
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to remove files from collection");
    }
  }

  Future<void> suggestDelete(int collectionID, List<int> fileIDs) async {
    final response = await _enteDio.post(
      "/collections/suggest-delete",
      data: {"collectionID": collectionID, "fileIDs": fileIDs},
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to send delete suggestion");
    }
  }

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
