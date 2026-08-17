import "package:dio/dio.dart";
import "package:photos/models/duplicate_files.dart";

class FilesGateway {
  final Dio _enteDio;

  FilesGateway(this._enteDio);

  Future<int> getFilesSize(List<int> fileIDs) async {
    final response = await _enteDio.post(
      "/files/size",
      data: {"fileIDs": fileIDs},
    );
    return response.data["size"] as int;
  }

  Future<Map<int, int>> getFilesInfo(List<int> fileIDs) async {
    final response = await _enteDio.post(
      "/files/info",
      data: {"fileIDs": fileIDs},
    );
    final Map<int, int> idToSize = {};
    final List<dynamic> result = response.data["filesInfo"] as List<dynamic>;
    for (final fileInfo in result) {
      final int uploadedFileID = fileInfo["id"] as int;
      final int size = fileInfo["fileInfo"]["fileSize"] as int;
      idToSize[uploadedFileID] = size;
    }
    return idToSize;
  }

  Future<DuplicateFilesResponse> getDuplicates() async {
    final response = await _enteDio.get("/files/duplicates");
    return DuplicateFilesResponse.fromMap(
      response.data as Map<String, dynamic>,
    );
  }
}
