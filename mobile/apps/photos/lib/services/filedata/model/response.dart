import "package:photos/services/filedata/model/file_data.dart";

class FileDataResponse {
  final Map<int, FileDataEntity> data;
  // fetchErrorFileIDs are the fileIDs for whom we failed failed to fetch embeddings
  // from the storage
  final Set<int> fetchErrorFileIDs;
  // pendingIndexFileIDs are the fileIDs that were never indexed
  final Set<int> pendingIndexFileIDs;
  FileDataResponse(
    this.data, {
    required this.fetchErrorFileIDs,
    required this.pendingIndexFileIDs,
  });

  // empty response
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
