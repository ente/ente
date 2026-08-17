import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import 'package:photos/models/search/search_result.dart';
import "package:photos/models/search/search_types.dart";

class DeviceAlbumSearchResult extends SearchResult {
  final DeviceCollection deviceCollection;

  DeviceAlbumSearchResult(this.deviceCollection);

  @override
  ResultType type() {
    return ResultType.deviceCollection;
  }

  @override
  String name() {
    return deviceCollection.name;
  }

  @override
  EnteFile? previewThumbnail() {
    return deviceCollection.thumbnail;
  }

  @override
  List<EnteFile> resultFiles() {
    // Device album results open the folder directly; do not call this method.
    throw UnimplementedError();
  }

  @override
  HierarchicalSearchFilter getHierarchicalSearchFilter() {
    // Device albums do not support hierarchical filtering.
    throw UnimplementedError();
  }
}
