import "package:flutter/cupertino.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/search_constants.dart";
import 'package:photos/models/search/search_result.dart';
import "package:photos/models/search/search_types.dart";

class GenericSearchResult extends SearchResult {
  final String _name;
  final List<EnteFile> _files;
  final ResultType _type;
  final Function(BuildContext context)? onResultTap;
  final Map<String, dynamic> params;
  final HierarchicalSearchFilter hierarchicalSearchFilter;

  GenericSearchResult(
    this._type,
    this._name,
    this._files, {
    required this.hierarchicalSearchFilter,
    this.onResultTap,
    this.params = const {},
  });

  @override
  String name() {
    return _name;
  }

  @override
  ResultType type() {
    return _type;
  }

  @override
  String heroTag() {
    final locationID = params[kLocationParamID];
    return locationID != null ? '${type()}_$locationID' : super.heroTag();
  }

  @override
  EnteFile? previewThumbnail() {
    if (type() == ResultType.shared) {
      throw Exception(
        "Do not use first file as thumbnail. Use user avatar instead.",
      );
    }
    return _files.isEmpty ? null : _files.first;
  }

  @override
  List<EnteFile> resultFiles() {
    return _files;
  }

  int fileCount() {
    return _files.length;
  }

  @override
  HierarchicalSearchFilter getHierarchicalSearchFilter() {
    return hierarchicalSearchFilter;
  }
}
