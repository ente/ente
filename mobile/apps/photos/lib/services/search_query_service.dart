import "dart:async";

import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/search/search_query_utils.dart";

class SearchQueryService {
  SearchQueryService(this._searchService);

  static const _localFileIDsSearchPrefix = "local_ids:";
  static const _uploadedFileIDsSearchPrefix = "uploaded_ids:";

  final SearchService _searchService;
  final _logger = Logger("SearchQueryService");

  Stream<List<SearchResult>> search(
    BuildContext context,
    String query, {
    bool Function(Collection)? collectionFilter,
    Future<List<SearchResult>> Function()? magicSearch,
  }) {
    if (query.isEmpty) {
      return Stream<List<SearchResult>>.multi((controller) {
        controller.add([]);
        controller.close();
      });
    }

    if (query.startsWith(_uploadedFileIDsSearchPrefix)) {
      final uploadedFileIDs = query
          .substring(_uploadedFileIDsSearchPrefix.length)
          .split(",")
          .map((value) => int.tryParse(value.trim()))
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
      return Stream.fromFuture(
        _resultsOrEmpty(
          _searchService.getUploadedFileIDsSearchResults(
            query,
            uploadedFileIDs,
          ),
        ),
      );
    }

    if (query.startsWith(_localFileIDsSearchPrefix)) {
      final localFileIDs = query
          .substring(_localFileIDsSearchPrefix.length)
          .split(",")
          .map((value) => value.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      return Stream.fromFuture(
        _resultsOrEmpty(
          _searchService.getLocalFileIDsSearchResults(query, localFileIDs),
        ),
      );
    }

    final searches = <Future<List<SearchResult>>>[
      if (isYearSearchQuery(query)) _searchService.getYearSearchResults(query),
      _searchService.getHolidaySearchResults(context, query),
      _searchService.getFileTypeResults(context, query),
      _searchService.getCaptionAndNameResults(query),
      _searchService.getFileExtensionResults(query),
      _searchService.getLocationResults(context, query),
      _searchService
          .getAllFace(null, minClusterSize: 10)
          .then(
            (results) => results
                .where(
                  (result) =>
                      result.name().toLowerCase().contains(query.toLowerCase()),
                )
                .toList(),
          ),
      _searchService.getCollectionSearchResults(
        query,
        collectionFilter: collectionFilter,
      ),
      _searchService.getDeviceCollectionSearchResults(query),
      _searchService.getMonthSearchResults(context, query),
      _searchService.getDateResults(context, query),
      magicSearch?.call() ??
          _searchService.getMagicSearchResults(context, query),
      _searchService.getContactSearchResults(query),
    ];
    final controller = StreamController<List<SearchResult>>();
    var remaining = searches.length;
    for (final future in searches) {
      _resultsOrEmpty(future).then((results) {
        if (controller.isClosed) return;
        controller.add(results);
        if (--remaining == 0) unawaited(controller.close());
      });
    }
    return controller.stream.asBroadcastStream();
  }

  Future<List<SearchResult>> _resultsOrEmpty(
    Future<List<SearchResult>> future,
  ) => future.onError((error, stack) {
    _logger.warning("Could not complete search provider", error, stack);
    return <SearchResult>[];
  });
}
