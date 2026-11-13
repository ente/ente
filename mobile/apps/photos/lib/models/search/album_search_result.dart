import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/search/hierarchical/album_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import 'package:photos/models/search/search_result.dart';
import "package:photos/models/search/search_types.dart";

class AlbumSearchResult extends SearchResult {
  final CollectionWithThumbnail collectionWithThumbnail;

  AlbumSearchResult(this.collectionWithThumbnail);

  @override
  ResultType type() {
    return ResultType.collection;
  }

  @override
  String name() {
    return collectionWithThumbnail.collection.displayName;
  }

  @override
  EnteFile? previewThumbnail() {
    return collectionWithThumbnail.thumbnail;
  }

  @override
  List<EnteFile> resultFiles() {
    // Album results open the album directly; this method must not be called.
    throw UnimplementedError();
  }

  @override
  HierarchicalSearchFilter getHierarchicalSearchFilter() {
    return AlbumFilter(
      collectionID: collectionWithThumbnail.collection.id,
      albumName: collectionWithThumbnail.collection.displayName,
      occurrence: kMostRelevantFilter,
    );
  }
}
