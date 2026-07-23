import "package:photos/core/configuration.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/services/filter/collection_ignore.dart";
import "package:photos/services/filter/dedupe_by_upload_id.dart";
import "package:photos/services/filter/filter.dart";
import "package:photos/services/filter/only_uploaded_files_filter.dart";
import "package:photos/services/filter/shared.dart";
import "package:photos/services/filter/upload_ignore.dart";
import "package:photos/services/ignored_files_service.dart";

class DBFilterOptions {
  // typically used for filtering out all files which are present in hidden
  // (searchable files result) or archived collections or both (ex: home
  // timeline)
  Set<int>? ignoredCollectionIDs;
  bool dedupeUploadID;
  bool hideIgnoredForUpload;
  // If true, shared files that are already saved in the users account will be ignored.
  bool ignoreSavedFiles;
  bool onlyUploadedFiles;

  // If true, files owned by other users or uploaded by other users will be ignored.
  bool ignoreSharedItems = false;

  DBFilterOptions({
    this.ignoredCollectionIDs,
    this.hideIgnoredForUpload = false,
    this.dedupeUploadID = true,
    this.ignoreSavedFiles = false,
    this.onlyUploadedFiles = false,
    this.ignoreSharedItems = false,
  });

  static DBFilterOptions dedupeOption = DBFilterOptions(dedupeUploadID: true);
}

Future<List<EnteFile>> applyDBFilters(
  List<EnteFile> files,
  DBFilterOptions? options,
) async {
  if (options == null) {
    return files;
  }
  final List<Filter> filters = [];
  if (options.ignoreSharedItems) {
    filters.add(SkipSharedFileFilter());
  }
  if (options.hideIgnoredForUpload) {
    final Map<String, String> idToReasonMap =
        await IgnoredFilesService.instance.idToIgnoreReasonMap;
    if (idToReasonMap.isNotEmpty) {
      filters.add(UploadIgnoreFilter(idToReasonMap));
    }
  }
  if (options.dedupeUploadID) {
    filters.add(DedupeUploadIDFilter());
  }

  if ((options.ignoredCollectionIDs ?? <int>{}).isNotEmpty ||
      options.ignoreSavedFiles) {
    final collectionIgnoreFilter = CollectionsAndSavedFileFilter(
      options.ignoredCollectionIDs ?? <int>{},
      Configuration.instance.getUserID() ?? 0,
      files,
      options.ignoreSavedFiles,
    );
    filters.add(collectionIgnoreFilter);
  }

  if (options.onlyUploadedFiles) {
    filters.add(OnlyUploadedFilesFilter());
  }

  final List<EnteFile> filterFiles = [];
  for (final file in files) {
    if (filters.every((f) => f.filter(file))) {
      filterFiles.add(file);
    }
  }
  return filterFiles;
}
