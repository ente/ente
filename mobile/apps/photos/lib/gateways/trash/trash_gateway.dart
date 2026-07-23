import "package:dio/dio.dart";

/// Gateway for trash API endpoints.
///
/// Handles trash operations like fetching trash diff, moving files to trash,
/// permanently deleting files, and emptying trash.
class TrashGateway {
  final Dio _enteDio;

  TrashGateway(this._enteDio);

  /// Gets the trash diff since the given time.
  ///
  /// [sinceTime] - Unix timestamp in microseconds to get changes since.
  ///
  /// Returns the raw response data containing the trash diff.
  Future<Map<String, dynamic>> getDiff(int sinceTime) async {
    final response = await _enteDio.get(
      "/trash/v2/diff",
      queryParameters: {"sinceTime": sinceTime},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Moves files to trash.
  ///
  /// [items] - List of maps containing fileID and collectionID for each file.
  Future<void> trashFiles(List<Map<String, dynamic>> items) async {
    await _enteDio.post("/files/trash", data: {"items": items});
  }

  /// Permanently deletes files from trash.
  ///
  /// [fileIDs] - List of file IDs to permanently delete.
  Future<void> deleteFiles(List<int> fileIDs) async {
    await _enteDio.post("/trash/delete", data: {"fileIDs": fileIDs});
  }

  /// Empties the trash, permanently deleting all trashed files.
  ///
  /// [lastUpdatedAt] - Last sync timestamp to ensure consistency.
  Future<void> emptyTrash(int lastUpdatedAt) async {
    await _enteDio.post("/trash/empty", data: {"lastUpdatedAt": lastUpdatedAt});
  }
}
