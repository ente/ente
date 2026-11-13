import "package:photos/services/filedata/model/file_data.dart";

class FileDataResponse {
  final Map<int, FileDataEntity> data;
  final Set<int> fetchErrorFileIDs;
  final Set<int> pendingIndexFileIDs;
  FileDataResponse(
    this.data, {
    required this.fetchErrorFileIDs,
    required this.pendingIndexFileIDs,
  });

  FileDataResponse.empty()
    : data = {},
      fetchErrorFileIDs = {},
      pendingIndexFileIDs = {};

  String debugLog() {
    final nonZeroFetchErrorFileIDs = fetchErrorFileIDs.isNotEmpty
        ? 'errorForFileIDs: ${fetchErrorFileIDs.length}'
        : '';
    final nonZeroPendingIndexFileIDs = pendingIndexFileIDs.isNotEmpty
        ? ', pendingIndexFileIDs: ${pendingIndexFileIDs.length}'
        : '';
    return 'MLRemote(mlData: ${data.length}$nonZeroFetchErrorFileIDs$nonZeroPendingIndexFileIDs)';
  }
}
