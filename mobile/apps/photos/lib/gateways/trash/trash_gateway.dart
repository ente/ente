import "package:dio/dio.dart";

class TrashGateway {
  final Dio _enteDio;

  TrashGateway(this._enteDio);

  Future<Map<String, dynamic>> getDiff(int sinceTime) async {
    final response = await _enteDio.get(
      "/trash/v2/diff",
      queryParameters: {"sinceTime": sinceTime},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> trashFiles(List<Map<String, dynamic>> items) async {
    await _enteDio.post("/files/trash", data: {"items": items});
  }

  Future<void> deleteFiles(List<int> fileIDs) async {
    await _enteDio.post("/trash/delete", data: {"fileIDs": fileIDs});
  }

  Future<void> emptyTrash(int lastUpdatedAt) async {
    await _enteDio.post("/trash/empty", data: {"lastUpdatedAt": lastUpdatedAt});
  }
}
