import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";

class OnlyThemFilter extends HierarchicalSearchFilter {
  final List<FaceFilter> faceFilters;
  final int occurrence;

  /// Workaround to avoid passing context to the filter to avoid making context
  /// a long lived object.
  final String onlyThemString;

  OnlyThemFilter({
    required this.faceFilters,
    required this.occurrence,
    required this.onlyThemString,
    super.filterTypeName = "onlyThemFilter",
  });

  @override
  String name() {
    return onlyThemString;
  }

  @override
  int relevance() {
    return occurrence;
  }

  @override
  SearchFilterIcon icon() {
    return HugeIcons.strokeRoundedUserMultiple;
  }

  @override
  bool isMatch(EnteFile file) {
    throw UnimplementedError();
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is OnlyThemFilter) {
      return true;
    }
    return false;
  }
}
